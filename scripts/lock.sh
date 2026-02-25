#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/render_requirements.sh

mkdir -p dist .cache/uv

# Lock dependencies for linux + pinned python version, with hashes
PYTHON_SHORT="$(grep '^PYTHON_SHORT=' recipe/versions.env | cut -d= -f2)"
echo "[INFO] Locking for python=${PYTHON_SHORT}, platform=linux"

docker build -t sglang-appimage-builder -f docker/Dockerfile docker

docker run --rm -t \
  -v "$PWD:/work" \
  -v "$PWD/.cache/uv:/root/.cache/uv" \
  -w /work \
  sglang-appimage-builder \
  bash -lc "
    set -euo pipefail
    export TZ=UTC LC_ALL=C LANG=C
    uv pip compile recipe/requirements.in \
      --output-file recipe/requirements.lock \
      --generate-hashes \
      --python-version=${PYTHON_SHORT} \
      --python-platform=linux \
      --index-strategy=unsafe-best-match
  "

echo "[OK] Wrote recipe/requirements.lock"
