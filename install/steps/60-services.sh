#!/bin/bash
#
# Enable the system services a desktop needs. Everything else — notifications,
# the bar, the idle daemon — is started by Hyprland's autostart, not systemd,
# so it lives in the Hyprland config rather than here.

if $PFX_SKIP_PACKAGES; then
  info "Skipping services (--no-packages)"
  return 0
fi

for unit in NetworkManager bluetooth power-profiles-daemon; do
  if systemctl list-unit-files "$unit.service" >/dev/null 2>&1; then
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      info "$unit already enabled"
    else
      run sudo systemctl enable --now "$unit"
      ok "$unit enabled"
    fi
  else
    warn "$unit not installed, skipping"
  fi
done

# Chromium is the web-app runtime; make it the default browser so
# pfx-launch-webapp resolves correctly out of the box.
if have xdg-settings && have chromium; then
  run xdg-settings set default-web-browser chromium.desktop
  ok "Default browser set to Chromium"
fi

ok "Services configured"
