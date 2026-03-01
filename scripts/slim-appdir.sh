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

# 用构建环境的 libstdc++ 替换 manylinux 的旧版本
# kt-kernel 用 GCC 13 (Ubuntu 24.04) 编译，需要 GLIBCXX_3.4.32，
# 而 python-appimage 打包的 manylinux libstdc++ 和许多宿主机的都太旧。
BUILD_LIBSTDCXX=$(find /usr/lib -name "libstdc++.so.6.*" -type f 2>/dev/null | sort -V | tail -1)
if [ -n "${BUILD_LIBSTDCXX}" ]; then
  APPDIR_LIB="${APPDIR}/usr/lib"
  echo "  [slim] 替换 libstdc++: $(basename "${BUILD_LIBSTDCXX}")"
  cp -f "${BUILD_LIBSTDCXX}" "${APPDIR_LIB}/"
  ln -sf "$(basename "${BUILD_LIBSTDCXX}")" "${APPDIR_LIB}/libstdc++.so.6"
fi

AFTER=$(du -sm "${APPDIR}" | cut -f1)
SAVED=$((BEFORE - AFTER))
echo "[slim] 完成: ${BEFORE}MB → ${AFTER}MB (节省 ${SAVED}MB)"
