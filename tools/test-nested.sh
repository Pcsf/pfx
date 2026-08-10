#!/bin/bash
#
# Run pfx as a nested Hyprland session inside your current desktop.
#
# This is the middle rung of the testing ladder. A container proves the install
# works; a VM proves the boot path works; this proves the DESKTOP works — real
# compositor, real waybar, real menu, real theme, real keybindings — in about
# thirty seconds and without touching anything you own.
#
# Usage:
#   ./tools/test-nested.sh              # build a scratch session and launch it
#   ./tools/test-nested.sh --keep       # reuse the previous scratch session
#   ./tools/test-nested.sh --clean      # delete scratch sessions and exit
#
# WHAT IT ISOLATES
#   HOME             a fresh directory under /tmp; your real ~/.config is never
#                    read or written
#   pfx tree         installed into that scratch HOME, not ~/.local/share/pfx
#   compositor       its own Hyprland instance with its own signature, so every
#                    hyprctl call inside it targets the nested session
#   PFX_NESTED=1     makes the System menu refuse Lock/Suspend/Reboot/Shutdown,
#                    which would otherwise hit your real machine
#
# WHAT IT CANNOT ISOLATE
#   Your login session and the system bus are shared. Anything that talks to
#   systemd, logind or the machine itself is real. The guards above cover the
#   paths pfx exposes; if you type such a command into a nested terminal
#   yourself, it will do exactly what it says.
#
# HOW TO GET OUT
#   From inside      SUPER+SHIFT+ALT+Q  (exits the nested compositor only)
#   From outside     close the window, or run:  pkill -f 'Hyprland -c /tmp/pfx-nested'
#   If input is stuck Ctrl+Alt+F2 for a TTY, then the pkill above, then
#                    Ctrl+Alt+F1 to come back
#
# Killing the nested session cannot harm the outer one: it is an ordinary
# Wayland client of your current compositor, and everything it wrote lives
# under /tmp.
#
# EXPECTED NOISE
#   A red notification reading "Hyprland was started without start-hyprland.
#   This is strongly discouraged unless you are in a debugging environment."
#   That is exactly what this is. Ignore it.
#
#   xkbcomp warnings about keycodes above 255 and redefined virtual modifiers
#   also scroll past on launch; they come from the nested keymap and are
#   harmless.

set -eEuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PREFIX="/tmp/pfx-nested"

bold=$'\e[1m' dim=$'\e[2m' green=$'\e[32m' yellow=$'\e[33m' reset=$'\e[0m'

mode="fresh"
for arg in "$@"; do
  case "$arg" in
  --keep) mode="keep" ;;
  --clean) mode="clean" ;;
  --help | -h)
    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown option: $arg" >&2
    exit 1
    ;;
  esac
done

if [[ $mode == clean ]]; then
  found=$(find /tmp -maxdepth 1 -name 'pfx-nested*' 2>/dev/null | wc -l)
  rm -rf "${SCRATCH_PREFIX}"*
  echo "Removed $found scratch session(s)."
  exit 0
fi

# --- preconditions ---------------------------------------------------------

[[ -n ${WAYLAND_DISPLAY:-} ]] || {
  echo "No WAYLAND_DISPLAY. Run this from inside a Wayland session." >&2
  exit 1
}
command -v Hyprland >/dev/null 2>&1 || {
  echo "Hyprland is not installed." >&2
  exit 1
}
[[ -n ${XDG_RUNTIME_DIR:-} ]] || {
  echo "XDG_RUNTIME_DIR is not set; Hyprland needs it." >&2
  exit 1
}

# --- scratch session -------------------------------------------------------

if [[ $mode == keep ]]; then
  SCRATCH=$(find /tmp -maxdepth 1 -name 'pfx-nested.*' -type d 2>/dev/null | sort | tail -1)
  [[ -n $SCRATCH ]] || {
    echo "No previous session to keep. Run without --keep first." >&2
    exit 1
  }
  echo "Reusing $SCRATCH"
else
  SCRATCH=$(mktemp -d "${SCRATCH_PREFIX}.XXXXXX")
  echo "${bold}Building a scratch session in $SCRATCH${reset}"
  echo "${dim}Packages are taken from the host, so nothing is downloaded.${reset}"
  echo

  HOME="$SCRATCH" "$ROOT/install.sh" --no-packages 2>&1 |
    sed 's/^/  /' | tail -6

  # Replace the autostart with one that does not touch shared session state.
  # The shipped version runs everything through `uwsm app --` and starts a
  # systemd user unit; both reach the real login session, not this compositor.
  cat >"$SCRATCH/.local/share/pfx/default/hypr/autostart.conf" <<'AUTOSTART'
# Nested-session autostart, written by tools/test-nested.sh.
#
# Deliberately does NOT use `uwsm app --` or `systemctl --user`: those manage
# the real login session, which this nested compositor is a guest inside.
exec-once = waybar
exec-once = mako
exec-once = walker --gapplication-service
exec-once = wl-paste --watch cliphist store
exec-once = pfx-theme-bg-next
AUTOSTART

  # A window, not a screen. 1600x900 fits comfortably on a 1080p display.
  cat >"$SCRATCH/.config/hypr/monitors.conf" <<'MONITORS'
# Nested session: one virtual output sized to sit inside a window.
monitor = , 1600x900@60, auto, 1
MONITORS

  # Make it visually obvious which session you are looking at.
  cat >>"$SCRATCH/.config/hypr/looknfeel.conf" <<'MARK'

# Nested test session marker — a thick warm border you cannot mistake for the
# real desktop.
general {
    border_size = 4
}
MARK
fi

# --- launch ----------------------------------------------------------------

cat <<INFO

${green}${bold}Launching nested pfx session${reset}

  ${bold}Scratch HOME${reset}  $SCRATCH
  ${bold}Your real ~/.config${reset}  untouched — never read, never written

  ${bold}Try${reset}
    SUPER + K                  keybinding list
    SUPER + ALT + SPACE        pfx menu
    SUPER + CTRL + T           cycle theme  ${dim}(the point of the exercise)${reset}
    SUPER + RETURN             terminal

  ${bold}Get out${reset}
    SUPER + SHIFT + ALT + Q    from inside
    ${dim}pkill -f 'Hyprland -c $SCRATCH'${reset}   from another terminal
    ${yellow}Ctrl+Alt+F2 → pkill → Ctrl+Alt+F1${reset}   if input is stuck

  ${yellow}Lock, Suspend, Reboot and Shut down are disabled in this session.${reset}
  ${dim}They act on the machine, not the compositor, so they would hit your real desktop.${reset}

INFO

# HYPRLAND_INSTANCE_SIGNATURE must be cleared so the nested compositor mints
# its own — inheriting the outer one would point every hyprctl call in the
# nested session at the real desktop.
env -u HYPRLAND_INSTANCE_SIGNATURE \
  HOME="$SCRATCH" \
  PFX_NESTED=1 \
  XDG_CONFIG_HOME="$SCRATCH/.config" \
  XDG_DATA_HOME="$SCRATCH/.local/share" \
  XDG_CACHE_HOME="$SCRATCH/.cache" \
  PATH="$SCRATCH/.local/share/pfx/bin:$PATH" \
  Hyprland -c "$SCRATCH/.config/hypr/hyprland.conf"

echo
echo "Nested session ended. Scratch kept at $SCRATCH"
echo "${dim}Reuse it with --keep, or remove every scratch session with --clean.${reset}"
