#!/usr/bin/env bash

set -euo pipefail

readonly RULE_PATH="/etc/udev/rules.d/70-leomoon-studios-screencast-keys.rules"
readonly INPUT_RULE_PREFIX='SUBSYSTEM=="input", KERNEL=="event*"'
readonly UACCESS_RULE='TAG+="uaccess"'

fail() {
  echo "input-access: $*" >&2
  exit 1
}

[[ ${EUID} -eq 0 ]] || fail "this helper must be run through pkexec or sudo"

case "${1:-}" in
install)
  temporary_file=$(mktemp)
  trap 'rm -f -- "$temporary_file"' EXIT
  printf '%s, ENV{ID_INPUT_KEYBOARD}=="1", %s\n' "$INPUT_RULE_PREFIX" "$UACCESS_RULE" >"$temporary_file"
  printf '%s, ENV{ID_INPUT_MOUSE}=="1", %s\n' "$INPUT_RULE_PREFIX" "$UACCESS_RULE" >>"$temporary_file"
  printf '%s, ENV{ID_INPUT_TOUCHPAD}=="1", %s\n' "$INPUT_RULE_PREFIX" "$UACCESS_RULE" >>"$temporary_file"
  printf '%s, ENV{ID_INPUT_POINTINGSTICK}=="1", %s\n' "$INPUT_RULE_PREFIX" "$UACCESS_RULE" >>"$temporary_file"
  install -o root -g root -m 0644 "$temporary_file" "$RULE_PATH"
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=input --action=change
  ;;
remove)
  rm -f -- "$RULE_PATH"
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=input --action=change
  ;;
*)
  fail "usage: $0 install|remove"
  ;;
esac
