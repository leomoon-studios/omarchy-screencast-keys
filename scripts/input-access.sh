#!/usr/bin/env bash

set -euo pipefail

readonly RULE_PATH="/etc/udev/rules.d/70-leomoon-studios-screencast-keys.rules"
readonly RULE='SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"'

fail() {
  echo "input-access: $*" >&2
  exit 1
}

[[ ${EUID} -eq 0 ]] || fail "this helper must be run through pkexec or sudo"

case "${1:-}" in
install)
  temporary_file=$(mktemp)
  trap 'rm -f -- "$temporary_file"' EXIT
  printf '%s\n' "$RULE" >"$temporary_file"
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
