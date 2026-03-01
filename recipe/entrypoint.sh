#!/bin/sh
set -xeu

APPDIR="${APPDIR:-$(dirname "$(readlink -f "$0")")}"
PY_HOME="${APPDIR}/usr"

# ── 1) Host libstdc++ (JIT 编译的 kernel 需要宿主机/conda 的新版) ──
# AppImage 内置的 manylinux libstdc++ 太旧，缺少 GLIBCXX_3.4.32 等符号。
# 必须让宿主机的新版 libstdc++ 优先加载。
HOST_LIBS=""
# conda 环境优先
if [ -n "${CONDA_PREFIX:-}" ] && [ -f "${CONDA_PREFIX}/lib/libstdc++.so.6" ]; then
  HOST_LIBS="${CONDA_PREFIX}/lib"
fi
# 系统路径兜底
for d in /usr/lib/x86_64-linux-gnu /usr/lib64 /lib/x86_64-linux-gnu; do
  if [ -f "${d}/libstdc++.so.6" ]; then
    HOST_LIBS="${HOST_LIBS:+${HOST_LIBS}:}${d}"
    break
  fi
done

# ── 2) AppImage bundled system libs (libssl, libcrypto, etc.) ──────
APPIMAGE_LIBS="${APPDIR}/usr/lib"

# ── 3) CUDA libs shipped by wheels (torch / nvidia-*) ──────────────
TORCH_LIB="${PY_HOME}/lib/python{{ python-version }}/site-packages/torch/lib"
NVIDIA_LIB_ROOT="${PY_HOME}/lib/python{{ python-version }}/site-packages/nvidia"

NVIDIA_LIBS=""
if [ -d "${NVIDIA_LIB_ROOT}" ]; then
  for d in $(find "${NVIDIA_LIB_ROOT}" -maxdepth 3 -type d -name lib 2>/dev/null); do
    NVIDIA_LIBS="${NVIDIA_LIBS}:${d}"
  done
fi

# ── 4) 组装 LD_LIBRARY_PATH ──────────────────────────────────────
# 顺序：宿主机 libstdc++ → AppImage bundled libs → torch/nvidia CUDA libs → 原有
export LD_LIBRARY_PATH="${APPIMAGE_LIBS}:${HOST_LIBS:+${HOST_LIBS}:}${TORCH_LIB}${NVIDIA_LIBS}:${LD_LIBRARY_PATH:-}"

# Avoid writing bytecode into the mounted AppImage
export PYTHONDONTWRITEBYTECODE=1

# ── 5) JIT 编译环境 (Triton / torch inductor) ────────────────────
# Triton JIT: 编译 Python DSL → IR → PTX → cubin，需要可写缓存目录
# torch inductor: torch.compile() 的代码生成后端
SGLANG_CACHE="${XDG_CACHE_HOME:-${HOME}/.cache}/sglang"

export TRITON_CACHE_DIR="${TRITON_CACHE_DIR:-${SGLANG_CACHE}/triton}"
export TRITON_HOME="${TRITON_HOME:-${SGLANG_CACHE}/triton_home}"
export TORCH_EXTENSIONS_DIR="${TORCH_EXTENSIONS_DIR:-${SGLANG_CACHE}/torch_extensions}"
mkdir -p "${TRITON_CACHE_DIR}" "${TORCH_EXTENSIONS_DIR}" 2>/dev/null || true

# Triton 自带 ptxas (PTX → cubin 汇编器)，确保能找到
TRITON_PTXAS="${PY_HOME}/lib/python{{ python-version }}/site-packages/triton/third_party/cuda/bin/ptxas"
if [ -x "${TRITON_PTXAS}" ]; then
  export TRITON_PTXAS_PATH="${TRITON_PTXAS}"
fi

# torch inductor C++ wrapper: 探测宿主机 g++，没有就自动禁用
# C++ wrapper 只优化 CPU 端 kernel launch 调度，对 GPU 推理吞吐影响极小
if [ -z "${TORCHINDUCTOR_CPP_WRAPPER:-}" ]; then
  if command -v g++ >/dev/null 2>&1; then
    export TORCHINDUCTOR_CPP_WRAPPER=1
  else
    export TORCHINDUCTOR_CPP_WRAPPER=0
  fi
fi

# Pass the real Python binary path so multiprocessing spawn works correctly.
export _SGLANG_REAL_PYTHON="{{ python-executable }}"

exec {{ python-executable }} -c '
import sys, os, multiprocessing

# Fix sys.executable for multiprocessing "spawn" mode in AppImage
real_python = os.environ.get("_SGLANG_REAL_PYTHON", sys.executable)
sys.executable = real_python
multiprocessing.set_executable(real_python)

from sglang.srt.server_args import prepare_server_args
from sglang.srt.utils import kill_process_tree
from sglang.srt.utils.common import suppress_noisy_warnings
from sglang.launch_server import run_server

suppress_noisy_warnings()
server_args = prepare_server_args(sys.argv[1:])
try:
    run_server(server_args)
finally:
    kill_process_tree(os.getpid(), include_parent=False)
' "$@"
