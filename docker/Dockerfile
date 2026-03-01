# syntax=docker/dockerfile:1.7
#
# 基于 manylinux_2_28 (AlmaLinux 8, glibc 2.28) 构建。
# 产出的所有 .so 只依赖 glibc 2.28+，可在绝大多数 Linux 发行版上运行。
#
# GCC 14 via gcc-toolset-14: 修复了 GCC bug 114098
#   (_tile_loadconfig 只声明 8 字节内存访问导致 AMX SIGSEGV)
#
FROM quay.io/pypa/manylinux_2_28_x86_64

# ── GCC 14 (AMX _tile_loadconfig fix) ────────────────────────────
RUN dnf install -y gcc-toolset-14-gcc gcc-toolset-14-gcc-c++ \
    && dnf clean all
# 写入 profile.d 使 bash -l 自动启用
RUN echo 'source /opt/rh/gcc-toolset-14/enable' > /etc/profile.d/gcc-toolset-14.sh

# ── 构建依赖 ─────────────────────────────────────────────────────
RUN dnf install -y \
      hwloc-devel numactl-devel \
      squashfs-tools \
    && dnf clean all

# manylinux 镜像自带 cmake, git, curl, patchelf, python 3.8-3.13

# ── Python 构建工具 ──────────────────────────────────────────────
# 使用 manylinux 自带的 Python 3.12
ENV PATH="/opt/python/cp312-cp312/bin:${PATH}"

ARG UV_VERSION=0.8.22
ARG PYTHON_APPIMAGE_VERSION=1.4.5

RUN pip install --no-cache-dir \
      "uv==${UV_VERSION}" \
      "python-appimage==${PYTHON_APPIMAGE_VERSION}" \
      build setuptools wheel setuptools-scm auditwheel

WORKDIR /work
