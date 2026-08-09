#!/bin/bash
#
# Install the pfx tree itself.
#
# $PFX_PATH is system-owned and replaceable: bin/, default/, themes/, and
# applications/ are wiped and rewritten on every install. Nothing the user
# edits lives here, which is exactly why replacing it wholesale is safe.

info "Installing pfx into $PFX_PATH"

run mkdir -p "$PFX_PATH"
for tree in bin default themes applications install; do
  replace_tree "$PFX_SOURCE/$tree" "$PFX_PATH/$tree"
done
run cp "$PFX_SOURCE/VERSION" "$PFX_PATH/VERSION"

run chmod +x "$PFX_PATH/bin/"*

# Put pfx on PATH for login shells. Written to a dedicated file rather than
# appended to .bashrc so re-running the installer can't duplicate the entry.
profile_snippet="$HOME/.config/pfx-path.sh"
# ~/.config is not guaranteed to exist on a freshly created account.
run mkdir -p "$HOME/.config"
if ! $PFX_DRY_RUN; then
  cat >"$profile_snippet" <<'SNIPPET'
# Added by pfx. Safe to delete if you uninstall.
export PFX_PATH="$HOME/.local/share/pfx"
case ":$PATH:" in
*":$PFX_PATH/bin:"*) ;;
*) export PATH="$PFX_PATH/bin:$PATH" ;;
esac
SNIPPET
else
  info "would write $profile_snippet"
fi

source_line="[[ -f ~/.config/pfx-path.sh ]] && source ~/.config/pfx-path.sh"
if [[ -f $HOME/.bashrc ]] && grep -qF 'pfx-path.sh' "$HOME/.bashrc"; then
  info "PATH hook already in .bashrc"
else
  run_sh "printf '\n%s\n' '$source_line' >> '$HOME/.bashrc'"
  ok "PATH hook added to .bashrc"
fi

ok "pfx tree installed"
