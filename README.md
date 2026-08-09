# pfx

A post-install script that turns a vanilla Arch Linux system into a complete,
themed, keyboard-driven Hyprland desktop. Everything comes from the official
Arch repositories and the AUR — no third-party binary repository, no ISO, no
release channels.

## Install

Install Arch normally (base system, a user account, a network connection),
then:

```bash
git clone https://github.com/<you>/pfx ~/pfx
cd ~/pfx
./install.sh --dry-run   # see exactly what it will do
./install.sh             # do it
```

You will be asked for your sudo password once, early. Log out afterwards and
start the session from a TTY:

```bash
uwsm start hyprland-uwsm.desktop
```

Press <kbd>SUPER</kbd>+<kbd>K</kbd> for the keybinding list and
<kbd>SUPER</kbd>+<kbd>ALT</kbd>+<kbd>SPACE</kbd> for the menu.

## The one structural idea

Configuration is split in two, and the split is what makes updates safe:

| Tree | Owner | On update |
|---|---|---|
| `~/.local/share/pfx/` | pfx | **replaced wholesale** |
| `~/.config/` | you | never overwritten without a timestamped backup |

Your `~/.config/hypr/hyprland.conf` sources the pfx defaults first and your
own files second, so your settings always win. That means pfx can ship a new
default keybinding without touching anything you wrote, and without needing a
migration system to reconcile the two.

To override a default binding, unbind it first — Hyprland keeps both otherwise:

```
unbind = SUPER, F
bindd = SUPER, F, Files, exec, uwsm-app -- nautilus --new-window
```

## Commands

Everything is `pfx <group> <action>`, and every command also works standalone
as `pfx-<group>-<action>`. Run `pfx --help` for the full list.

```bash
pfx menu                          # the menu
pfx menu keybindings              # searchable keybinding list
pfx theme set nord                # switch theme
pfx theme next                    # cycle
pfx webapp install Grafana https://grafana.example.com
pfx webapp remove Grafana
pfx capture screenshot region
pfx pkg add ripgrep
```

## Web apps

A web app is a URL that behaves like a native application: its own window, its
own launcher entry, its own alt-tab slot. `pfx-webapp-install` writes a
`.desktop` file whose `Exec` runs the browser with Chromium's `--app=` flag,
which is the entire mechanism — no wrapper process, no extension.

```bash
pfx webapp install "Home Assistant" https://ha.local
```

The icon is fetched automatically from the site's favicon. If that fails the
app still installs with a generic icon.

## Themes

A theme is a directory of colour files, one per app. `pfx-theme-set` resolves
it, stages it, and repoints `~/.config/pfx/current/theme` — a symlink — with a
single `rename(2)`. Nothing ever observes a half-applied theme.

Every app reads its colours from that stable path, so switching themes needs no
templating step and no config rewriting.

Shipped: `tokyo-night`, `gruvbox`, `nord`.

To add one, write a palette and generate it:

```bash
cp tools/palettes/nord.sh tools/palettes/mine.sh
$EDITOR tools/palettes/mine.sh
./tools/make-theme.sh mine tools/palettes/mine.sh
pfx theme set mine
```

To tweak a shipped theme without forking it, drop the files you want to change
into `~/.config/pfx/themes/<name>/`. They are overlaid on top of the stock
theme, so a single-file override is enough.

## Updating

```bash
cd ~/pfx && git pull && ./install.sh
```

Safe by construction: the system tree is replaced, user configs are compared
and left alone when unchanged, and backed up when they differ.

## What this is not

No ISO. No package repository. No migration engine. No release channels. If you
want those, run [Omarchy](https://omarchy.org) — it does all of it well, and pfx
owes it the architecture. See `NOTICE`.

## Layout

```
install.sh              entry point
install/
  packages.txt          official-repo packages
  packages-aur.txt      AUR packages (kept deliberately short)
  helpers.sh            run(), deploy_config(), backup_if_exists()
  steps/                numbered, sourced in order
bin/                    every pfx-* command
default/                system config, replaced on update
config/                 user config, copied to ~/.config once
themes/                 generated colour sets
tools/make-theme.sh     palette → theme
ISA.md                  what "done" means, as testable claims
```
