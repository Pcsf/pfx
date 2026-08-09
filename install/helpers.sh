#!/bin/bash
#
# Shared helpers for the installer. Sourced by install.sh before any step runs.
#
# The single most important thing in this file is run(): every action that
# touches the system goes through it, which is what makes --dry-run honest.

BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' BLUE=$'\e[34m' RESET=$'\e[0m'

banner() {
  cat <<'ART'

   ███████╗ ███████╗██╗  ██╗
   ██╔══██║ ██╔════╝╚██╗██╔╝
   ██████╔╝ █████╗   ╚███╔╝
   ██╔═══╝  ██╔══╝   ██╔██╗
   ██║      ██║     ██╔╝ ██╗
   ╚═╝      ╚═╝     ╚═╝  ╚═╝
ART
  echo "   Arch + Hyprland desktop toolkit"
  $PFX_DRY_RUN && echo "   ${YELLOW}DRY RUN — nothing will be changed${RESET}"
  echo
}

heading() { printf '\n%s▸ %s%s\n' "$BOLD$BLUE" "$1" "$RESET"; }
info() { printf '  %s\n' "$1"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
abort() {
  printf '\n  %s✗ %s%s\n\n' "$RED" "$1" "$RESET" >&2
  exit 1
}

# run <command...>
#
# The only sanctioned way to mutate the system. In dry-run mode it prints what
# would happen and returns success; otherwise it executes. Arguments are passed
# through as an array, never re-parsed by a shell, so paths with spaces are safe.
run() {
  if $PFX_DRY_RUN; then
    printf '  %swould run:%s %s\n' "$DIM" "$RESET" "$*"
    return 0
  fi
  "$@"
}

# run_sh <string>
#
# For the handful of actions that genuinely need shell features (pipes,
# redirection). Kept separate from run() so the unsafe path is visible at
# every call site.
run_sh() {
  if $PFX_DRY_RUN; then
    printf '  %swould run:%s %s\n' "$DIM" "$RESET" "$1"
    return 0
  fi
  bash -c "$1"
}

have() { command -v "$1" >/dev/null 2>&1; }

# pkg_installed <name> — true if pacman knows the package is installed.
pkg_installed() { pacman -Qq "$1" >/dev/null 2>&1; }

# read_package_list <file> — emit one package name per line, comments stripped.
read_package_list() {
  grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' | awk '{print $1}'
}

# backup_if_exists <path>
#
# Never overwrite a user file without a recoverable copy. Returns 0 whether or
# not a backup was needed, so callers can chain it.
backup_if_exists() {
  local target="$1"
  [[ -e $target ]] || return 0
  local backup="${target}.bak.$(date +%s)"
  run cp -a "$target" "$backup"
  warn "backed up existing $(basename "$target") → $(basename "$backup")"
}

# deploy_config <source-file> <dest-file>
#
# Copy a user-editable default into place. If the destination already exists
# and differs, back it up first. If it exists and matches, do nothing at all —
# this is what makes re-running install.sh idempotent and quiet.
deploy_config() {
  local src="$1" dest="$2"

  # A few configs (btop) cannot expand ~ themselves, so the literal home path
  # is substituted here rather than hardcoded in the repo.
  local rendered
  rendered=$(mktemp)
  sed "s|@HOME@|$HOME|g" "$src" >"$rendered"

  run mkdir -p "$(dirname "$dest")"
  if [[ -f $dest ]]; then
    if cmp -s "$rendered" "$dest" 2>/dev/null; then
      info "$(basename "$dest") already current"
      rm -f "$rendered"
      return 0
    fi
    backup_if_exists "$dest"
  fi
  run cp "$rendered" "$dest"
  rm -f "$rendered"
  ok "deployed $(basename "$dest")"
}

# link_or_copy_tree <source-dir> <dest-dir>
#
# Replace a system-owned tree wholesale. Used only for $PFX_PATH, which is
# explicitly declared replaceable — never for anything under ~/.config.
replace_tree() {
  local src="$1" dest="$2"
  run rm -rf "$dest"
  run mkdir -p "$(dirname "$dest")"
  run cp -r "$src" "$dest"
}
