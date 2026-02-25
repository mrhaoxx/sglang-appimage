#!/usr/bin/env bash
# slim-appdir.sh — 在 appimagetool 打包前瘦身 AppDir
# 删除运行时无用文件 + strip debug symbols
set -euo pipefail

APPDIR="${1:?用法: slim-appdir.sh <AppDir路径>}"

if [ ! -d "${APPDIR}" ]; then
  echo "[ERR] AppDir 不存在: ${APPDIR}" >&2
  exit 1
fi

echo "[slim] 开始瘦身 AppDir: ${APPDIR}"
BEFORE=$(du -sm "${APPDIR}" | cut -f1)

# ── 1) 删除 __pycache__ ──────────────────────────────────
echo "  [slim] 删除 __pycache__ ..."
find "${APPDIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# ── 2) 删除 test/tests 目录 ──────────────────────────────
echo "  [slim] 删除 test/tests 目录 ..."
find "${APPDIR}" -type d \( -name "test" -o -name "tests" \) \
  -not -path "*/sglang/*" \
  -exec rm -rf {} + 2>/dev/null || true

# ── 3) 删除 torch/include (C++ headers) ─────────────────
echo "  [slim] 删除 torch/include ..."
find "${APPDIR}" -type d -path "*/torch/include" -exec rm -rf {} + 2>/dev/null || true

# ── 4) 删除 torch/bin ────────────────────────────────────
echo "  [slim] 删除 torch/bin ..."
find "${APPDIR}" -type d -path "*/torch/bin" -exec rm -rf {} + 2>/dev/null || true

# ── 5) 删除 *.dist-info ─────────────────────────────────
echo "  [slim] 删除 *.dist-info ..."
find "${APPDIR}" -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true

# ── 6) 删除无人 NEEDED 的 NVIDIA 库 ─────────────────────
echo "  [slim] 删除 libnvblas.so* ..."
find "${APPDIR}" -name "libnvblas.so*" -delete 2>/dev/null || true

echo "  [slim] 删除 libcusolverMg.so* ..."
find "${APPDIR}" -name "libcusolverMg.so*" -delete 2>/dev/null || true

# ── 7) strip debug symbols ──────────────────────────────
echo "  [slim] strip --strip-unneeded *.so ..."
find "${APPDIR}" \( -name "*.so" -o -name "*.so.*" \) -type f \
  -exec strip --strip-unneeded {} + 2>/dev/null || true

AFTER=$(du -sm "${APPDIR}" | cut -f1)
SAVED=$((BEFORE - AFTER))
echo "[slim] 完成: ${BEFORE}MB → ${AFTER}MB (节省 ${SAVED}MB)"
