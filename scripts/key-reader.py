#!/usr/bin/env python3
"""Read Linux keyboard and mouse-button events and emit labels as JSON.

The process never stores input. Each emitted line is either a status object or
one key/chord object for the Quickshell service.
"""

from __future__ import annotations

import argparse
import errno
import fcntl
import glob
import json
import os
import selectors
import struct
import sys
import time


EV_SYN = 0x00
EV_KEY = 0x01
SYN_REPORT = 0
SYN_DROPPED = 3
KEY_ENTER = 28
KEY_A = 30
KEY_Z = 44
KEY_SPACE = 57
BTN_LEFT = 0x110
BTN_RIGHT = 0x111
BTN_MIDDLE = 0x112
POINTER_BUTTON_NAMES = {
    BTN_LEFT: "LMB",
    BTN_RIGHT: "RMB",
    BTN_MIDDLE: "MMB",
    0x113: "MOUSE SIDE",
    0x114: "MOUSE EXTRA",
    0x115: "MOUSE FORWARD",
    0x116: "MOUSE BACK",
    0x117: "MOUSE TASK",
}
POINTER_BUTTONS = tuple(POINTER_BUTTON_NAMES)
EVENT = struct.Struct("llHHI")
BITS_PER_LONG = struct.calcsize("L") * 8
MAX_OUTPUT_EVENTS_PER_SECOND = 120.0
MAX_OUTPUT_BURST = 120.0
MAX_READ_BATCHES = 16
MAX_ERROR_DETAIL_LENGTH = 256
KEY_BITMAP_BYTES = 96

MODIFIERS = {
    29: "CTRL",       # left ctrl
    97: "CTRL",       # right ctrl
    42: "SHIFT",      # left shift
    54: "SHIFT",      # right shift
    56: "ALT",        # left alt
    100: "ALT",       # right alt / AltGr
    125: "SUPER",     # left meta
    126: "SUPER",     # right meta
}
MODIFIER_ORDER = ("CTRL", "ALT", "SHIFT", "SUPER")


KEY_NAMES = {
    1: "ESC", 2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7",
    9: "8", 10: "9", 11: "0", 12: "-", 13: "=", 14: "BACKSPACE",
    15: "TAB", 16: "Q", 17: "W", 18: "E", 19: "R", 20: "T", 21: "Y",
    22: "U", 23: "I", 24: "O", 25: "P", 26: "[", 27: "]", 28: "ENTER",
    29: "CTRL", 30: "A", 31: "S", 32: "D", 33: "F", 34: "G", 35: "H",
    36: "J", 37: "K", 38: "L", 39: ";", 40: "'", 41: "`", 42: "SHIFT",
    43: "\\", 44: "Z", 45: "X", 46: "C", 47: "V", 48: "B", 49: "N",
    50: "M", 51: ",", 52: ".", 53: "/", 54: "SHIFT", 55: "NUM *",
    56: "ALT", 57: "SPACE", 58: "CAPS LOCK", 59: "F1", 60: "F2", 61: "F3",
    62: "F4", 63: "F5", 64: "F6", 65: "F7", 66: "F8", 67: "F9", 68: "F10",
    69: "NUM LOCK", 70: "SCROLL LOCK", 71: "NUM 7", 72: "NUM 8", 73: "NUM 9",
    74: "NUM -", 75: "NUM 4", 76: "NUM 5", 77: "NUM 6", 78: "NUM +",
    79: "NUM 1", 80: "NUM 2", 81: "NUM 3", 82: "NUM 0", 83: "NUM .",
    87: "F11", 88: "F12", 96: "NUM ENTER", 97: "CTRL", 98: "NUM /",
    99: "PRINT SCREEN", 100: "ALT", 102: "HOME", 103: "UP", 104: "PAGE UP",
    105: "LEFT", 106: "RIGHT", 107: "END", 108: "DOWN", 109: "PAGE DOWN",
    110: "INSERT", 111: "DELETE", 113: "MUTE", 114: "VOLUME DOWN",
    115: "VOLUME UP", 116: "POWER", 119: "PAUSE", 125: "SUPER", 126: "SUPER",
    127: "MENU", 128: "STOP", 139: "MENU", 142: "SLEEP", 150: "BROWSER",
    155: "MAIL", 158: "BACK", 159: "FORWARD", 163: "NEXT TRACK",
    164: "PLAY/PAUSE", 165: "PREVIOUS TRACK", 166: "STOP", 172: "HOME PAGE",
    173: "REFRESH", 183: "F13", 184: "F14", 185: "F15", 186: "F16",
    187: "F17", 188: "F18", 189: "F19", 190: "F20", 191: "F21",
    192: "F22", 193: "F23", 194: "F24", 217: "SEARCH", 224: "BRIGHTNESS DOWN",
    225: "BRIGHTNESS UP", 226: "MEDIA", 227: "DISPLAY", 240: "UNKNOWN",
    248: "MIC MUTE", **POINTER_BUTTON_NAMES,
}


def emit(payload: dict) -> None:
    print(json.dumps(payload, separators=(",", ":")), flush=True)


def error_detail(error: BaseException) -> str:
    """Return a bounded diagnostic that never includes captured input."""
    detail = f"Input reader failed: {type(error).__name__}: {error}"
    return detail[:MAX_ERROR_DETAIL_LENGTH]


def _read_header_names() -> dict[int, str]:
    """Use Linux headers as a fallback for keys not in the friendly table."""
    result: dict[int, str] = {}
    path = "/usr/include/linux/input-event-codes.h"
    try:
        with open(path, encoding="utf-8") as source:
            for line in source:
                fields = line.strip().split()
                if len(fields) < 3 or fields[0] != "#define" or not fields[1].startswith("KEY_"):
                    continue
                try:
                    code = int(fields[2], 0)
                except ValueError:
                    continue
                macro = fields[1][4:]
                if macro in {"RESERVED", "MIN_INTERESTING", "MAX", "CNT"}:
                    continue
                result.setdefault(code, macro.replace("_", " "))
    except OSError:
        pass
    return result


HEADER_KEY_NAMES = _read_header_names()


def key_name(code: int) -> str:
    return KEY_NAMES.get(code, HEADER_KEY_NAMES.get(code, f"KEY {code}"))


def displayable_code(code: int) -> bool:
    """Exclude touch/tool buttons while retaining keyboard and mouse keys."""
    return code in POINTER_BUTTON_NAMES or code in KEY_NAMES or code in HEADER_KEY_NAMES


class ModifierState:
    def __init__(self, label: str) -> None:
        self.label = label
        self.used = False


class KeyChordFormatter:
    """Convert raw EV_KEY transitions into displayable key/chord lists."""

    def __init__(self) -> None:
        self._pressed: dict[tuple[str, int], ModifierState] = {}

    def _held_labels(self) -> list[str]:
        held = {state.label for state in self._pressed.values()}
        return [label for label in MODIFIER_ORDER if label in held]

    def handle(self, code: int, value: int, source: str = "keyboard") -> list[list[str]]:
        token = (source, code)

        if code in MODIFIERS:
            if value == 1:
                self._pressed[token] = ModifierState(MODIFIERS[code])
            elif value == 0:
                state = self._pressed.pop(token, None)
                if state is not None and not state.used:
                    return [[state.label]]
            return []

        # Only the initial key-down is displayed. Release (0) and repeat (2)
        # are intentionally ignored.
        if value != 1:
            return []

        labels = self._held_labels()
        for state in self._pressed.values():
            state.used = True
        labels.append(key_name(code))
        return [labels]

    def release_source(self, source: str) -> None:
        self._pressed = {
            token: state for token, state in self._pressed.items()
            if token[0] != source
        }

    def sync_source_modifiers(self, source: str, pressed_codes: set[int]) -> None:
        """Replace one device's modifier state after an input queue overrun."""
        self.release_source(source)
        for code in pressed_codes:
            if code in MODIFIERS:
                state = ModifierState(MODIFIERS[code])
                # The events leading to this state were lost, so suppress a
                # possibly-spurious standalone modifier on its next release.
                state.used = True
                self._pressed[(source, code)] = state


class TokenBucket:
    """Bound event output while allowing short bursts of normal input."""

    def __init__(
        self,
        rate: float = MAX_OUTPUT_EVENTS_PER_SECOND,
        burst: float = MAX_OUTPUT_BURST,
        clock=time.monotonic,
    ) -> None:
        self.rate = max(0.0, float(rate))
        self.burst = max(1.0, float(burst))
        self.clock = clock
        self.tokens = self.burst
        self.updated_at = self.clock()

    def allow(self) -> bool:
        now = self.clock()
        elapsed = max(0.0, now - self.updated_at)
        if now >= self.updated_at:
            self.updated_at = now
        self.tokens = min(self.burst, self.tokens + elapsed * self.rate)
        if self.tokens < 1.0:
            return False
        self.tokens -= 1.0
        return True


def _ioc_read(number: int, size: int) -> int:
    return (2 << 30) | (size << 16) | (ord("E") << 8) | number


def _event_bits(fd: int, event_type: int, size: int) -> bytes:
    buffer = bytearray(size)
    fcntl.ioctl(fd, _ioc_read(0x20 + event_type, size), buffer, True)
    return bytes(buffer)


def _pressed_modifier_codes(fd: int) -> set[int]:
    """Return modifiers currently held according to the kernel."""
    buffer = bytearray(KEY_BITMAP_BYTES)
    fcntl.ioctl(fd, _ioc_read(0x18, len(buffer)), buffer, True)
    bits = bytes(buffer)
    return {code for code in MODIFIERS if _bit_is_set(bits, code)}


def _bit_is_set(bits: bytes, bit: int) -> bool:
    byte = bit // 8
    return byte < len(bits) and bool(bits[byte] & (1 << (bit % 8)))


def _is_supported_input_fd(fd: int) -> bool:
    event_types = _event_bits(fd, 0, 16)
    if not _bit_is_set(event_types, EV_KEY):
        return False
    keys = _event_bits(fd, EV_KEY, KEY_BITMAP_BYTES)
    is_keyboard = all(
        _bit_is_set(keys, code) for code in (KEY_ENTER, KEY_A, KEY_Z, KEY_SPACE)
    )
    has_pointer_button = any(_bit_is_set(keys, code) for code in POINTER_BUTTONS)
    return is_keyboard or has_pointer_button


def _sysfs_is_supported_input(path: str) -> bool:
    name = os.path.basename(path)
    capability = f"/sys/class/input/{name}/device/capabilities/key"
    try:
        with open(capability, encoding="ascii") as source:
            words = source.read().strip().split()
        bitmap = 0
        for index, word in enumerate(reversed(words)):
            bitmap |= int(word, 16) << (index * BITS_PER_LONG)
        is_keyboard = all(
            bitmap & (1 << code) for code in (KEY_ENTER, KEY_A, KEY_Z, KEY_SPACE)
        )
        has_pointer_button = any(bitmap & (1 << code) for code in POINTER_BUTTONS)
        return is_keyboard or has_pointer_button
    except (OSError, ValueError):
        # If sysfs cannot classify it, try opening it. The ioctl check remains
        # authoritative once access is available.
        return True


class EventReader:
    def __init__(self) -> None:
        self.selector = selectors.DefaultSelector()
        self.devices: dict[str, int] = {}
        self.formatter = KeyChordFormatter()
        self.output_limiter = TokenBucket()
        self.desynced_sources: set[str] = set()
        self._last_status: tuple[str, str, int] | None = None

    def status(self, state: str, detail: str = "") -> None:
        signature = (state, detail, len(self.devices))
        if signature == self._last_status:
            return
        self._last_status = signature
        emit({"type": "status", "state": state, "detail": detail, "devices": len(self.devices)})

    def close_device(self, path: str) -> None:
        fd = self.devices.pop(path, None)
        if fd is None:
            return
        self.desynced_sources.discard(path)
        self.formatter.release_source(path)
        try:
            self.selector.unregister(fd)
        except (KeyError, ValueError):
            pass
        try:
            os.close(fd)
        except OSError:
            pass

    def rescan(self) -> None:
        paths = set(glob.glob("/dev/input/event*"))
        for old_path in list(self.devices):
            if old_path not in paths:
                self.close_device(old_path)

        denied = 0
        candidates = 0
        for path in sorted(paths):
            if path in self.devices or not _sysfs_is_supported_input(path):
                continue
            candidates += 1
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
            except PermissionError:
                denied += 1
                continue
            except OSError:
                continue

            try:
                if not _is_supported_input_fd(fd):
                    os.close(fd)
                    continue
                self.devices[path] = fd
                self.selector.register(fd, selectors.EVENT_READ, path)
            except OSError:
                os.close(fd)

        if self.devices and denied:
            readable = len(self.devices)
            self.status(
                "degraded",
                f"{readable} input device" + ("s" if readable != 1 else "")
                + f" available; {denied} unavailable",
            )
        elif self.devices:
            count = len(self.devices)
            self.status("ready", f"{count} input device" + ("s" if count != 1 else ""))
        elif denied:
            self.status(
                "permission-denied",
                f"Permission is required for {denied} input device"
                + ("s" if denied != 1 else ""),
            )
        elif candidates or paths:
            self.status("no-inputs", "No readable keyboard or mouse device was found")
        else:
            self.status("no-inputs", "No keyboard or mouse event devices were found")

    def read_device(self, path: str, fd: int) -> None:
        try:
            # Bound each selector dispatch so a faulty or synthetic device
            # cannot monopolize the reader loop indefinitely.
            for _batch in range(MAX_READ_BATCHES):
                data = os.read(fd, EVENT.size * 64)
                if not data:
                    self.close_device(path)
                    return
                usable = len(data) - (len(data) % EVENT.size)
                for _seconds, _micros, event_type, code, value in EVENT.iter_unpack(data[:usable]):
                    if event_type == EV_SYN and code == SYN_DROPPED:
                        self.desynced_sources.add(path)
                        self.formatter.release_source(path)
                        continue
                    if path in self.desynced_sources:
                        if event_type == EV_SYN and code == SYN_REPORT:
                            self.desynced_sources.discard(path)
                            self.formatter.sync_source_modifiers(
                                path, _pressed_modifier_codes(fd)
                            )
                        continue
                    if event_type != EV_KEY or not displayable_code(code):
                        continue
                    for keys in self.formatter.handle(code, value, path):
                        if self.output_limiter.allow():
                            emit({"type": "key", "keys": keys})
        except BlockingIOError:
            return
        except OSError as error:
            if error.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
                self.close_device(path)

    def run(self) -> None:
        last_scan = 0.0
        while True:
            now = time.monotonic()
            if now - last_scan >= 2.0:
                self.rescan()
                last_scan = now

            for key, _mask in self.selector.select(timeout=0.5):
                self.read_device(str(key.data), int(key.fd))


def demo() -> None:
    emit({"type": "status", "state": "ready", "detail": "Demo input", "devices": 1})
    for keys in (["SUPER", "L"], ["SUPER", "RMB"], ["LMB"], ["SPACE"]):
        emit({"type": "key", "keys": keys})


def main() -> int:
    parser = argparse.ArgumentParser(description="Emit global keyboard and mouse chords as JSON lines")
    parser.add_argument("--demo", action="store_true", help="emit sample chords and exit")
    args = parser.parse_args()
    if args.demo:
        demo()
        return 0

    try:
        EventReader().run()
    except KeyboardInterrupt:
        return 0
    except Exception as error:  # Keep error output free of captured key values.
        print(error_detail(error), file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
