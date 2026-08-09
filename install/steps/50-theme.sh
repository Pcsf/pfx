#!/bin/bash
#
# Apply a theme so the desktop is styled on first login rather than falling
# back to unstyled defaults. An existing choice is respected.

default_theme="tokyo-night"

if [[ -f $PFX_CONFIG/current/theme.name ]]; then
  current=$(<"$PFX_CONFIG/current/theme.name")
  info "Keeping existing theme: $current"
  # Re-apply so templates regenerate against any new files this update shipped.
  run "$PFX_SOURCE/bin/pfx-theme-set" "$current"
else
  info "Applying default theme: $default_theme"
  run "$PFX_SOURCE/bin/pfx-theme-set" "$default_theme"
fi

ok "Theme applied"
