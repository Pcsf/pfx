# pfx

A post-install script that turns a vanilla Arch Linux system into a complete,
themed, keyboard-driven Hyprland desktop. Everything comes from the official
Arch repositories and the AUR — no third-party binary repository, no ISO, no
release channels.

## Install

### What you need first

**Vanilla Arch, and nothing else.** Do *not* install Hyprland beforehand — pfx
installs it, along with the bar, the launcher, the fonts and everything else.
`hyprland`, `hyprlock`, `hypridle`, `uwsm`, `waybar`, `base-devel` and `git`
are all in `install/packages.txt`.

Run `archinstall` with a **minimal profile, no desktop environment**, and make
sure you end up with:

| Requirement | Why |
|---|---|
| A normal user account in the `wheel` group, with sudo working | `install.sh` refuses to run as root and asks for sudo once |
| A working network connection | ~1 GB of packages get downloaded |
| `git` installed (`sudo pacman -S git`) | Arch's `base` does not include it, and you need it to clone |

Preflight will stop you if any of these are missing: it checks for
`/etc/arch-release`, refuses to run as root, requires `pacman`, and requires
sudo to authenticate. A missing network is only a warning.

You do **not** need an AUR helper — `base-devel` arrives in step 10 and yay is
built from source in step 20.

### Then

```bash
git clone https://github.com/Pcsf/pfx ~/pfx
cd ~/pfx
./install.sh --dry-run   # see exactly what it will do, change nothing
./install.sh             # do it
```

You will be asked for your sudo password once, early; the rest is unattended.
Log out afterwards and start the session from a TTY:

```bash
uwsm start hyprland-uwsm.desktop
```

Press <kbd>SUPER</kbd>+<kbd>K</kbd> for the keybinding list and
<kbd>SUPER</kbd>+<kbd>ALT</kbd>+<kbd>SPACE</kbd> for the menu.

### After: the machine-specific bits

pfx deliberately ships no hardware quirk handling, so three things are yours to
set on a real machine.

**Keyboard.** The shipped default is a bare `kb_layout = us`. Drop your own
settings into `~/.config/hypr/input.conf`, which is sourced *after* the
defaults and therefore wins:

```
input {
    kb_layout = us
    kb_options = compose:caps    # Caps Lock becomes Compose: ç, á, ê, ü, …

    repeat_rate = 40             # faster key repeat than the default
    repeat_delay = 250           # and a shorter wait before it starts
    numlock_by_default = true

    touchpad {
        clickfinger_behavior = true
        scroll_factor = 0.4
    }
}
```

`compose:caps` is the useful part on a US layout: Compose then `'` then `c`
gives `ç`, Compose `'` `a` gives `á`, and so on — accented characters without
giving up a US keyboard. To add a second layout instead, use a group toggle:

```
kb_layout = us,br
kb_options = compose:caps,grp:alt_shift_toggle    # Alt+Shift switches layout
```

Toggle names come from the xkb rules, not from Hyprland. There are 45 of them —
`grp:alt_shift_toggle` (Alt+Shift), `grp:alts_toggle` (both Alts together) and
`grp:caps_toggle` are the common ones. List them all with:

```bash
grep -E '^  grp:' /usr/share/X11/xkb/rules/base.lst
```

Same file lists every `compose:` option, if you would rather put Compose
somewhere other than Caps Lock.

Set the console and X11 layouts to match while you are at it, so the TTY and
XWayland agree with Hyprland:

```bash
sudo localectl set-keymap us
sudo localectl set-x11-keymap us pc105 "" compose:caps
```

**Input method (optional).** If you type languages that need composition
beyond a Compose key, pfx does not install one. Add it yourself:

```bash
pfx pkg add fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool
```

then export `GTK_IM_MODULE`, `QT_IM_MODULE` and `XMODIFIERS` in
`~/.config/hypr/envs.conf` and start it from `~/.config/hypr/autostart.conf`.

**Monitors and GPU.** Set your real display layout in
`~/.config/hypr/monitors.conf` (`hyprctl monitors` lists what is attached); the
shipped `preferred, auto, auto` handles one screen but will not place two
sensibly. NVIDIA also needs `nvidia`/`nvidia-utils` and kernel parameters that
pfx does not install.

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

## Testing

Three rungs, none of which replaces another.

```bash
./tools/test-container.sh    # ~90s cached — installs into a clean Arch container
./tools/test-nested.sh       # ~30s — real compositor inside your current session
```

The **container** proves the install works: real `pacman` and AUR runs, config
deployment, idempotency, the theme engine, web apps, and Hyprland config
parsing. All 26 probes pass in it. It cannot start a compositor — Hyprland
needs DRM and a seat, and 0.56 exposes no headless switch.

The **nested session** proves the desktop works: real waybar, real menu, real
theme switching, real keybindings. It runs under a scratch `HOME` in `/tmp`
with its own compositor instance, so your `~/.config` is never read or written,
and destructive System-menu items are disabled inside it. Exit with
`SUPER+SHIFT+ALT+Q`, or `pkill -f 'Hyprland -c /tmp/pfx-nested'` from anywhere.

```bash
./tools/test-vm.sh --install   # first run: a few minutes
./tools/test-vm.sh --gui       # boot with a virtual GPU and see the desktop
```

The **VM** is the only rung that exercises the real boot path — systemd,
logind, a login session, and Hyprland on an actual DRM device. It is also the
only honest place to check the application launcher, because only there does
`elephant` run against pfx's own packaging rather than the host's.

It does not run `archinstall`: Arch publishes an official cloud image, so the
base system arrives ready and cloud-init creates the user. The disk is a
copy-on-write overlay, so `--fresh` throws it away and the next boot is a
pristine Arch system.

Requires `qemu-desktop` and `cloud-image-utils`.

**Run the VM fullscreen** (`--fullscreen`). QEMU rescales the guest framebuffer
to whatever size the window is, so a 1920x1080 guest in a slightly smaller
window gets squashed a few percent vertically — which shaves a pixel row off
every glyph and makes the text look clipped along the top, as though the font
were bad. The guest is rendering it perfectly. Fullscreen with the menu bar off
makes the window exactly the monitor size, so pixels map one-to-one.

**The QEMU window grabs the keyboard on hover.** Without that, every `SUPER`
binding you press goes to the compositor you are sitting in, not to the VM —
pressing `SUPER+W` to test pfx's close binding makes *your* window manager
close the QEMU window instead. The window's close button is also disabled
(`window-close=off`) so a stray click cannot take the running VM with it; shut
it down with `--stop`.

Idle management is disabled inside the VM. The shipped `hypridle.conf` blanks
the display after 11 minutes and suspends the machine after 30 — correct for a
laptop, but in a VM both are indistinguishable from a crash (QEMU reports
"Display output is not active", then ssh stops answering). If a VM does freeze,
`./tools/test-vm.sh --wake` sends an ACPI wake-up rather than making you reboot.

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
