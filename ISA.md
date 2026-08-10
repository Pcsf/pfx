---
task: "Post-Arch install script and desktop toolkit"
slug: 20260809-pfx-arch-hyprland-toolkit
effort: extended
effort_source: auto
phase: complete
progress: 33/33
mode: iterate
started: 2026-08-09T08:45:00Z
updated: 2026-08-09T09:25:00Z
principal_stated_goal: "I would like to make my own install starting from the basic Arch+hyperland incorporating the omarchy approach on menu system, webb apps and several others. No need to make it an iso or anything else more complicated than an instalation script to be runned just after arch linux vanyla install."
principal_stated_goal_source: prompt
principal_stated_goal_signal: 1
principal_stated_goal_locked: 2026-08-09T08:45:00Z
---

# pfx — Arch + Hyprland desktop toolkit

## Problem

Omarchy is an excellent opinionated Arch/Hyprland desktop, but adopting it means adopting all of it: its package repository, its release channels, its ISO, its 149-package base, its taste. Paulo wants the *mechanisms* — the walker-driven menu, web apps as first-class desktop entries, atomic theme switching — on top of a vanilla Arch install he controls, with no third-party binary repo in his `pacman.conf` and no ISO to build.

The specific failure this avoids: being two months stale on an upstream tree you didn't choose (as happened this session — `pacman -Syu` moved Hyprland to 0.56.0 while the omarchy checkout sat at May's 3.8.2, and a broken `hyprctl -j binds` serializer silently emptied the keybindings menu).

## Vision

One shell script, run once on a freshly-installed vanilla Arch box with a working network, that leaves behind a complete, themed, keyboard-driven Hyprland desktop. Afterwards a `pfx` command manages it: launch things, install things, switch themes, add web apps. Every package comes from Arch's own repos or the AUR. The whole system is readable bash a competent engineer can audit in an afternoon.

The split that makes it maintainable, lifted from Omarchy: system defaults live in a read-only tree that updates cleanly, and user overrides live in `~/.config` where they survive updates. Configs source defaults first, user files second, so the last word is always the user's.

## Out of Scope

- ISO building, archiso, live media, bootable images
- A binary package repository, package signing, mirrors, or release channels
- A migration system for upgrading existing installs (single-machine scope; `git pull` + re-run `install.sh` is the update story)
- Arch installation itself — partitioning, base install, bootloader, user creation are the operator's job before this script runs
- Multi-user or system-wide installation; everything lands under `$HOME`
- Display-manager configuration (login is TTY + `uwsm`/`Hyprland`)

## Principles

- **Readable over clever.** Bash that reads top-to-bottom. No sourcing chains more than two deep.
- **Idempotent by default.** Re-running `install.sh` on a configured machine converges rather than duplicates or errors.
- **Never clobber user edits.** User config files are written only if absent, or backed up with a timestamp first.
- **Defaults are replaceable, user files are sacred.** Anything in `~/.local/share/pfx` may be overwritten on update; anything in `~/.config` may not.
- **No inherited bugs.** Where Omarchy's implementation is known-broken on current upstream, implement the correct thing rather than porting the defect.

## Constraints

- Arch Linux, `pacman` + one AUR helper (`yay`), Wayland, Hyprland
- Bash 5.x only — no Python, no Node, no compiled components
- Packages from `core`/`extra`/`multilib` and the AUR exclusively; nothing from `pkgs.omarchy.org`
- MIT-licensed derivation from Omarchy where code is adapted; attribution retained in `NOTICE`
- Must not require the operator to answer prompts mid-install beyond one sudo password
- Command prefix is `pfx`; config home is `~/.config/pfx`; system home is `~/.local/share/pfx`

## Goal

A `pfx` repository whose `install.sh`, run once on vanilla Arch, produces a working themed Hyprland desktop with a walker-driven menu system, web-app support, an atomic theme engine, and install/remove menus — all sourced from Arch + AUR, all verifiable without a reboot.

## Criteria

**Installer**

- [x] ISC-1: `bash -n` parses every `.sh` file in the repo with zero syntax errors. *(probe: `find . -name '*.sh' -exec bash -n {} \;` exits 0)*
- [x] ISC-2: `install.sh --dry-run` prints every action it would take and mutates nothing — no files created, no packages installed, no `sudo` invoked. *(probe: run under a scratch `HOME`, diff the tree before/after; `strace`-free check via file-count equality)*
- [x] ISC-3: `install.sh --dry-run` names every package it would install, and every named package resolves in the Arch repos or AUR. *(probe: `pacman -Si` for repo packages; all must resolve)*
- [x] ISC-4: Running the config-deploy step twice leaves identical output the second time and creates no `.bak` files on the second pass. *(probe: run twice under scratch `HOME`, compare `find` output and backup count)*
- [x] ISC-5: The config-deploy step backs up a pre-existing user file rather than overwriting it. *(probe: seed a sentinel `~/.config/hypr/bindings.conf`, deploy, assert sentinel content survives in a `.bak.*` file)*

**Menu system**

- [x] ISC-6: `pfx-menu` renders a top-level menu through `walker --dmenu` and dispatches to submenus. *(probe: screenshot of the live overlay showing populated entries)*
- [x] ISC-7: Every menu branch reachable from the main menu terminates in either an action or a `back_to` return — no dead ends, no unhandled cases. *(probe: static enumeration of every `case` arm against the submenu function list)*
- [x] ISC-8: `pfx-menu-keybindings --print` lists every bind Hyprland has loaded, parsed from a source that is correct on Hyprland 0.56.0. *(probe: line count matches `hyprctl binds` block count; zero unresolved `code:` entries)*
- [x] ISC-9: Invoking the menu while a menu is already open closes it rather than stacking a second overlay. *(probe: launch twice, assert walker layer count is 0)*

**Web apps**

- [x] ISC-10: `pfx-webapp-install <name> <url>` writes a valid `.desktop` file that `desktop-file-validate` accepts. *(probe: `desktop-file-validate` exits 0)*
- [x] ISC-11: An installed web app appears in the application launcher's index. *(probe: the `.desktop` file lands in `~/.local/share/applications` and `gtk-launch --help`-visible name resolves)*
- [x] ISC-12: `pfx-webapp-install` fetches a favicon when none is supplied and still succeeds when the fetch fails. *(probe: install with an unreachable domain; assert exit 0 and a fallback icon reference)*
- [x] ISC-13: `pfx-webapp-remove` deletes both the `.desktop` entry and its icon, and is a no-op on an unknown name. *(probe: install, remove, assert both paths gone, exit 0; remove again, assert exit 0)*
- [x] ISC-14: `pfx-launch-webapp` resolves the user's default browser and falls back to chromium when it is unsupported. *(probe: run with `--print-cmd` under a stubbed `xdg-settings`, assert the chromium fallback)*

**Theme engine**

- [x] ISC-15: `pfx-theme-set <name>` swaps the current theme atomically — no window in which `~/.config/pfx/current/theme` is partially populated. *(probe: build into `next-theme`, single `mv`; assert via code path that no `cp` targets `current/theme`)*
- [x] ISC-16: Every shipped theme provides the full file set the templates consume, so no app falls back to unstyled defaults. *(probe: for each theme dir, assert presence of every file named in the template manifest)*
- [x] ISC-17: `pfx-theme-set` on an unknown name exits non-zero and leaves the current theme untouched. *(probe: capture `current/theme.name` before and after a bogus set)*
- [x] ISC-18: Applying a theme updates the live Hyprland border colour without a compositor restart. *(probe: `hyprctl getoption general:col.active_border` differs across two theme sets, compositor PID unchanged — run against a nested session)*
- [x] ISC-19: `pfx-theme-list` output and the on-disk theme directories agree exactly. *(probe: diff the command output against `ls themes/`)*

**Install / remove menus**

- [x] ISC-20: Every package named in an install-menu entry resolves in the Arch repos or AUR. *(probe: extract all `pfx-pkg-add`/`pfx-pkg-aur-add` arguments from the menu, resolve each)*
- [x] ISC-21: `pfx-pkg-add` is non-interactive and refuses to run with an empty argument list. *(probe: invoke with no args, assert non-zero exit and no pacman call)*
- [x] ISC-22: The remove menu never offers a package that is part of the base install set. *(probe: intersect remove-menu package names with `install/packages.txt`; assert empty)*

**Launcher backend**

- [x] ISC-30: Every provider named in the walker config is carried by a package the installer requests. *(probe: intersect `config.toml` providers against the AUR `Provides` of every elephant package in `packages-aur.txt`)*
- [x] ISC-31: The walker theme uses walker 2.16 row selectors, so the selection highlight renders. *(probe: `child:selected` present, `.item:selected` absent)*
- [x] ISC-32: `theme` and `additional_theme_location` resolve at TOML top level, not swallowed by a `[table]`. *(probe: `tomllib.load`, assert both are root keys)*
- [x] ISC-33: No command signals a session process it does not own, and the nested harness runs the installer with no instance signature. *(probe: grep `bin/` for unscoped `pkill`/`killall` of waybar/mako/hyprpaper/walker/elephant; assert `env -u HYPRLAND_INSTANCE_SIGNATURE` in test-nested.sh)*

**Testing harness**

- [x] ISC-25: No icon slot in the bar config is present but empty. *(probe: grep for format strings that are whitespace-only or whose icon position is blank)*
- [x] ISC-26: The waybar config is valid JSON once `//` comments are stripped. *(probe: `json.loads` on the stripped file)*
- [x] ISC-27: A container install passes every probe that does not need a screen. *(probe: `./tools/test-container.sh`)*
- [x] ISC-28: A nested session runs the real compositor without reading or writing anything the user owns. *(probe: md5 of live `~/.config/hypr/*` and absence of `~/.config/pfx` before and after)*
- [x] ISC-29: Restarting a component affects only the invoking Hyprland instance. *(probe: two sessions running, `pfx-session-pids waybar` returns a different PID in each)*

**Whole-system**

- [x] ISC-23: Every `pfx-*` command in `bin/` carries a `# pfx:summary=` line, and `pfx --help` lists all of them. *(probe: count summary lines vs `ls bin/`, compare to `pfx --help` output)*
- [x] ISC-24: The deployed Hyprland config parses with zero errors on a live compositor. *(probe: `hyprctl configerrors` empty after sourcing the generated config in an isolated check)*

### Anti-criteria

- [x] ANTI-1: The installer must never modify `/etc/pacman.conf` to add a third-party repository. *(probe: grep the entire repo for `pkgs.omarchy.org` and for writes to `pacman.conf`; both must be empty)*
- [x] ANTI-2: The installer must never overwrite an existing user config file without leaving a recoverable backup. *(probe: ISC-5; plus grep for `cp` into `~/.config` without a preceding backup guard)*
- [x] ANTI-3: No command may consume `hyprctl -j binds`, whose serializer is broken on Hyprland 0.56.0. *(probe: `grep -r 'hyprctl -j binds\|hyprctl.*binds.*-j' bin/` returns nothing)*
- [x] ANTI-4: The install must not require network access to any host other than the Arch mirrors, the AUR, and icon CDNs at web-app creation time. *(probe: grep for `curl`/`wget` targets across the repo; each must be one of those three classes)*
- [x] ANTI-5: Nothing in the repo may write to Paulo's live `~/.config` during development or verification. *(probe: all test runs use a scratch `HOME`; assert live `~/.config/hypr` mtime unchanged across the build)*

## Test Strategy

| Probe class | Mechanism |
|---|---|
| Syntax | `bash -n` across every script; `shellcheck` if installable |
| Isolation | every behavioural test runs under `HOME=$(mktemp -d)` so the live desktop is never touched |
| Package resolution | `pacman -Si <pkg>` for repo packages; AUR names checked against the AUR RPC endpoint |
| Desktop entries | `desktop-file-validate` |
| Menu rendering | launch through walker, capture with `grim`, view the pixels |
| Theme atomicity | code-path assertion plus live `hyprctl getoption` before/after |
| Config validity | `hyprctl configerrors` against the generated config |

## Features

- [x] F1: Repository skeleton, `NOTICE`, `README`
- [x] F2: Installer — preflight, packages, AUR helper, config deploy, PATH, services
- [x] F3: `pfx` dispatcher + `--help` from `pfx:summary` lines
- [x] F4: Launcher primitives — walker wrapper, launch-or-focus, terminal/editor/browser
- [x] F5: Web app subsystem — install, remove, launch, launch-or-focus
- [x] F6: Theme engine — set, list, current, next, background cycling, template pass
- [x] F7: Menu system — main, apps, style, install, remove, system, keybindings
- [x] F8: Hyprland + waybar + walker + mako + terminal default configs
- [x] F9: Three themes with full file sets
- [x] F10: Verification pass against all ISCs and anti-criteria
- [x] F11: Container harness (`Dockerfile`, `tools/test-container.sh`)
- [x] F12: Nested-session harness (`tools/test-nested.sh`) with session-scoped kills and a nested safety gate

## Decisions

| Decision | Rationale |
|---|---|
| Arch + AUR only, no `pkgs.omarchy.org` | Paulo's explicit choice. Removes a third-party trust and availability dependency; costs some AUR build time. |
| Hybrid derivation — rewrite core, adapt details | Paulo's explicit choice. Menu/webapp/theme machinery written clean; Hyprland defaults and xkb keycode mapping adapted from Omarchy (MIT, attributed). |
| No migration system | Paulo descoped it. Update path is `git pull && ./install.sh`, which is safe because deploy is idempotent and backs up. |
| `default/` (system, replaceable) vs `config/` (user, sacred) | Omarchy's best structural idea. Makes updates non-destructive without a migration engine. |
| Parse `hyprctl binds` plain text, never `-j` | The 0.56.0 serializer emits invalid JSON. Verified this session. Plain text is stable and correct. |
| `walker` as the menu backend | Already the Omarchy choice, available in AUR, and the `--dmenu` contract is simple enough to swap for `fuzzel`/`wofi` later. |

## Changelog

- **conjectured:** the bulk of Omarchy's value is in its 25k lines of bash.
  **refuted by:** reading the sources — web apps are ~100 lines, `launch-or-focus` is 20, the theme core is 73, and the 891-line menu is ~50 lines of machinery wrapping 840 lines of content.
  **learned:** the mechanisms are small; the value is curation and taste. Reimplementing the machinery is cheap, so a clean rewrite costs little and avoids inherited defects.
  **criterion now:** ISCs target behaviour of the mechanisms, not line-count parity with Omarchy.

## Verification

Re-runnable: `./tools/verify.sh` — 24 automated probes, all passing as of 2026-08-09.

| Claim | Evidence |
|---|---|
| ISC-1 | 39 scripts parsed by `bash -n`, zero errors |
| ISC-2 | scratch `HOME` held 1 path before and after `--dry-run` |
| ISC-3 | 67 packages, all resolve in `core`/`extra` or the AUR RPC |
| ISC-4 | second deploy reported "already current", wrote zero `.bak` files |
| ISC-5 | sentinel content recovered from `bindings.conf.bak.1786260163` |
| ISC-6 | screenshot of the live overlay: 8 entries, all icons rendering |
| ISC-6b | all 8 icon codepoints present in JetBrainsMono Nerd Font (ink test) |
| ISC-7 | 16 submenus, every one defined and carrying a fallback arm |
| ISC-8 | 192 formatted lines against 192 `hyprctl binds` blocks — exact parity |
| ISC-9 | walker layer count 0 after a second invocation |
| ISC-10 | `desktop-file-validate` exits 0 on the generated entry |
| ISC-11 | entry written to the XDG applications dir, `mimeinfo.cache` produced |
| ISC-12 | install against `nonexistent.invalid` exits 0 with `Icon=applications-internet` |
| ISC-13 | entry and icon gone; removing an unknown name exits 0 |
| ISC-14 | stubbed firefox default → `/usr/bin/chromium --app=https://example.com` |
| ISC-15 | staged directory plus one `mv -T` onto the symlink; no `cp` targets the live path |
| ISC-16 | 3 themes × 7 manifest files, all present, all with backgrounds |
| ISC-17 | bogus name exits 1, `theme.name` unchanged |
| ISC-19 | `pfx-theme-list` output byte-identical to `ls themes/` |
| ISC-20 | 26 distinct menu packages, all resolve |
| ISC-21 | exits 1 with a usage message on empty input |
| ISC-22 | `pfx-pkg-remove hyprland` refused with a base-install message; non-base names pass |
| ISC-23 | 24 commands, all carrying `pfx:summary`, all executable, all listed by `pfx --help` |
| ISC-24 | `Hyprland --verify-config` on the deployed config: `config ok`, zero errors |
| ANTI-1 | no `pkgs.omarchy.org` reference, no `pacman.conf` write outside prose |
| ANTI-3 | no command reads `hyprctl -j binds` outside an explanatory comment |
| ANTI-4 | network targets limited to Arch, the AUR, and the favicon service |
| ANTI-5 | every behavioural probe ran under `HOME=$(mktemp -d)`; the live `~/.config` was never written |

**ISC-18 closed** (2026-08-10, nested session). The deferral is resolved: a nested Hyprland running pfx changed `general:col.active_border` from `ff7aa2f7` (tokyo-night accent) to `ff83a598` (gruvbox accent) across a `pfx-theme-set`, with the compositor PID unchanged at 2539961 and the outer session's border untouched at `ffe8e6e3 ffc4b5a0 45deg`. Both values match their palettes exactly.

**Testing ladder**

| Rung | Command | Covers | Time |
|---|---|---|---|
| Container | `./tools/test-container.sh` | all 26 non-visual probes, real package install, AUR bootstrap | ~90s cached |
| Nested | `./tools/test-nested.sh` | real compositor, bar, menu, theme, keybindings, ISC-18 | ~30s |
| VM | manual | boot path, systemd, login session | ~1h first time |

No rung supersedes another. The container cannot start a compositor (`CBackend::create() failed!` — Hyprland needs DRM and a seat, and 0.56 exposes no headless switch). The nested session cannot test the boot path or systemd, because it is a guest inside an already-running login session.

**Bugs this pass caught and fixed:**

1. `pfx-launch-webapp` died under `set -e` when the browser's `.desktop` file was absent, so the chromium fallback was unreachable — the exact path a fresh install takes.
2. `bin/pfx-menu` and `install.sh` were not executable, which made `pfx-menu` invisible to the dispatcher and the installer unrunnable. Swept every intended entry point; probe added to ISC-23.
3. `install.sh` assumed `~/.config` existed — false on a genuinely fresh account.
4. Window rules used pre-0.53 syntax (`class:^(...)$`); `dwindle:pseudotile`, `misc:vfr` and the `gestures {}` block no longer exist; `togglesplit` is a `layoutmsg`, not a dispatcher. Eleven config errors, all found by ISC-24 and none visible without it.
5. Sixty of 68 menu entries silently lost their icon glyphs, and two surviving choices were semantically wrong — Remove rendered as a **power symbol**. Menu now carries eight verified glyphs; ISC-6b locks it.

**Third pass (2026-08-10), after "I couldn't see the menu and walker working":**

9. **The application launcher was completely broken and every screenshot had hidden it.** Walker 2.x delegates all data to a separate `elephant` daemon. `walker-bin` depends on bare `elephant`, which ships *no providers*; `elephant-all` — which carries `desktopapplications`, `calc`, `files`, `symbols` — is merely an **optional** dependency. So `SUPER+SPACE`, the most-used key on the desktop, would have opened an empty list with no error in any log. Every menu screenshot used `--dmenu`, which needs no providers at all, so the gap was invisible to all 29 probes. `elephant-all` is now installed from the AUR and started before walker in autostart; ISC-30 checks the config-to-package mapping.

10. **The walker theme's CSS class names were wrong.** Walker 2.16 calls a list row `child` and the selected row `child:selected .item-box`; pfx styled `.item:selected`, which parses fine and matches nothing. The result was a menu with no selection highlight — no feedback about what Enter would do. ISC-31 locks the selector.

11. `hide_action_hints = true` does not hide the F1–F4 badges; those are `quick_activate`, a separate `[keybinds]` setting. Fixed, and the config was rewritten so every top-level key precedes the first `[table]` — TOML would otherwise have folded `theme` into `[keybinds]`, silently leaving walker on its default theme. ISC-32 asserts the ordering.

12. **The nested harness signalled the real desktop and eventually killed its bar.** `install.sh`'s theme step runs `pfx-theme-set`, and `test-nested.sh` ran the installer in the invoking shell — which carries the *real* session's `HYPRLAND_INSTANCE_SIGNATURE`. So every nested test ran `hyprctl reload` and `pkill -SIGUSR2 waybar` against the live session; SIGUSR2 resets the bar, and repeated resets left it dead. Two causes, both fixed: `pfx-theme-set` still had an unscoped `pkill` that the earlier sweep missed, and the harness must strip the signature before the install, not only at launch. ISC-33 covers the whole class and was validated by reintroducing the exact line and watching it fail.

**Second pass (2026-08-10), building the test harnesses:**

6. **The same glyph loss had hit the entire waybar config and ISC-6b did not catch it.** Every icon in the bar was gone, and `bluetooth.format` had become an empty string, so that module rendered nothing at all. The probe passed because it asked *"is every glyph I use valid?"* — and a file with zero glyphs satisfies that trivially. Absence has to be tested for directly, not inferred from validity. ISC-25 now greps for empty icon slots; ISC-6b was widened from one file to all 48 under `bin/`, `config/` and `default/`. Found by looking at a screenshot of the nested bar, not by any probe.

7. `pfx-restart` used `pkill -x waybar`, which kills *every* waybar the user owns. Harmless with one session, actively wrong with two — restarting the bar in a nested test session would have killed the bar on the real desktop. Now scoped via `pfx-session-pids`, which matches on `HYPRLAND_INSTANCE_SIGNATURE`. Verified with two sessions live: each returned only its own PID. `pfx-theme-bg-next` had the same defect for `hyprpaper`.

8. The System menu's Lock, Suspend, Reboot and Shut down act on the machine, not the compositor — they would hit the real desktop from inside a nested session. Gated behind `PFX_NESTED`. Log out is exempt: `hyprctl dispatch exit` correctly targets only the nested instance.
