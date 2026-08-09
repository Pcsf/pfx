#!/bin/bash
#
# Bootstrap an AUR helper, then install the handful of packages Arch does not
# ship itself. Kept deliberately small — every entry here is a build that can
# break, so anything available in the official repos belongs in packages.txt.

if $PFX_SKIP_PACKAGES; then
  info "Skipping AUR (--no-packages)"
  return 0
fi

if ! have yay; then
  info "Bootstrapping yay from the AUR"
  build_dir=$(mktemp -d)
  run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$build_dir/yay-bin"
  # makepkg must run in the build directory and cannot be given a path, so this
  # is one of the few places a subshell is genuinely required.
  run_sh "cd '$build_dir/yay-bin' && makepkg -si --noconfirm"
  run rm -rf "$build_dir"
  ok "yay installed"
else
  info "yay already present"
fi

mapfile -t aur_packages < <(read_package_list "$PFX_SOURCE/install/packages-aur.txt")

info "${#aur_packages[@]} packages from the AUR"
run yay -S --needed --noconfirm "${aur_packages[@]}"

ok "AUR packages installed"
