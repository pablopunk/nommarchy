#!/usr/bin/env bash
# nommarchy installer — installs the `nommarchy` CLI (user-local) and the udev
# rule that lets your user talk to the Razer Nommo V2 X without root.
#
# Run it *without* sudo:
#
#   ./install.sh
#
# Only the udev rule needs root, so the script elevates just that step (and
# the udev reload/trigger) with sudo/pkexec. The privileged write uses a
# fixed, reviewed rule string (see install_udev below) — nothing is copied out
# of the user-writable plugin checkout into a system location.
#
# The shell plugin itself is installed separately with:
#   omarchy plugin add https://github.com/pablopunk/nommarchy.git
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINDIR="${BINDIR:-$HOME/.local/bin}"
RULE=/etc/udev/rules.d/99-nommo.rules

# The CLI must be installed into the invoking user's home, not root's, so
# refuse the common "sudo ./install.sh" mistake up front.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  echo "error: run './install.sh' as your normal user, not with sudo." >&2
  echo "       The script elevates only the udev-rule step itself." >&2
  exit 1
fi

# Run a command as root. Already root -> run directly; otherwise prefer sudo
# and fall back to pkexec.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1; then
    pkexec "$@"
  else
    echo "error: sudo or pkexec is required to install the udev rule" >&2
    exit 1
  fi
}

install_backend() {
  # User-local: no privilege boundary is crossed (checkout -> ~/.local/bin).
  install -Dm755 "$here/nommarchy" "$BINDIR/nommarchy"
}

install_udev() {
  # Fixed rule content. Kept as a literal heredoc so the privileged step can
  # only ever write these exact bytes — the same content as 99-nommo.rules,
  # never copied from the mutable checkout.
  as_root tee "$RULE" >/dev/null <<'EOF'
# Razer Nommo V2 X (1532:055E) — allow the local user to control the
# speakers' vendor HID interface (feature report 0x07) without root.
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="055e", MODE="0660", GROUP="input", TAG+="uaccess"
EOF
  as_root udevadm control --reload-rules
  as_root udevadm trigger --subsystem-match=hidraw
}

uninstall() {
  rm -f "$BINDIR/nommarchy"
  as_root rm -f "$RULE"
  as_root udevadm control --reload-rules
  echo "nommarchy backend and udev rule removed"
}

case "${1:-}" in
  --uninstall)
    uninstall
    ;;
  *)
    install_backend
    install_udev
    echo "nommarchy installed to $BINDIR/nommarchy"
    echo "udev rule installed — your user can now access the Nommo V2 X"
    ;;
esac
