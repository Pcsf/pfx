# A throwaway Arch box for testing pfx.
#
# This verifies everything that does not need a screen: package resolution and
# real installation, the AUR bootstrap, config deployment, idempotency, the
# theme engine, web apps, and Hyprland config parsing.
#
# It cannot start a compositor — Hyprland needs DRM and a seat, which a
# container does not have. For that, see tools/test-nested.sh (fast, uses your
# existing session) or a VM (slow, tests the real boot path).
#
#   docker build -t pfx-test .
#   docker run --rm pfx-test
#
# or just: ./tools/test-container.sh

FROM archlinux:base-devel

# install.sh refuses to run as root, and makepkg refuses outright, so the test
# runs as an unprivileged user with passwordless sudo — the same shape as a
# real Arch install right after `useradd -G wheel`.
RUN useradd -m -G wheel tester \
 && echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel \
 && pacman -Sy --noconfirm --needed git \
 && pacman -Scc --noconfirm

# The official image omits this, and preflight checks for it.
RUN touch /etc/arch-release

USER tester
WORKDIR /home/tester

COPY --chown=tester:tester . /home/tester/pfx

# Baked into the image so `docker run` re-tests instantly instead of
# reinstalling. Docker caches this layer until the repo actually changes.
RUN cd ~/pfx && ./install.sh > /tmp/install.log 2>&1 \
 || (echo "INSTALL FAILED"; tail -40 /tmp/install.log; exit 1)

# Hyprland's config parser needs this; a container has no login session to
# provide one.
ENV XDG_RUNTIME_DIR=/tmp/xdg-runtime
RUN mkdir -p /tmp/xdg-runtime && chmod 700 /tmp/xdg-runtime

ENV PATH="/home/tester/.local/share/pfx/bin:${PATH}"

CMD ["bash", "-lc", "cd ~/pfx && ./tools/verify.sh"]
