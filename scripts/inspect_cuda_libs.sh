#!/usr/bin/env bash
set -euo pipefail

APPIMAGE="${1:?Usage: inspect_cuda_libs.sh path/to/AppImage}"
TMP="$(mktemp -d)"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

chmod +x "$APPIMAGE"

# Extract without FUSE
"$APPIMAGE" --appimage-extract >/dev/null
mv squashfs-root "$TMP/root"

echo "[INFO] Looking for CUDA-related .so in site-packages (nvidia/*/lib) and torch/lib ..."
find "$TMP/root/usr" -type f -name '*.so*' \
  | grep -E '/site-packages/(nvidia|torch)/' \
  | grep -E 'cuda|cudart|cublas|cufft|curand|cusolver|cusparse|nvrtc|nccl|cudnn' \
  | sort || true
