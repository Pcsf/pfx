#!/bin/bash
#
# pfx — post-install setup for a vanilla Arch Linux system.
#
# Usage:
#   ./install.sh              # install for real
#   ./install.sh --dry-run    # print every action, change nothing
#   ./install.sh --no-packages   # skip package installation, deploy configs only
#
# Run this as your normal user (NOT root) on a freshly installed Arch system
# with a working network connection. You will be asked for your sudo password
# once, early, and the sudo timestamp is refreshed for the rest of the run.

set -eEo pipefail

PFX_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PFX_SOURCE
export PFX_PATH="$HOME/.local/share/pfx"
export PFX_CONFIG="$HOME/.config/pfx"
export PFX_DRY_RUN=false
export PFX_SKIP_PACKAGES=false

for arg in "$@"; do
  case "$arg" in
  --dry-run | -n) PFX_DRY_RUN=true ;;
  --no-packages) PFX_SKIP_PACKAGES=true ;;
  --help | -h)
    sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown option: $arg" >&2
    exit 1
    ;;
  esac
done

source "$PFX_SOURCE/install/helpers.sh"

trap 'abort "Installation failed on line $LINENO. Nothing further was changed."' ERR

banner

for step in "$PFX_SOURCE"/install/steps/*.sh; do
  heading "$(basename "$step" .sh | sed 's/^[0-9]*-//' | tr '-' ' ')"
  source "$step"
done

echo
if $PFX_DRY_RUN; then
  ok "Dry run complete. Nothing was changed."
  echo "   Re-run without --dry-run to apply."
else
  ok "pfx is installed."
  echo
  echo "   Next steps:"
  echo "     1. Log out of this session (or reboot)."
  echo "     2. From a TTY, start Hyprland with:  uwsm start hyprland-uwsm.desktop"
  echo "     3. Press SUPER + K to see every keybinding."
  echo "     4. Press SUPER + ALT + SPACE for the pfx menu."
fi
