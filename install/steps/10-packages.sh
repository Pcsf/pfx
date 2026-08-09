#!/bin/bash
#
# Install everything available from the official Arch repositories.

if $PFX_SKIP_PACKAGES; then
  info "Skipping packages (--no-packages)"
  return 0
fi

mapfile -t packages < <(read_package_list "$PFX_SOURCE/install/packages.txt")

info "${#packages[@]} packages from core/extra/multilib"

# --needed makes this idempotent: already-installed packages are left alone.
run sudo pacman -Syu --needed --noconfirm "${packages[@]}"

ok "Repository packages installed"
