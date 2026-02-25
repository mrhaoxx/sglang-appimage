#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f recipe/requirements.lock ]; then
  echo "[ERR] recipe/requirements.lock not found. Run ./scripts/lock.sh first." >&2
  exit 1
fi

# python-appimage parses line by line; strip --hash lines and trailing backslashes
sed -e '/^ *--hash/d' -e 's/ *\\$//' recipe/requirements.lock > recipe/requirements.txt

mkdir -p dist .cache/python-appimage .cache/uv

docker build -t sglang-appimage-builder -f docker/Dockerfile docker

# NOTE:
# - Many build environments export SOURCE_DATE_EPOCH. appimagetool can fail if it is set.
#   We explicitly unset it inside the container.
docker run --rm -t \
  -v "$PWD:/work" \
  -v "$PWD/.cache/python-appimage:/root/.cache/python-appimage" \
  -v "$PWD/.cache/uv:/root/.cache/uv" \
  -w /work \
  sglang-appimage-builder \
  bash -lc "
    set -euo pipefail
    export TZ=UTC LC_ALL=C LANG=C
    unset SOURCE_DATE_EPOCH || true

    # Install deps into the app recipe virtual env via python-appimage.
    # python-appimage will read:
    #   - recipe/requirements.lock
    #   - recipe/entrypoint.sh
    #   - recipe/app.desktop and icon
    #
    # If you want full isolation at runtime, entrypoint uses: {{ python-executable }} -I
    python-appimage build app \
      -p $(grep '^PYTHON_SHORT=' recipe/versions.env | cut -d= -f2) \
      -n SGLang \
      recipe

    # python-appimage outputs an AppImage in the current directory by default; move it
    mv -f SGLang*.AppImage dist/SGLang.AppImage
  "

echo "[OK] dist/SGLang.AppImage"
