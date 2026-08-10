#!/bin/bash
#
# Install pfx into a clean Arch container and run every probe against it.
#
# This is the fast loop. It catches packaging, path, permission, idempotency
# and config-syntax regressions in about ninety seconds once the image layer
# is cached. It cannot catch anything visual — see tools/test-nested.sh.
#
# Usage:
#   ./tools/test-container.sh            # build (cached) and run the probes
#   ./tools/test-container.sh --rebuild  # ignore the cache, install from scratch
#   ./tools/test-container.sh --shell     # drop into the installed container

set -eEuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="pfx-test"

command -v docker >/dev/null 2>&1 || {
  echo "docker is not installed." >&2
  exit 1
}
docker info >/dev/null 2>&1 || {
  echo "The docker daemon is not reachable. Try: sudo systemctl start docker" >&2
  exit 1
}

build_args=()
mode="verify"

for arg in "$@"; do
  case "$arg" in
  --rebuild) build_args+=(--no-cache) ;;
  --shell) mode="shell" ;;
  --help | -h)
    sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown option: $arg" >&2
    exit 1
    ;;
  esac
done

echo "Building $IMAGE (a full install runs inside; first build takes a few minutes)…"
docker build "${build_args[@]}" -t "$IMAGE" "$ROOT"

echo
if [[ $mode == shell ]]; then
  exec docker run --rm -it "$IMAGE" bash -l
fi

docker run --rm "$IMAGE"
