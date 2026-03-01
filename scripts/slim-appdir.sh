#!/usr/bin/env bash
# slim-appdir.sh — 在打包前瘦身 AppDir
#
# kt-kernel 的系统库依赖 (libhwloc/libnuma/libgomp) 已由 auditwheel repair
# 打入 wheel 内部，无需在此手动 copy .so。
set -euo pipefail

APPDIR="${1:?用法: slim-appdir.sh <AppDir路径>}"
[ -d "${APPDIR}" ] || { echo "[ERR] AppDir 不存在: ${APPDIR}" >&2; exit 1; }

echo "[slim] 开始瘦身 AppDir: ${APPDIR}"
BEFORE=$(du -sm "${APPDIR}" | cut -f1)

# 1) 删除 __pycache__（运行时会自动重建）
echo "  [slim] 删除 __pycache__ ..."
find "${APPDIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# 2) 删除 nvidia pip 包中的 libcuda.so 存根
# libcuda.so.1 是 NVIDIA 内核驱动的用户态接口，必须由宿主机提供。
echo "  [slim] 删除 nvidia pip 包中的 libcuda 存根 ..."
find "${APPDIR}" -path "*/nvidia/*/lib/libcuda.so*" -delete 2>/dev/null || true

AFTER=$(du -sm "${APPDIR}" | cut -f1)
SAVED=$((BEFORE - AFTER))
echo "[slim] 完成: ${BEFORE}MB → ${AFTER}MB (节省 ${SAVED}MB)"
