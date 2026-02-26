#!/usr/bin/env bash
# slim-appdir.sh — 在打包前瘦身 AppDir，仅删除安全无害的缓存文件
set -euo pipefail

APPDIR="${1:?用法: slim-appdir.sh <AppDir路径>}"

if [ ! -d "${APPDIR}" ]; then
  echo "[ERR] AppDir 不存在: ${APPDIR}" >&2
  exit 1
fi

echo "[slim] 开始瘦身 AppDir: ${APPDIR}"
BEFORE=$(du -sm "${APPDIR}" | cut -f1)

# 删除 __pycache__（运行时会自动重建）
echo "  [slim] 删除 __pycache__ ..."
find "${APPDIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

AFTER=$(du -sm "${APPDIR}" | cut -f1)
SAVED=$((BEFORE - AFTER))
echo "[slim] 完成: ${BEFORE}MB → ${AFTER}MB (节省 ${SAVED}MB)"
