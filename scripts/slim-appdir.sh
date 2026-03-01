#!/usr/bin/env bash
# slim-appdir.sh — 在 manylinux_2_28 容器内运行（需 bash -l 激活 gcc-toolset-14）
#
# manylinux_2_28 方案的核心：
#   gcc-toolset-14 编译在 AlmaLinux 8 (glibc 2.28) 上，
#   它的 libstdc++ 提供 GLIBCXX_3.4.33 但只依赖 glibc 2.28。
#   新编译器 + 旧 glibc = 可移植的产物。
set -euo pipefail

APPDIR="${1:?用法: slim-appdir.sh <AppDir路径>}"
[ -d "${APPDIR}" ] || { echo "[ERR] AppDir 不存在: ${APPDIR}" >&2; exit 1; }

echo "[slim] 开始瘦身 AppDir: ${APPDIR}"
BEFORE=$(du -sm "${APPDIR}" | cut -f1)
APPDIR_LIB="${APPDIR}/usr/lib"
mkdir -p "${APPDIR_LIB}"

# ── helper: 复制库到 AppDir，自动 readlink + soname 符号链接 ──
bundle_lib() {
  local src="$1" link_name="${2:-}"
  if [ ! -e "${src}" ]; then
    echo "    [WARN] 未找到: ${src}"
    return 1
  fi
  local real; real=$(readlink -f "${src}")
  cp -f "${real}" "${APPDIR_LIB}/"
  local base; base=$(basename "${real}")
  if [ -n "${link_name}" ] && [ "${base}" != "${link_name}" ]; then
    ln -sf "${base}" "${APPDIR_LIB}/${link_name}"
  fi
  echo "    ${link_name:-${base}}"
}

# ── 1) 删除 __pycache__（运行时会自动重建）──
echo "  [slim] 删除 __pycache__ ..."
find "${APPDIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# ── 2) 打包 gcc-toolset-14 运行时库（glibc 2.28 兼容）──
# 这些 .so 由 Red Hat 在 glibc 2.28 环境下编译，保证可移植性。
echo "  [slim] 打包 gcc-toolset-14 运行时库 ..."
GCC14="/opt/rh/gcc-toolset-14/root/usr/lib64"
bundle_lib "${GCC14}/libstdc++.so.6" "libstdc++.so.6"
bundle_lib "${GCC14}/libgomp.so.1"   "libgomp.so.1"

# ── 3) 打包系统运行时库（hwloc / numa, 同样 glibc 2.28）──
echo "  [slim] 打包系统运行时库 ..."
bundle_lib "/usr/lib64/libhwloc.so.15" "libhwloc.so.15" || \
  bundle_lib "/usr/lib64/libhwloc.so.5" "libhwloc.so.5" || true
bundle_lib "/usr/lib64/libnuma.so.1" "libnuma.so.1" || true

# ── 4) 删除 nvidia pip 包中的 libcuda.so 存根 ──
# libcuda.so.1 是 NVIDIA 内核驱动的用户态接口，必须由宿主机提供。
# pip 的 nvidia-cuda-* 包自带的是无法使用的存根，会遮蔽宿主机的真实驱动。
echo "  [slim] 删除 nvidia pip 包中的 libcuda 存根 ..."
find "${APPDIR}" -path "*/nvidia/*/lib/libcuda.so*" -delete 2>/dev/null || true

AFTER=$(du -sm "${APPDIR}" | cut -f1)
SAVED=$((BEFORE - AFTER))
echo "[slim] 完成: ${BEFORE}MB → ${AFTER}MB (节省 ${SAVED}MB)"
