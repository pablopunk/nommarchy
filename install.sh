#!/usr/bin/env bash
# nommarchy installer — installs the `nommarchy` CLI and the udev rule that
# lets your user talk to the Razer Nommo V2 X without root.
#
# The shell plugin itself is installed separately with:
#   omarchy plugin add https://github.com/pablopunk/nommarchy.git
#
# This script is the second half: it puts the backend binary on PATH and
# grants unprivileged access to the speakers' HID interface.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "error: run with sudo (installs to $PREFIX/bin and /etc/udev/rules.d)" >&2
    exit 1
  fi
}

install_backend() {
  install -Dm755 "$here/nommarchy" "$PREFIX/bin/nommarchy"
}

install_udev() {
  install -Dm644 "$here/99-nommo.rules" /etc/udev/rules.d/99-nommo.rules
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=hidraw
}

uninstall() {
  require_root
  rm -f "$PREFIX/bin/nommarchy" /etc/udev/rules.d/99-nommo.rules
  udevadm control --reload-rules
  echo "nommarchy backend and udev rule removed"
}

case "${1:-}" in
  --uninstall)
    uninstall
    ;;
  *)
    require_root
    install_backend
    install_udev
    echo "nommarchy installed to $PREFIX/bin/nommarchy"
    echo "udev rule installed — your user can now access the Nommo V2 X"
    ;;
esac
