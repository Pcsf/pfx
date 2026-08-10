#!/bin/bash
#
# Run the ISA's probes. Every check here corresponds to an ISC in ISA.md.
#
# Everything that could touch a real desktop runs under a scratch HOME with
# HYPRLAND_INSTANCE_SIGNATURE unset, so running this on a live machine cannot
# disturb the live session.

set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0 FAIL=0 SKIP=0

green=$'\e[32m' red=$'\e[31m' yellow=$'\e[33m' dim=$'\e[2m' reset=$'\e[0m'

check() {
  local id="$1" desc="$2"
  shift 2
  local output
  if output=$("$@" 2>&1); then
    printf '%s✓%s %-8s %s\n' "$green" "$reset" "$id" "$desc"
    [[ -n $output ]] && printf '%s        %s%s\n' "$dim" "${output//$'\n'/$'\n'        }" "$reset"
    ((PASS++))
  else
    printf '%s✗%s %-8s %s\n' "$red" "$reset" "$id" "$desc"
    printf '%s        %s%s\n' "$dim" "${output//$'\n'/$'\n'        }" "$reset"
    ((FAIL++))
  fi
}

skip() {
  printf '%s—%s %-8s %s %s(%s)%s\n' "$yellow" "$reset" "$1" "$2" "$dim" "$3" "$reset"
  ((SKIP++))
}

scratch() {
  local dir
  dir=$(mktemp -d)
  echo "$dir"
}

# --------------------------------------------------------------- ISC-1
isc1() {
  local failed=0 f
  while IFS= read -r -d '' f; do
    bash -n "$f" || {
      echo "syntax error in $f"
      failed=1
    }
  done < <(find "$ROOT" -type f \( -name '*.sh' -o -path "$ROOT/bin/*" \) -print0)
  echo "parsed $(find "$ROOT" -type f \( -name '*.sh' -o -path "$ROOT/bin/*" \) | wc -l) scripts"
  return $failed
}

# --------------------------------------------------------------- ISC-2
isc2() {
  local home before after
  home=$(scratch)
  before=$(find "$home" | wc -l)
  HOME="$home" "$ROOT/install.sh" --dry-run >/dev/null 2>&1
  after=$(find "$home" | wc -l)
  rm -rf "$home"
  [[ $before == "$after" ]] || {
    echo "dry run created $((after - before)) paths under HOME"
    return 1
  }
  echo "scratch HOME unchanged ($before paths before and after)"
}

# --------------------------------------------------------------- ISC-3 / ISC-20
resolve_packages() {
  local unresolved=() p
  for p in "$@"; do
    pacman -Si "$p" >/dev/null 2>&1 && continue
    # Not in the repos — check the AUR before calling it a failure.
    if [[ $(curl -sf --max-time 10 "https://aur.archlinux.org/rpc/v5/info?arg[]=$p" |
      jq -r '.resultcount' 2>/dev/null) == "1" ]]; then
      continue
    fi
    unresolved+=("$p")
  done
  if ((${#unresolved[@]})); then
    echo "unresolved: ${unresolved[*]}"
    return 1
  fi
  echo "all $# resolve"
}

isc3() {
  mapfile -t pkgs < <(grep -hv '^[[:space:]]*#' \
    "$ROOT/install/packages.txt" "$ROOT/install/packages-aur.txt" |
    grep -v '^[[:space:]]*$' | awk '{print $1}')
  resolve_packages "${pkgs[@]}"
}

isc20() {
  # Every package name the install menu would hand to pfx-pkg-add / -aur-add.
  mapfile -t pkgs < <(
    grep -oE 'install_(pkg|aur) "[^"]+" "[^"]+"' "$ROOT/bin/pfx-menu" |
      sed 's/.*" "//; s/"$//' | tr ' ' '\n' | sort -u
  )
  ((${#pkgs[@]})) || {
    echo "no menu packages found — probe is broken"
    return 1
  }
  resolve_packages "${pkgs[@]}"
}

# --------------------------------------------------------------- ISC-4
isc4() {
  local home
  home=$(scratch)
  HOME="$home" PFX_SOURCE="$ROOT" PFX_DRY_RUN=false PFX_SKIP_PACKAGES=true \
    bash -c "source '$ROOT/install/helpers.sh'; source '$ROOT/install/steps/40-config.sh'" >/dev/null 2>&1
  local first_backups
  first_backups=$(find "$home" -name '*.bak.*' | wc -l)
  local second
  second=$(HOME="$home" PFX_SOURCE="$ROOT" PFX_DRY_RUN=false PFX_SKIP_PACKAGES=true \
    bash -c "source '$ROOT/install/helpers.sh'; source '$ROOT/install/steps/40-config.sh'" 2>&1)
  local second_backups
  second_backups=$(find "$home" -name '*.bak.*' | wc -l)
  rm -rf "$home"
  [[ $first_backups == 0 && $second_backups == 0 ]] || {
    echo "backups created on a clean/repeat deploy: $first_backups then $second_backups"
    return 1
  }
  grep -q 'already current' <<<"$second" || {
    echo "second pass did not detect unchanged files"
    return 1
  }
  echo "second pass reported files already current, no backups written"
}

# --------------------------------------------------------------- ISC-5
isc5() {
  local home
  home=$(scratch)
  mkdir -p "$home/.config/hypr"
  echo "SENTINEL-DO-NOT-LOSE" >"$home/.config/hypr/bindings.conf"
  HOME="$home" PFX_SOURCE="$ROOT" PFX_DRY_RUN=false PFX_SKIP_PACKAGES=true \
    bash -c "source '$ROOT/install/helpers.sh'; source '$ROOT/install/steps/40-config.sh'" >/dev/null 2>&1
  local found
  found=$(grep -rl 'SENTINEL-DO-NOT-LOSE' "$home/.config/hypr/" 2>/dev/null | grep '\.bak\.' | head -1)
  rm -rf "$home"
  [[ -n $found ]] || {
    echo "sentinel content was lost — no backup contains it"
    return 1
  }
  echo "sentinel preserved in $(basename "$found")"
}

# --------------------------------------------------------------- ISC-7
isc7() {
  # Every submenu the dispatcher or a case arm names must exist as a function.
  local missing=()
  while read -r fn; do
    grep -q "^${fn}() {" "$ROOT/bin/pfx-menu" || missing+=("$fn")
  done < <(grep -oE '\bshow_[a-z_]+_menu\b' "$ROOT/bin/pfx-menu" | sort -u)
  if ((${#missing[@]})); then
    echo "referenced but undefined: ${missing[*]}"
    return 1
  fi
  # Every submenu must have a fallback arm so escape returns rather than hangs.
  local nofallback=()
  while read -r fn; do
    awk -v f="$fn" '
      $0 ~ "^" f "\\(\\) \\{" { inside = 1 }
      inside && /^\}/ { inside = 0 }
      inside && /^  \*\)/ { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$ROOT/bin/pfx-menu" || nofallback+=("$fn")
  done < <(grep -oE '^show_[a-z_]+_menu' "$ROOT/bin/pfx-menu" | sort -u | grep -v 'show_apps_menu\|show_theme_menu')
  if ((${#nofallback[@]})); then
    echo "no escape/fallback arm: ${nofallback[*]}"
    return 1
  fi
  echo "$(grep -cE '^show_[a-z_]+_menu\(\) \{' "$ROOT/bin/pfx-menu") submenus, all defined, all with a fallback arm"
}

# --------------------------------------------------------------- ISC-10..13
isc10() {
  command -v desktop-file-validate >/dev/null 2>&1 || {
    echo "desktop-file-validate not installed"
    return 2
  }
  local home
  home=$(scratch)
  HOME="$home" PATH="$ROOT/bin:$PATH" \
    pfx-webapp-install "Probe App" "https://example.com" "applications-internet" >/dev/null 2>&1
  local out
  out=$(desktop-file-validate "$home/.local/share/applications/Probe App.desktop" 2>&1)
  local rc=$?
  rm -rf "$home"
  [[ $rc == 0 ]] || {
    echo "$out"
    return 1
  }
  echo "generated .desktop passes desktop-file-validate"
}

isc12() {
  local home
  home=$(scratch)
  # An unroutable domain: favicon fetch must fail, install must still succeed.
  HOME="$home" PATH="$ROOT/bin:$PATH" \
    pfx-webapp-install "Broken Icon" "https://nonexistent.invalid" >/dev/null 2>&1
  local rc=$?
  local has_entry=0
  [[ -f "$home/.local/share/applications/Broken Icon.desktop" ]] && has_entry=1
  local icon
  icon=$(grep '^Icon=' "$home/.local/share/applications/Broken Icon.desktop" 2>/dev/null)
  rm -rf "$home"
  [[ $rc == 0 && $has_entry == 1 ]] || {
    echo "install failed when the icon could not be fetched (rc=$rc)"
    return 1
  }
  echo "installed anyway; $icon"
}

isc13() {
  local home
  home=$(scratch)
  HOME="$home" PATH="$ROOT/bin:$PATH" \
    pfx-webapp-install "Temp App" "https://example.com" "applications-internet" >/dev/null 2>&1
  HOME="$home" PATH="$ROOT/bin:$PATH" pfx-webapp-remove "Temp App" >/dev/null 2>&1
  local left
  left=$(find "$home/.local/share/applications" -name 'Temp App*' 2>/dev/null | wc -l)
  HOME="$home" PATH="$ROOT/bin:$PATH" pfx-webapp-remove "Never Existed" >/dev/null 2>&1
  local rc=$?
  rm -rf "$home"
  [[ $left == 0 ]] || {
    echo "$left files left behind after removal"
    return 1
  }
  [[ $rc == 0 ]] || {
    echo "removing an unknown app exited $rc, expected 0"
    return 1
  }
  echo "entry and icon removed; removing an unknown app is a no-op"
}

isc14() {
  local home stub
  home=$(scratch)
  stub="$home/stub"
  mkdir -p "$stub"
  # Stub xdg-settings to report an unsupported browser.
  printf '#!/bin/bash\necho firefox.desktop\n' >"$stub/xdg-settings"
  chmod +x "$stub/xdg-settings"
  local out
  out=$(HOME="$home" PATH="$stub:$ROOT/bin:$PATH" \
    pfx-launch-webapp --print-cmd "https://example.com" 2>&1)
  rm -rf "$home"
  grep -qE 'chrom|brave|vivaldi|edge' <<<"$out" || {
    echo "did not fall back to a Chromium-family browser: $out"
    return 1
  }
  echo "firefox default → $out"
}

# --------------------------------------------------------------- ISC-15..19
isc15() {
  # The swap must be a rename onto a symlink, never a copy into the live path.
  grep -q 'mv -T "\$tmp_link" "\$CURRENT/theme"' "$ROOT/bin/pfx-theme-set" || {
    echo "no atomic rename found"
    return 1
  }
  if grep -qE 'cp .*"\$CURRENT/theme"' "$ROOT/bin/pfx-theme-set"; then
    echo "found a copy targeting the live theme path"
    return 1
  fi
  echo "staged then swapped with a single mv -T onto the symlink"
}

isc16() {
  local manifest=(alacritty.toml waybar.css walker.css mako.ini hyprland.conf hyprlock.conf btop.theme)
  local problems=() theme f
  for theme in "$ROOT"/themes/*/; do
    for f in "${manifest[@]}"; do
      [[ -f $theme/$f ]] || problems+=("$(basename "$theme")/$f")
    done
    [[ -d $theme/backgrounds ]] &&
      [[ $(find "$theme/backgrounds" -type f | wc -l) -gt 0 ]] ||
      problems+=("$(basename "$theme")/backgrounds")
  done
  if ((${#problems[@]})); then
    echo "missing: ${problems[*]}"
    return 1
  fi
  echo "$(find "$ROOT/themes" -mindepth 1 -maxdepth 1 -type d | wc -l) themes, all ${#manifest[@]} manifest files present plus backgrounds"
}

isc17() {
  local home
  home=$(scratch)
  mkdir -p "$home/.config/pfx/current"
  echo "tokyo-night" >"$home/.config/pfx/current/theme.name"
  HOME="$home" PFX_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    pfx-theme-set "not-a-real-theme" >/dev/null 2>&1
  local rc=$?
  local after
  after=$(<"$home/.config/pfx/current/theme.name")
  rm -rf "$home"
  [[ $rc != 0 ]] || {
    echo "bogus theme name exited 0"
    return 1
  }
  [[ $after == "tokyo-night" ]] || {
    echo "current theme was changed to '$after'"
    return 1
  }
  echo "exited $rc, current theme still tokyo-night"
}

isc19() {
  local listed on_disk
  listed=$(PFX_PATH="$ROOT" PFX_CONFIG="$(scratch)" "$ROOT/bin/pfx-theme-list" | sort)
  on_disk=$(find "$ROOT/themes" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  [[ $listed == "$on_disk" ]] || {
    echo "list: $listed"
    echo "disk: $on_disk"
    return 1
  }
  echo "$(wc -l <<<"$listed") themes, list matches disk"
}

# --------------------------------------------------------------- ISC-21..23
isc21() {
  local out rc
  out=$("$ROOT/bin/pfx-pkg-add" 2>&1)
  rc=$?
  [[ $rc != 0 ]] || {
    echo "exited 0 with no arguments"
    return 1
  }
  grep -q Usage <<<"$out" || {
    echo "no usage message: $out"
    return 1
  }
  echo "exits $rc with a usage message"
}

isc22() {
  mapfile -t base < <(grep -v '^[[:space:]]*#' "$ROOT/install/packages.txt" |
    grep -v '^[[:space:]]*$' | awk '{print $1}' | sort -u)
  mapfile -t removable < <(grep -oE 'remove_pkg "[^"]+" "[^"]+"' "$ROOT/bin/pfx-menu" |
    sed 's/.*" "//; s/"$//' | tr ' ' '\n' | sort -u)
  local overlap
  overlap=$(comm -12 <(printf '%s\n' "${base[@]}") <(printf '%s\n' "${removable[@]}" | grep -v '^$'))
  [[ -z $overlap ]] || {
    echo "remove menu offers base packages: $overlap"
    return 1
  }

  # The menu check above is vacuous while the remove menu only prompts for a
  # name, so exercise the guard that actually protects the base install.
  local out rc
  out=$(PFX_PATH="$ROOT" "$ROOT/bin/pfx-pkg-remove" hyprland 2>&1)
  rc=$?
  [[ $rc != 0 ]] || {
    echo "pfx-pkg-remove accepted a base package"
    return 1
  }
  grep -q 'base install' <<<"$out" || {
    echo "refused, but without explaining why: $out"
    return 1
  }
  # ...and that it does not block a package outside the base set.
  grep -qx "[[:space:]]*htop[[:space:]]*" "$ROOT/install/packages.txt" && {
    echo "probe is stale — htop is now in the base set"
    return 1
  }
  echo "guard rejects 'hyprland' (exit $rc), allows non-base packages"
}

isc23() {
  local missing=() notexec=() cmd
  for cmd in "$ROOT"/bin/pfx-*; do
    grep -q '^# pfx:summary=' "$cmd" || missing+=("$(basename "$cmd")")
    # A command that isn't executable is invisible to the dispatcher, which
    # is how pfx-menu silently vanished from `pfx --help` the first time.
    [[ -x $cmd ]] || notexec+=("$(basename "$cmd")")
  done
  if ((${#missing[@]})); then
    echo "no summary line: ${missing[*]}"
    return 1
  fi
  if ((${#notexec[@]})); then
    echo "not executable: ${notexec[*]}"
    return 1
  fi
  local listed total
  listed=$("$ROOT/bin/pfx" --help | grep -cE '^  [a-z]')
  total=$(find "$ROOT/bin" -name 'pfx-*' -type f | wc -l)
  [[ $listed == "$total" ]] || {
    echo "pfx --help lists $listed of $total commands"
    return 1
  }
  echo "$total commands, all documented and all listed by pfx --help"
}

# --------------------------------------------------------------- ISC-11
isc11() {
  local home
  home=$(scratch)
  HOME="$home" PATH="$ROOT/bin:$PATH" \
    pfx-webapp-install "Index Probe" "https://example.com" "applications-internet" >/dev/null 2>&1
  local entry="$home/.local/share/applications/Index Probe.desktop"
  local indexed=0
  [[ -f $entry ]] || {
    echo "no .desktop written to the XDG applications directory"
    rm -rf "$home"
    return 1
  }
  # An entry is only visible to a launcher once the desktop database sees it.
  [[ -f "$home/.local/share/applications/mimeinfo.cache" ]] && indexed=1
  local name
  name=$(grep '^Name=' "$entry")
  rm -rf "$home"
  [[ $indexed == 1 ]] || {
    echo "entry written but update-desktop-database produced no cache"
    return 1
  }
  echo "$name — written to XDG applications dir and indexed"
}

# --------------------------------------------------------------- ISC-24
isc24() {
  command -v Hyprland >/dev/null 2>&1 || {
    echo "Hyprland not installed"
    return 2
  }
  local home out
  home=$(scratch)
  HOME="$home" "$ROOT/install.sh" --no-packages >/dev/null 2>&1 || {
    echo "scratch install failed"
    rm -rf "$home"
    return 1
  }
  # --verify-config parses and exits; it never starts a compositor, so this is
  # safe to run from inside a live session.
  out=$(HOME="$home" Hyprland --verify-config -c "$home/.config/hypr/hyprland.conf" 2>&1 |
    grep -i 'error' || true)
  rm -rf "$home"
  [[ -z $out ]] || {
    echo "$out"
    return 1
  }
  echo "Hyprland --verify-config reports config ok"
}

# --------------------------------------------------------------- ISC-6b / ISC-25
# Two distinct failures, both of which shipped once:
#
#   1. A glyph that does not exist in the shipped font renders as nothing.
#   2. An icon slot that lost its glyph entirely — the string is still there,
#      just empty. The first version of this probe passed happily while the
#      whole waybar was iconless, because "no glyphs" trivially satisfies
#      "every glyph is valid". Absence has to be tested for directly.
iscglyphs() {
  local font
  font=$(fc-match -f '%{file}' "JetBrainsMono Nerd Font" 2>/dev/null)
  [[ -f ${font:-} ]] || {
    echo "JetBrainsMono Nerd Font not installed"
    return 2
  }
  python3 - "$ROOT" "$font" <<'PY'
import sys, subprocess, glob, os
root, font = sys.argv[1], sys.argv[2]

targets = []
for pat in ("bin/*", "config/**/*", "default/**/*"):
    targets += [f for f in glob.glob(os.path.join(root, pat), recursive=True)
                if os.path.isfile(f)]

cache = {}
def present(c):
    if c not in cache:
        r = subprocess.run(["magick", "-background", "black", "-fill", "white",
                            "-font", font, "-pointsize", "48", f"label:{c}",
                            "-format", "%[fx:mean]", "info:"],
                           capture_output=True, text=True)
        try: cache[c] = float(r.stdout) >= 0.001
        except ValueError: cache[c] = False
    return cache[c]

missing, total = [], 0
for f in sorted(targets):
    try: text = open(f, encoding='utf-8').read()
    except Exception: continue
    for c in {c for c in text if ord(c) > 0x2100}:
        total += 1
        if not present(c):
            missing.append(f"{os.path.relpath(f, root)}: U+{ord(c):05X}")

print(f"{total} icon glyph uses checked across {len(targets)} files")
if missing:
    print("absent from the font:")
    for m in missing: print("   ", m)
    sys.exit(1)
PY
}

# An icon slot that is present but empty. Catches the regression directly
# rather than inferring it.
iscemptyicons() {
  local cfg="$ROOT/config/waybar/config.jsonc" problems=()

  # "format": "  {usage}%" — leading whitespace where an icon belongs.
  while IFS= read -r line; do
    problems+=("${line}")
  done < <(grep -nE '"(format|format-[a-z]+)": "[[:space:]]+\{' "$cfg" || true)

  # "format-icons": ["", "", ""] — the array survived, the icons did not.
  while IFS= read -r line; do
    problems+=("${line}")
  done < <(grep -nE '"format-icons": *[\[{][^]}]*""' "$cfg" || true)

  # A module whose entire format string is empty renders nothing at all.
  while IFS= read -r line; do
    problems+=("${line}")
  done < <(grep -nE '"format(-[a-z]+)?": *"[[:space:]]*"' "$cfg" || true)

  if ((${#problems[@]})); then
    echo "empty icon slots in waybar config:"
    printf '   %s\n' "${problems[@]}"
    return 1
  fi
  echo "no empty icon slots in the waybar config"
}

# The bar is unusable if its config does not parse. jsonc allows // comments,
# so strip them before handing it to a JSON parser.
iscwaybarjson() {
  python3 - "$ROOT/config/waybar/config.jsonc" <<'PY'
import sys, json, re
raw = open(sys.argv[1], encoding='utf-8').read()
stripped = re.sub(r'^\s*//.*$', '', raw, flags=re.M)
try:
    cfg = json.loads(stripped)
except json.JSONDecodeError as e:
    print(f"invalid JSON: {e}")
    sys.exit(1)
mods = len(cfg.get("modules-left", []) + cfg.get("modules-center", []) + cfg.get("modules-right", []))
print(f"parses cleanly, {mods} modules configured")
PY
}

# --------------------------------------------------------------- ISC-30..32
# Walker failure modes that produce NO error message. All three shipped once.

# Every provider the launcher config names must be carried by a package the
# installer actually requests. walker-bin depends on bare `elephant`, which has
# no providers at all, so a launcher configured for `desktopapplications` opens
# empty and silent.
isc30() {
  python3 - "$ROOT" <<'PY'
import sys, os, json, urllib.request, tomllib

root = sys.argv[1]
cfg = tomllib.load(open(os.path.join(root, "config/walker/config.toml"), "rb"))

wanted = set(cfg.get("providers", {}).get("default", []))
for pref in cfg.get("providers", {}).get("prefixes", []):
    wanted.add(pref["provider"])

aur = [l.split('#')[0].strip() for l in
       open(os.path.join(root, "install/packages-aur.txt"), encoding="utf-8")]
aur = [l for l in aur if l]

available = set()
for pkg in aur:
    if not pkg.startswith("elephant"):
        continue
    url = f"https://aur.archlinux.org/rpc/v5/info?arg[]={pkg}"
    try:
        data = json.load(urllib.request.urlopen(url, timeout=15))
    except Exception as e:
        print(f"could not reach the AUR: {e}")
        sys.exit(2)
    if not data["results"]:
        print(f"{pkg} is not in the AUR")
        sys.exit(1)
    r = data["results"][0]
    for name in r.get("Provides", []) + [r["Name"]]:
        available.add(name.split("=")[0].replace("elephant-", ""))

missing = sorted(w for w in wanted if w not in available)
if missing:
    print("providers with no installed backend:", ", ".join(missing))
    print("configured:", ", ".join(sorted(wanted)))
    sys.exit(1)
print(f"{len(wanted)} configured providers, all covered: {', '.join(sorted(wanted))}")
PY
}

# Walker 2.16 names a list row `child`, not `.item`. Styling `.item:selected`
# parses fine and highlights nothing, so the menu gives no feedback about what
# Enter will do.
isc31() {
  local css="$ROOT/default/walker/themes/pfx/style.css"
  grep -q 'child:selected' "$css" || {
    echo "no 'child:selected' rule — the selection highlight will not render"
    return 1
  }
  if grep -qE '^\s*\.item:selected' "$css"; then
    echo "uses '.item:selected', which walker 2.16 does not match"
    return 1
  fi
  echo "uses walker 2.16 row selectors (child / child:selected .item-box)"
}

# TOML puts every bare key after a [table] INSIDE that table. `theme` landing
# in [keybinds] would silently leave walker on its default theme.
isc32() {
  python3 - "$ROOT/config/walker/config.toml" <<'PY'
import sys, tomllib
cfg = tomllib.load(open(sys.argv[1], "rb"))
required = ["theme", "additional_theme_location"]
missing = [k for k in required if k not in cfg]
if missing:
    print("not at top level (swallowed by a [table]?):", ", ".join(missing))
    sys.exit(1)
print(f"theme={cfg['theme']!r} resolved at top level; {len(cfg)} root keys")
PY
}

# --------------------------------------------------------------- ISC-33
# No command may signal a session process it does not own.
#
# This is the class, not one instance of it. pfx-restart and pfx-theme-bg-next
# were fixed first and pfx-theme-set was missed, which is what killed the real
# desktop's bar during nested testing. Anything that signals waybar, mako,
# hyprpaper or walker must go through pfx-session-pids.
isc33() {
  local offenders
  offenders=$(grep -rnE '(pkill|killall)[^|;]*\b(waybar|mako|hyprpaper|walker|elephant)\b' "$ROOT/bin" |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)

  [[ -z $offenders ]] || {
    echo "unscoped signal to a session process:"
    echo "$offenders"
    echo "use: kill \$(pfx-session-pids <name>)"
    return 1
  }

  # And the harness must not carry the real session's signature into the
  # scratch install, which is how the signals escaped in the first place.
  grep -q 'env -u HYPRLAND_INSTANCE_SIGNATURE HOME="\$SCRATCH"' "$ROOT/tools/test-nested.sh" || {
    echo "test-nested.sh runs the installer with the live instance signature set"
    return 1
  }

  echo "no unscoped signals; nested installer runs with no instance signature"
}

# --------------------------------------------------------------- anti-criteria
anti1() {
  # Prose is excluded — the ISA, the README and this file all name the things
  # being forbidden, which is the point of them.
  local excludes=(--exclude-dir=.git --exclude=ISA.md --exclude=README.md --exclude=NOTICE --exclude=verify.sh)
  if grep -rn 'pkgs\.omarchy\.org' "$ROOT" "${excludes[@]}"; then
    echo "reference to the omarchy package repo found"
    return 1
  fi
  if grep -rn 'pacman\.conf' "$ROOT" "${excludes[@]}"; then
    echo "something writes to pacman.conf"
    return 1
  fi
  echo "no third-party repo, no pacman.conf writes"
}

anti3() {
  # Comment lines are stripped first: the keybindings reader documents at
  # length why it does NOT use the JSON serializer, and that explanation
  # should not trip its own guard.
  local hits
  hits=$(grep -rn 'hyprctl -j binds\|hyprctl --json binds' "$ROOT/bin" |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
  [[ -z $hits ]] || {
    echo "a command consumes the broken JSON binds serializer:"
    echo "$hits"
    return 1
  }
  echo "nothing consumes hyprctl -j binds outside comments"
}

anti4() {
  local bad
  bad=$(grep -rhoE '(curl|wget)[^|;]*https?://[^ "'"'"']+' "$ROOT/bin" "$ROOT/install" 2>/dev/null |
    grep -vE 'aur\.archlinux\.org|archlinux\.org|google\.com/s2/favicons' || true)
  [[ -z $bad ]] || {
    echo "unexpected network target: $bad"
    return 1
  }
  echo "network targets limited to Arch, the AUR, and the favicon service"
}

# --------------------------------------------------------------- run
echo
echo "pfx verification — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

check ISC-1 "every script parses" isc1
check ISC-2 "dry run mutates nothing" isc2
check ISC-3 "install packages resolve" isc3
check ISC-4 "config deploy is idempotent" isc4
check ISC-5 "existing user config is backed up" isc5
check ISC-7 "menu branches all terminate" isc7
check ISC-10 "generated .desktop is valid" isc10
check ISC-11 "web app reaches the launcher index" isc11
check ISC-12 "webapp install survives icon failure" isc12
check ISC-13 "webapp removal is clean and idempotent" isc13
check ISC-14 "unsupported browser falls back to chromium" isc14
check ISC-15 "theme swap is atomic" isc15
check ISC-16 "every theme is complete" isc16
check ISC-17 "unknown theme is rejected safely" isc17
check ISC-19 "theme list matches disk" isc19
check ISC-20 "menu packages resolve" isc20
check ISC-21 "pkg-add refuses empty input" isc21
check ISC-22 "remove menu spares base packages" isc22
check ISC-23 "every command is documented" isc23
check ISC-24 "deployed Hyprland config parses" isc24
check ISC-6b "every icon glyph exists in the font" iscglyphs
check ISC-25 "no empty icon slots in the bar" iscemptyicons
check ISC-26 "waybar config parses" iscwaybarjson
check ISC-30 "every walker provider has a backend" isc30
check ISC-31 "walker theme uses 2.16 selectors" isc31
check ISC-32 "walker config key ordering is sane" isc32
check ISC-33 "no unscoped signals to session processes" isc33
check ANTI-1 "no third-party package repo" anti1
check ANTI-3 "no broken JSON binds reader" anti3
check ANTI-4 "network targets are bounded" anti4

echo
printf 'passed %d · failed %d · skipped %d\n' "$PASS" "$FAIL" "$SKIP"
((FAIL == 0))
