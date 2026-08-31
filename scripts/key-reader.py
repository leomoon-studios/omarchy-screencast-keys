#!/usr/bin/env python3
"""Read Linux keyboard events and emit privacy-preserving key labels as JSON.

The process never stores input. Each emitted line is either a status object or
one key/chord object for the Quickshell overlay.
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


EV_KEY = 0x01
KEY_ENTER = 28
KEY_A = 30
KEY_Z = 44
KEY_SPACE = 57
EVENT = struct.Struct("llHHI")
BITS_PER_LONG = struct.calcsize("L") * 8

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
    248: "MIC MUTE",
}


def emit(payload: dict) -> None:
    print(json.dumps(payload, separators=(",", ":")), flush=True)


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


def _ioc_read(number: int, size: int) -> int:
    return (2 << 30) | (size << 16) | (ord("E") << 8) | number


def _event_bits(fd: int, event_type: int, size: int) -> bytes:
    buffer = bytearray(size)
    fcntl.ioctl(fd, _ioc_read(0x20 + event_type, size), buffer, True)
    return bytes(buffer)


def _bit_is_set(bits: bytes, bit: int) -> bool:
    byte = bit // 8
    return byte < len(bits) and bool(bits[byte] & (1 << (bit % 8)))


def _is_keyboard_fd(fd: int) -> bool:
    event_types = _event_bits(fd, 0, 16)
    if not _bit_is_set(event_types, EV_KEY):
        return False
    keys = _event_bits(fd, EV_KEY, 96)
    return all(_bit_is_set(keys, code) for code in (KEY_ENTER, KEY_A, KEY_Z, KEY_SPACE))


def _sysfs_is_keyboard(path: str) -> bool:
    name = os.path.basename(path)
    capability = f"/sys/class/input/{name}/device/capabilities/key"
    try:
        with open(capability, encoding="ascii") as source:
            words = source.read().strip().split()
        bitmap = 0
        for index, word in enumerate(reversed(words)):
            bitmap |= int(word, 16) << (index * BITS_PER_LONG)
        return all(bitmap & (1 << code) for code in (KEY_ENTER, KEY_A, KEY_Z, KEY_SPACE))
    except (OSError, ValueError):
        # If sysfs cannot classify it, try opening it. The ioctl check remains
        # authoritative once access is available.
        return True


class EventReader:
    def __init__(self) -> None:
        self.selector = selectors.DefaultSelector()
        self.devices: dict[str, int] = {}
        self.formatter = KeyChordFormatter()
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
            if path in self.devices or not _sysfs_is_keyboard(path):
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
                if not _is_keyboard_fd(fd):
                    os.close(fd)
                    continue
                self.devices[path] = fd
                self.selector.register(fd, selectors.EVENT_READ, path)
            except OSError:
                os.close(fd)

        if self.devices:
            count = len(self.devices)
            self.status("ready", f"{count} keyboard" + ("s" if count != 1 else ""))
        elif denied:
            self.status("permission-denied", "Permission is required to read keyboard events")
        elif candidates or paths:
            self.status("no-keyboards", "No readable keyboard device was found")
        else:
            self.status("no-keyboards", "No keyboard event devices were found")

    def read_device(self, path: str, fd: int) -> None:
        try:
            while True:
                data = os.read(fd, EVENT.size * 64)
                if not data:
                    self.close_device(path)
                    return
                usable = len(data) - (len(data) % EVENT.size)
                for _seconds, _micros, event_type, code, value in EVENT.iter_unpack(data[:usable]):
                    if event_type != EV_KEY:
                        continue
                    for keys in self.formatter.handle(code, value, path):
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
    for keys in (["SUPER", "L"], ["CTRL", "SHIFT", "P"], ["SPACE"]):
        emit({"type": "key", "keys": keys})


def main() -> int:
    parser = argparse.ArgumentParser(description="Emit global keyboard chords as JSON lines")
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
        print(f"Input reader failed: {type(error).__name__}: {error}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
