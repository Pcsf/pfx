#!/bin/bash
#
# Deploy user-editable configuration.
#
# Everything here lands in ~/.config and is SACRED: if a file already exists
# and differs from ours, it is backed up before being replaced, never silently
# overwritten. The system defaults these configs source from live in
# $PFX_PATH/default and are replaced freely — that split is what lets pfx
# update without a migration engine.

info "Deploying user configs to ~/.config"

while IFS= read -r -d '' src; do
  rel="${src#"$PFX_SOURCE"/config/}"
  deploy_config "$src" "$HOME/.config/$rel"
done < <(find "$PFX_SOURCE/config" -type f -print0 | sort -z)

run mkdir -p "$PFX_CONFIG/themes"
run mkdir -p "$PFX_CONFIG/current"

# XDG user directories (Downloads, Pictures, ...) so screenshots have a home.
have xdg-user-dirs-update && run xdg-user-dirs-update

ok "Configs deployed"
