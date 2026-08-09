#!/bin/bash
#
# Refuse to run anywhere this script would do damage, and fail early rather
# than halfway through.

[[ -f /etc/arch-release ]] || abort "This is not an Arch Linux system."

((EUID != 0)) || abort "Do not run this as root. Run it as your normal user; it will ask for sudo when needed."

have pacman || abort "pacman not found. This is not a working Arch install."

if ! ping -c1 -W3 archlinux.org >/dev/null 2>&1; then
  warn "Could not reach archlinux.org. Package installation will fail if you have no network."
fi

if [[ $PFX_SOURCE == "$PFX_PATH" ]]; then
  abort "Run install.sh from a clone, not from $PFX_PATH — the install step replaces that directory."
fi

info "Arch Linux detected, running as $USER"

# Take the sudo password once so the rest of the run is unattended. In dry-run
# we never escalate at all.
if ! $PFX_DRY_RUN && ! $PFX_SKIP_PACKAGES; then
  info "Requesting sudo (once) so the rest of the install is unattended..."
  sudo -v || abort "sudo authentication failed."
  # Keep the timestamp alive for the duration of the install.
  while true; do
    sudo -n true
    sleep 50
    kill -0 "$$" 2>/dev/null || exit
  done 2>/dev/null &
  PFX_SUDO_KEEPALIVE=$!
  trap 'kill "$PFX_SUDO_KEEPALIVE" 2>/dev/null || true' EXIT
fi

ok "Preflight passed"
