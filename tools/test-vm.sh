#!/bin/bash
#
# Test pfx in a throwaway Arch VM.
#
# This is the top rung of the testing ladder — the only one that exercises the
# real boot path: systemd, logind, a login session, and Hyprland starting on a
# real DRM device rather than as a guest of an existing compositor. It is the
# only place the application launcher can honestly be verified, because it is
# the only place elephant runs against pfx's own packaging instead of the
# host's.
#
# It does NOT run archinstall. Arch publishes an official cloud image, so the
# base system arrives ready and cloud-init creates the user. First run takes a
# few minutes (mostly the pfx package install); later runs are seconds.
#
# Usage:
#   ./tools/test-vm.sh            boot the VM (creates it on first run)
#   ./tools/test-vm.sh --install  boot, sync the repo, run install.sh, reboot
#   ./tools/test-vm.sh --gui      boot with a virtual GPU and start Hyprland
#   ./tools/test-vm.sh --ssh      shell into a running VM
#   ./tools/test-vm.sh --wake     wake a guest that suspended itself
#   ./tools/test-vm.sh --stop     shut the VM down
#   ./tools/test-vm.sh --fresh    discard the disk and start over
#   ./tools/test-vm.sh --clean    delete everything including the base image
#
# The VM is fully disposable: --fresh throws away the overlay disk and the next
# boot is a pristine Arch system again. Nothing it does can reach your desktop.

set -eEuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/pfx-vm"

BASE_IMAGE="$CACHE/Arch-Linux-x86_64-cloudimg.qcow2"
BASE_URL="https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
DISK="$CACHE/pfx-test.qcow2"
SEED="$CACHE/seed.iso"
KEY="$CACHE/id_ed25519"
MONITOR="$CACHE/monitor.sock"
PIDFILE="$CACHE/qemu.pid"

SSH_PORT=2222
VM_USER=pfx
RAM=4096
CPUS=4
DISK_SIZE=20G

bold=$'\e[1m' dim=$'\e[2m' green=$'\e[32m' yellow=$'\e[33m' red=$'\e[31m' reset=$'\e[0m'

info() { printf '  %s\n' "$1"; }
ok() { printf '  %s✓%s %s\n' "$green" "$reset" "$1"; }
warn() { printf '  %s!%s %s\n' "$yellow" "$reset" "$1"; }
die() {
  printf '\n  %s✗ %s%s\n\n' "$red" "$1" "$reset" >&2
  exit 1
}

ssh_vm() {
  ssh -q -i "$KEY" -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 -o LogLevel=ERROR \
    "$VM_USER@localhost" "$@"
}

vm_running() { [[ -f $PIDFILE ]] && kill -0 "$(<"$PIDFILE")" 2>/dev/null; }

# Start the desktop automatically on the first console, so --gui lands in pfx
# rather than at a shell prompt.
#
# The `command -v Hyprland` guard matters: without it, a VM where the install
# failed would try to exec a missing binary on every login and leave you with
# no way to reach a shell.
enable_desktop_autostart() {
  ssh_vm "cat > ~/.bash_profile" <<'PROFILE'
# Written by pfx tools/test-vm.sh.
[[ -f ~/.bashrc ]] && source ~/.bashrc

if [[ -z ${WAYLAND_DISPLAY:-} ]] && [[ ${XDG_VTNR:-0} == 1 ]] && command -v Hyprland >/dev/null 2>&1; then
  echo "Starting the pfx desktop… (Ctrl+C within 3s for a shell)"
  sleep 3 || return
  exec uwsm start hyprland-uwsm.desktop
fi
PROFILE

  # A virtual output's "preferred" mode is small. Give the VM a real desktop
  # resolution through the ordinary user override — which also demonstrates
  # that the defaults/user config split works.
  ssh_vm "cat > ~/.config/hypr/monitors.conf" <<'MONITORS'
# VM override, written by tools/test-vm.sh.
# 1920x1080 gives a realistic desktop; resize the QEMU window and Hyprland
# follows, or run the VM with --fullscreen.
monitor = , 1920x1080@60, 0x0, 1
MONITORS

  # Idle management OFF in the VM.
  #
  # The shipped timeouts are right for a laptop and wrong for a test machine:
  # after 11 minutes untouched the display goes DPMS-off and QEMU reports
  # "Display output is not active", and after 30 it runs `systemctl suspend`,
  # which freezes the guest and kills ssh. Both look exactly like a crash.
  #
  # To test the real idle behaviour, comment this file out and shorten the
  # timeouts in ~/.config/hypr/hypridle.conf instead of waiting them out.
  ssh_vm "cat > ~/.config/hypr/hypridle.conf" <<'HYPRIDLE'
# VM override, written by tools/test-vm.sh — no idle actions.
# The shipped config dims at 5min, locks at 10, blanks at 11 and suspends at
# 30. In a VM the last two are indistinguishable from a hang.
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
}
HYPRIDLE

  ssh_vm "pkill -x hypridle; setsid hypridle >/dev/null 2>&1 &" || true
}

# ---------------------------------------------------------------- arguments

mode="boot"
fresh=false
fullscreen=false
for arg in "$@"; do
  case "$arg" in
  --install) mode="install" ;;
  --gui) mode="gui" ;;
  --fullscreen) fullscreen=true ;;
  --ssh) mode="ssh" ;;
  --wake) mode="wake" ;;
  --stop) mode="stop" ;;
  --fresh)
    fresh=true
    ;;
  --clean) mode="clean" ;;
  --help | -h)
    sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *) die "Unknown option: $arg" ;;
  esac
done

# ---------------------------------------------------------------- simple modes

if [[ $mode == clean ]]; then
  vm_running && kill "$(<"$PIDFILE")" 2>/dev/null || true
  rm -rf "$CACHE"
  echo "Removed $CACHE (including the base image)."
  exit 0
fi

if [[ $mode == stop ]]; then
  vm_running || die "No VM is running."
  ssh_vm "sudo systemctl poweroff" 2>/dev/null || kill "$(<"$PIDFILE")"
  rm -f "$PIDFILE"
  ok "VM stopped"
  exit 0
fi

if [[ $mode == wake ]]; then
  vm_running || die "No VM is running."
  [[ -S $MONITOR ]] || die "No monitor socket. Restart the VM to get one."
  # A guest that ran `systemctl suspend` is frozen in S3 and will not answer
  # ssh or repaint the display; ACPI wake is the only way back in.
  printf 'system_wakeup\n' | socat - "unix-connect:$MONITOR" >/dev/null 2>&1 ||
    die "Could not reach the monitor socket (is socat installed?)"
  ok "sent an ACPI wake-up"
  exit 0
fi

if [[ $mode == ssh ]]; then
  vm_running || die "No VM is running. Start one with: ./tools/test-vm.sh"
  exec ssh -i "$KEY" -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "$VM_USER@localhost"
fi

# ---------------------------------------------------------------- preconditions

command -v qemu-system-x86_64 >/dev/null 2>&1 || die \
  "qemu is not installed. Run:  sudo pacman -S --needed qemu-desktop cloud-image-utils"
command -v cloud-localds >/dev/null 2>&1 || die \
  "cloud-localds is missing. Run:  sudo pacman -S --needed cloud-image-utils"
[[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]] || die \
  "No access to /dev/kvm. Add yourself to the kvm group:  sudo usermod -aG kvm $USER  (then log out and in)"

mkdir -p "$CACHE"

# ---------------------------------------------------------------- base image

if [[ ! -f $BASE_IMAGE ]]; then
  echo "${bold}Fetching the official Arch cloud image (~530 MB, once)${reset}"
  curl -fL --progress-bar -o "$BASE_IMAGE.part" "$BASE_URL"
  mv "$BASE_IMAGE.part" "$BASE_IMAGE"
  ok "base image cached at $BASE_IMAGE"
fi

# ---------------------------------------------------------------- ssh key

if [[ ! -f $KEY ]]; then
  ssh-keygen -q -t ed25519 -N '' -C 'pfx-vm' -f "$KEY"
  ok "generated a throwaway ssh key"
fi

# ---------------------------------------------------------------- cloud-init

if [[ ! -f $SEED ]]; then
  user_data="$CACHE/user-data"
  cat >"$user_data" <<CLOUDINIT
#cloud-config
hostname: pfx-test

users:
  - name: $VM_USER
    groups: [wheel, video, input, audio, seat]
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    lock_passwd: false
    # Password is 'pfx' — only reachable on the VM console, which is local.
    plain_text_passwd: pfx
    ssh_authorized_keys:
      - $(cat "$KEY.pub")

ssh_pwauth: true
disable_root: true

# Autologin on tty1 so the graphical run can start Hyprland without typing a
# password into a VM window.
write_files:
  - path: /etc/systemd/system/getty@tty1.service.d/autologin.conf
    content: |
      [Service]
      ExecStart=
      ExecStart=-/sbin/agetty --autologin $VM_USER --noclear %I \$TERM

runcmd:
  - [ systemctl, daemon-reload ]
  - [ pacman-key, --init ]
  - [ pacman-key, --populate, archlinux ]
  - [ pacman, -Sy, --noconfirm, --needed, git, rsync ]
CLOUDINIT

  cloud-localds "$SEED" "$user_data"
  ok "cloud-init seed built"
fi

# ---------------------------------------------------------------- disk

if $fresh; then
  vm_running && {
    kill "$(<"$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  }
  rm -f "$DISK"
  info "discarded the previous disk"
fi

if [[ ! -f $DISK ]]; then
  # A copy-on-write overlay: the base image is never modified, so --fresh is
  # instant and the download is never repeated.
  qemu-img create -q -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$DISK" "$DISK_SIZE"
  ok "created a $DISK_SIZE overlay disk"
fi

# ---------------------------------------------------------------- boot

qemu_args=(
  -name pfx-test
  -machine q35,accel=kvm
  -cpu host
  -smp "$CPUS"
  -m "$RAM"
  -drive "file=$DISK,if=virtio,format=qcow2"
  -drive "file=$SEED,if=virtio,format=raw"
  -netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
  -device virtio-net-pci,netdev=net0
  -device virtio-rng-pci
  -pidfile "$PIDFILE"
  # A control socket, so a guest that suspended itself can be woken with
  # `--wake` instead of being killed and rebooted.
  -monitor "unix:$MONITOR,server,nowait"
)

if [[ $mode == gui ]]; then
  # virtio-gpu-gl gives the guest a real DRM device, which is what Hyprland
  # needs — without it the compositor cannot create a backend and dies exactly
  # as it does in a container.
  # No audio device on purpose: the `-audio` shorthand and the available sound
  # models vary across QEMU versions, and a rejected flag stops the VM from
  # booting at all. Nothing pfx needs testing for makes a sound.
  qemu_args+=(
    -device virtio-vga-gl
    -display gtk,gl=on,show-cursor=on
    -device qemu-xhci -device usb-tablet -device usb-kbd
  )
  $fullscreen && qemu_args+=(-full-screen)
else
  qemu_args+=(-display none -serial mon:stdio)
fi

if ! vm_running; then
  echo
  echo "${bold}Booting the VM${reset} ${dim}(${CPUS} cores, ${RAM}MB, ssh on :$SSH_PORT)${reset}"
  if [[ $mode == gui ]]; then
    setsid qemu-system-x86_64 "${qemu_args[@]}" >"$CACHE/qemu.log" 2>&1 &
  else
    setsid qemu-system-x86_64 "${qemu_args[@]}" >"$CACHE/qemu.log" 2>&1 &
  fi

  printf '  waiting for ssh'
  for _ in $(seq 1 120); do
    if ssh_vm true 2>/dev/null; then
      echo
      ok "VM is up"
      break
    fi
    printf '.'
    sleep 2
  done
  ssh_vm true 2>/dev/null || {
    echo
    die "VM did not come up. See $CACHE/qemu.log"
  }
else
  ok "VM already running"
fi

# ---------------------------------------------------------------- install

if [[ $mode == install || $mode == gui ]]; then
  echo
  echo "${bold}Syncing the repo into the VM${reset}"
  rsync -a --delete --exclude '.git' \
    -e "ssh -i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR" \
    "$ROOT/" "$VM_USER@localhost:~/pfx/"
  ok "repo synced"

  if [[ $mode == install ]]; then
    echo
    echo "${bold}Running install.sh (this is the real thing — packages and all)${reset}"
    ssh_vm "cd ~/pfx && ./install.sh" || die "install.sh failed inside the VM"
    echo
    ok "pfx installed in the VM"
  fi

  # Only meaningful once pfx is present; harmless before, thanks to the guard
  # inside the profile itself.
  if ssh_vm "command -v Hyprland" >/dev/null 2>&1; then
    enable_desktop_autostart
    ok "desktop will start automatically on the VM console"
  else
    warn "Hyprland not installed yet — run with --install first"
  fi
fi

# ---------------------------------------------------------------- next steps

cat <<NEXT

${green}${bold}Ready${reset}

  ${bold}Shell in${reset}       ./tools/test-vm.sh --ssh
  ${bold}Run the probes${reset}  ./tools/test-vm.sh --ssh   then:  cd pfx && ./tools/verify.sh
  ${bold}See the desktop${reset} ./tools/test-vm.sh --gui   then in the VM window:
                     ${dim}uwsm start hyprland-uwsm.desktop${reset}
  ${bold}Stop${reset}           ./tools/test-vm.sh --stop
  ${bold}Start over${reset}     ./tools/test-vm.sh --fresh

  ${dim}The console password is 'pfx'. The disk is an overlay — --fresh discards
  it and the next boot is a pristine Arch system.${reset}

  ${yellow}The launcher is the thing to check.${reset} ${dim}Press SUPER+SPACE. If it lists your
  applications, elephant is wired correctly; an empty list means the provider
  packages did not land.${reset}

NEXT
