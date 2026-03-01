#!/usr/bin/env bash
# 全流程一键构建：克隆源码 → 构建 wheel → 打包 AppImage
set -euo pipefail
cd "$(dirname "$0")"

# ── 自动检测是否需要 sudo ──────────────────────────────
DOCKER=docker
if ! docker info >/dev/null 2>&1; then
  echo "[INFO] 当前用户无 docker 权限，自动使用 sudo"
  DOCKER="sudo docker"
fi

# ── 读取版本配置（环境变量优先，versions.env 作为默认值）──
while IFS='=' read -r key val; do
  [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
  val="${val%\"}" ; val="${val#\"}"
  # 仅在环境变量未设置时使用 versions.env 的值
  if [ -z "${!key+x}" ]; then
    export "$key=$val"
  fi
done < recipe/versions.env

IMAGE=sglang-appimage-builder

echo "============================================"
echo " SGLang + KTransformers AppImage 全流程构建"
echo " Python ${PYTHON_SHORT}"
echo " SGLang  ${SGLANG_REPO}@${SGLANG_REF}"
echo " KTrans  ${KTRANSFORMERS_REPO}@${KTRANSFORMERS_REF}"
echo "============================================"

# ── 1) 构建 Docker 镜像 ──────────────────────────────
echo ""
echo "[1/8] 构建 Docker 构建镜像 ..."
$DOCKER build -t "$IMAGE" \
  --build-arg http_proxy="${PROXY}" \
  --build-arg https_proxy="${PROXY}" \
  --build-arg no_proxy="${NO_PROXY}" \
  -f docker/Dockerfile docker
echo "[OK]  镜像 ${IMAGE}"

# ── 2) 克隆 sglang 源码 ─────────────────────────────
echo ""
echo "[2/8] 克隆 sglang 源码 (${SGLANG_REF}) ..."
SGLANG_SRC=".cache/sglang-src"
if [ -d "${SGLANG_SRC}/.git" ]; then
  echo "[INFO] 已有克隆，拉取最新 ..."
  git -C "${SGLANG_SRC}" fetch origin
  git -C "${SGLANG_SRC}" checkout "${SGLANG_REF}"
  git -C "${SGLANG_SRC}" pull --ff-only origin "${SGLANG_REF}" 2>/dev/null || true
else
  rm -rf "${SGLANG_SRC}"
  git clone --depth 1 -b "${SGLANG_REF}" "${SGLANG_REPO}" "${SGLANG_SRC}"
fi
SGLANG_COMMIT="$(git -C "${SGLANG_SRC}" rev-parse --short HEAD)"
echo "[OK]  sglang@${SGLANG_COMMIT}"

# ── 3) 克隆 ktransformers 源码 ──────────────────────
echo ""
echo "[3/8] 克隆 ktransformers 源码 (${KTRANSFORMERS_REF}) ..."
KT_SRC=".cache/ktransformers-src"
if [ -d "${KT_SRC}/.git" ]; then
  echo "[INFO] 已有克隆，拉取最新 ..."
  git -C "${KT_SRC}" fetch origin
  git -C "${KT_SRC}" checkout "${KTRANSFORMERS_REF}"
  git -C "${KT_SRC}" pull --ff-only origin "${KTRANSFORMERS_REF}" 2>/dev/null || true
else
  rm -rf "${KT_SRC}"
  git clone --depth 1 -b "${KTRANSFORMERS_REF}" "${KTRANSFORMERS_REPO}" "${KT_SRC}"
fi
git -C "${KT_SRC}" submodule update --init --recursive --depth 1
KT_COMMIT="$(git -C "${KT_SRC}" rev-parse --short HEAD)"
echo "[OK]  ktransformers@${KT_COMMIT}"

# ── 4) 构建 sglang + kt-kernel wheels ───────────────
echo ""
echo "[4/8] 构建 sglang + kt-kernel wheels ..."
mkdir -p dist .cache/uv .cache/pip-cache .cache/python-appimage .cache/wheels .cache/cuda-toolkit

$DOCKER run --rm -t \
  -v "$PWD:/work" \
  -w /work \
  -e "https_proxy=${PROXY}" \
  -e "no_proxy=${NO_PROXY}" \
  -e "CUDA_RUNFILE_URL=${CUDA_RUNFILE_URL:-https://developer.download.nvidia.com/compute/cuda/12.9.1/local_installers/cuda_12.9.1_575.57.08_linux.run}" \
  -e "CUDA_RUNFILE_INDEX_URL=${CUDA_RUNFILE_INDEX_URL:-https://developer.download.nvidia.com/compute/cuda/12.9.1/local_installers/}" \
  -e "CUDA_RUNFILE_NAME_REGEX=${CUDA_RUNFILE_NAME_REGEX:-^cuda_12\\.9\\.[0-9]+_[0-9.]+_linux\\.run$}" \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    export PIP_INDEX_URL=${PYPI_INDEX}
    export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn
    export PIP_CACHE_DIR=/work/.cache/pip-cache
    mkdir -p \"\${PIP_CACHE_DIR}\" /work/.cache/cuda-toolkit/python

    # 清理旧产物，避免挑到历史 wheel
    rm -f /work/.cache/wheels/sglang-*.whl /work/.cache/wheels/kt_kernel-*.whl /work/.cache/wheels/kt-kernel*.whl 2>/dev/null || true
    rm -f /work/recipe/sglang-*.whl /work/recipe/kt_kernel-*.whl /work/recipe/kt-kernel*.whl 2>/dev/null || true

    # ── CUDA toolkit cache（从 NVIDIA .run 大包安装，挂载到 /work/.cache） ──
    CUDA_CACHE_ROOT=/work/.cache/cuda-toolkit
    CUDA_RUNFILE_DIR=\${CUDA_CACHE_ROOT}/runfile
    CUDA_TOOLKIT_ROOT=\${CUDA_CACHE_ROOT}/toolkit-root
    CUDA_STAMP=/work/.cache/cuda-toolkit/.installed_pkgs
    CUDA_FULL_SPEC=\"runfile_url=\${CUDA_RUNFILE_URL} index=\${CUDA_RUNFILE_INDEX_URL} regex=\${CUDA_RUNFILE_NAME_REGEX}\"
    mkdir -p \"\${CUDA_RUNFILE_DIR}\"

    if [ ! -f \"\${CUDA_STAMP}\" ] || [ \"\$(cat \"\${CUDA_STAMP}\")\" != \"\${CUDA_FULL_SPEC}\" ] || [ ! -x \"\${CUDA_TOOLKIT_ROOT}/bin/nvcc\" ]; then
      echo '  [cuda] 下载并安装 NVIDIA CUDA .run 大包到 .cache/cuda-toolkit ...'

      RUNFILE_URL=\"\${CUDA_RUNFILE_URL}\"
      if [ -z \"\${RUNFILE_URL}\" ]; then
        echo \"  [cuda] 未显式给出 CUDA_RUNFILE_URL，尝试从索引页自动选择: \${CUDA_RUNFILE_INDEX_URL}\"
        RUNFILE_NAME=\$(curl -fsSL \"\${CUDA_RUNFILE_INDEX_URL}\" | tr '\"' '\n' | grep -E \"\${CUDA_RUNFILE_NAME_REGEX}\" | sort -V | tail -1 || true)
        if [ -z \"\${RUNFILE_NAME}\" ]; then
          echo \"[ERR] 无法从索引页解析到 .run 文件，请设置 CUDA_RUNFILE_URL。\" >&2
          exit 1
        fi
        RUNFILE_URL=\"\${CUDA_RUNFILE_INDEX_URL}\${RUNFILE_NAME}\"
      fi

      RUNFILE_PATH=\"\${CUDA_RUNFILE_DIR}/\$(basename \"\${RUNFILE_URL}\")\"
      if [ ! -f \"\${RUNFILE_PATH}\" ]; then
        echo \"  [cuda] 下载: \${RUNFILE_URL}\"
        curl -fSL \"\${RUNFILE_URL}\" -o \"\${RUNFILE_PATH}\"
      else
        echo \"  [cuda] 复用缓存: \${RUNFILE_PATH}\"
      fi
      chmod +x \"\${RUNFILE_PATH}\"

      rm -rf \"\${CUDA_TOOLKIT_ROOT}\" \"\${CUDA_CACHE_ROOT}/defaultroot\"
      mkdir -p \"\${CUDA_TOOLKIT_ROOT}\" \"\${CUDA_CACHE_ROOT}/defaultroot\"
      sh \"\${RUNFILE_PATH}\" --silent --toolkit \
        --toolkitpath=\"\${CUDA_TOOLKIT_ROOT}\" \
        --defaultroot=\"\${CUDA_CACHE_ROOT}/defaultroot\" \
        --override

      printf '%s' \"\${CUDA_FULL_SPEC}\" > \"\${CUDA_STAMP}\"
    else
      echo '  [cuda] 复用缓存的 NVIDIA CUDA toolkit (.cache/cuda-toolkit)'
    fi

    CUDA_NVCC_BIN=\"\${CUDA_TOOLKIT_ROOT}/bin/nvcc\"
    if [ ! -x \"\${CUDA_NVCC_BIN}\" ]; then
      echo '[ERR] CUDA .run 安装后未找到 nvcc。' >&2
      find \"\${CUDA_TOOLKIT_ROOT}\" -maxdepth 4 -type d | sed -n '1,200p' >&2 || true
      exit 1
    fi
    chmod +x \"\${CUDA_NVCC_BIN}\" 2>/dev/null || true

    CUDART_REAL=\$(find -L \"\${CUDA_TOOLKIT_ROOT}/lib64\" -maxdepth 1 -type f -name 'libcudart.so*' | sort -V | tail -1 || true)
    if [ -z \"\${CUDART_REAL}\" ]; then
      echo '[ERR] CUDA .run 安装后未找到 libcudart.so*。' >&2
      find -L \"\${CUDA_TOOLKIT_ROOT}/lib64\" -maxdepth 1 -name 'libcudart*' >&2 || true
      exit 1
    fi

    ln -sf \"\$(basename \"\${CUDART_REAL}\")\" \"\${CUDA_TOOLKIT_ROOT}/lib64/libcudart.so\"

    export CUDA_HOME=\${CUDA_TOOLKIT_ROOT}
    export CUDAToolkit_ROOT=\${CUDA_TOOLKIT_ROOT}
    export PATH=\"\${CUDA_TOOLKIT_ROOT}/bin:\${PATH}\"
    export LD_LIBRARY_PATH=\"\${CUDA_TOOLKIT_ROOT}/lib64:\${CUDA_TOOLKIT_ROOT}/nvvm/lib64:\${LD_LIBRARY_PATH:-}\"
    export CMAKE_ARGS=\"-DCMAKE_CUDA_COMPILER=\${CUDA_TOOLKIT_ROOT}/bin/nvcc -DCUDAToolkit_ROOT=\${CUDAToolkit_ROOT} -DCUDA_TOOLKIT_ROOT_DIR=\${CUDAToolkit_ROOT} \${CMAKE_ARGS:-}\"

    if ! command -v nvcc >/dev/null 2>&1; then
      echo '[ERR] 未找到 nvcc，无法构建带 CUDA stream API 的 kt-kernel' >&2
      exit 1
    fi
    nvcc --version | tail -n 1 || true

    # ── sglang wheel ──
    rm -rf /work/.cache/sglang-src/python/build/
    echo '  [build] sglang: pip wheel --no-deps ...'
    pip wheel --no-deps -w /work/.cache/wheels /work/.cache/sglang-src/python/ 2>&1 | tail -5

    SGLANG_WHL=\$(
      find /work/.cache/wheels -maxdepth 1 -type f -name 'sglang-*.whl' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -1 | cut -d' ' -f2- || true
    )
    if [ -z \"\${SGLANG_WHL}\" ]; then
      echo '[ERR] 未找到 sglang wheel（/work/.cache/wheels/sglang-*.whl）。' >&2
      find /work/.cache/wheels -maxdepth 2 -type f | sed -n '1,120p' >&2 || true
      exit 1
    fi
    SGLANG_WHL_NAME=\$(basename \"\${SGLANG_WHL}\")
    cp -f \"\${SGLANG_WHL}\" /work/recipe/
    echo \"  [build] sglang wheel: \${SGLANG_WHL_NAME}\"

    # ── kt-kernel wheel (multi-variant: AVX2/AVX512/AMX) ──
    rm -rf /work/.cache/ktransformers-src/kt-kernel/build /work/.cache/ktransformers-src/kt-kernel/kt_kernel.egg-info
    echo '  [build] kt-kernel: pip wheel --no-deps (all CPU variants + CUDA stream API) ...'
    CPUINFER_BUILD_ALL_VARIANTS=1 CPUINFER_USE_CUDA=1 CPUINFER_CUDA_STATIC_RUNTIME=0 \
      pip wheel -v --no-deps -w /work/.cache/wheels /work/.cache/ktransformers-src/kt-kernel/

    KT_WHL=\$(
      find /work/.cache/wheels /work/.cache/pip-cache/wheels -type f \( -name 'kt_kernel-*.whl' -o -name 'kt-kernel*.whl' \) -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -1 | cut -d' ' -f2- || true
    )
    if [ -z \"\${KT_WHL}\" ]; then
      echo '[ERR] 未找到 kt-kernel wheel（已检查 .cache/wheels 和 .cache/pip-cache/wheels）。' >&2
      find /work/.cache/wheels -maxdepth 3 -type f | sed -n '1,120p' >&2 || true
      find /work/.cache/pip-cache/wheels -maxdepth 5 -type f | sed -n '1,120p' >&2 || true
      exit 1
    fi

    # ── auditwheel repair: 把 libhwloc/libnuma/libgomp 等打入 wheel ──
    echo '  [build] auditwheel repair kt-kernel wheel ...'
    auditwheel show \"\${KT_WHL}\" || true
    rm -rf /work/.cache/wheels-repaired
    mkdir -p /work/.cache/wheels-repaired
    auditwheel repair \"\${KT_WHL}\" \
      --plat manylinux_2_28_x86_64 \
      -w /work/.cache/wheels-repaired/

    KT_WHL=\$(find /work/.cache/wheels-repaired -type f \( -name 'kt_kernel-*.whl' -o -name 'kt-kernel*.whl' \) | head -1)
    KT_WHL_NAME=\$(basename \"\${KT_WHL}\")

    cp -f \"\${KT_WHL}\" /work/recipe/
    echo \"  [build] kt-kernel wheel (repaired): \${KT_WHL_NAME}\"

    # ── requirements.txt ──
    echo \"/work/recipe/\${SGLANG_WHL_NAME}\" > /work/recipe/requirements.txt
    echo \"/work/recipe/\${KT_WHL_NAME}\" >> /work/recipe/requirements.txt
    echo '  [build] requirements.txt:'
    cat /work/recipe/requirements.txt
  "
echo "[OK]  wheels + requirements.txt"

# ── 5) 预下载 appimagetool + runtime ─────────────────
echo ""
echo "[5/8] 准备 appimagetool + runtime ..."
mkdir -p .cache/appimagetool-bin

RUNTIME=".cache/runtime-x86_64"
AIT=".cache/appimagetool-bin/appimagetool.real"

[ -f "${RUNTIME}" ] && echo "  runtime: 已缓存" || {
  echo "  runtime: 下载中 ..."
  curl -fSL -o "${RUNTIME}" \
    https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64
}
[ -f "${AIT}" ] && echo "  appimagetool: 已缓存" || {
  echo "  appimagetool: 下载中 ..."
  curl -fSL -o "${AIT}" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "${AIT}"
}
echo "[OK]  appimagetool + runtime"

# ── 6) 构建 AppDir ──────────────────────────────────────
echo ""
echo "[6/8] 构建 AppDir ..."

# 确保 pip 缓存目录存在
mkdir -p .cache/pip-cache

$DOCKER run --rm -t \
  -v "$PWD:/work" \
  -v "$PWD/.cache/python-appimage:/root/.cache/python-appimage" \
  -w /work \
  "$IMAGE" \
  bash -lxc '
    set -uo pipefail
    export TZ=UTC LC_ALL=C LANG=C
    export PIP_INDEX_URL='"${PYPI_INDEX}"'
    export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn
    export PIP_CACHE_DIR=/work/.cache/pip-cache
    export https_proxy='"${PROXY}"'
    export no_proxy='"${NO_PROXY}"'
    mkdir -p ${PIP_CACHE_DIR}
    chown -R "$(id -u):$(id -g)" ${PIP_CACHE_DIR}
    unset SOURCE_DATE_EPOCH 2>/dev/null || true

    # 固定 TMPDIR 便于后续找到 AppDir
    export TMPDIR=/work/.cache/appdir-tmp
    rm -rf ${TMPDIR}
    mkdir -p ${TMPDIR}

    echo "  [step6] 运行 python-appimage build app ..."
    echo "  [step6] TMPDIR=${TMPDIR}"
    echo "  [step6] PIP_CACHE_DIR=${PIP_CACHE_DIR}"
    echo "  [step6] PIP_INDEX_URL=${PIP_INDEX_URL}"

    # 运行 python-appimage（仅构建 AppDir，不需要它成功打包最终 AppImage）
    set +e
    python-appimage build app \
      -p '"${PYTHON_SHORT}"' \
      -n SGLang \
      recipe
    RC=$?
    set -e

    echo "  [step6] python-appimage 退出码: ${RC}"

    # 查找 AppDir（python-appimage 成功时也可能在 TMPDIR 留有 AppDir）
    APPDIR=""
    # python-appimage 成功时会生成 .AppImage 文件，但我们需要 AppDir
    # 先尝试从 TMPDIR 查找
    APPDIR=$(find ${TMPDIR} -maxdepth 3 -name AppDir -type d | head -1)

    # 如果 python-appimage 成功且 TMPDIR 无 AppDir，需要解包
    if [ ${RC} -eq 0 ] && [ -z "${APPDIR}" ]; then
      echo "  [step6] python-appimage 成功，解包 AppImage 以获取 AppDir ..."
      AIF=$(ls -t SGLang*.AppImage 2>/dev/null | head -1)
      if [ -n "${AIF}" ]; then
        chmod +x "${AIF}"
        APPDIR="${TMPDIR}/AppDir"
        ./"${AIF}" --appimage-extract 2>/dev/null
        mv squashfs-root "${APPDIR}"
        rm -f "${AIF}"
      fi
    fi

    if [ -z "${APPDIR}" ] || [ ! -d "${APPDIR}" ]; then
      echo "[ERR] AppDir 未找到" >&2
      find ${TMPDIR} -type f 2>/dev/null | head -20 || true
      exit 1
    fi

    # 保存 AppDir 路径供后续步骤使用
    echo "${APPDIR}" > /work/.cache/appdir-path.txt
    echo "  [step6] AppDir: ${APPDIR}"
    echo "  [step6] AppDir 大小: $(du -sh ${APPDIR} | cut -f1)"
  '

# ── 7) 瘦身 AppDir ──────────────────────────────────────
echo ""
echo "[7/8] 瘦身 AppDir ..."

APPDIR_PATH=$(cat .cache/appdir-path.txt)

$DOCKER run --rm -t \
  -v "$PWD:/work" \
  -w /work \
  "$IMAGE" \
  bash -lc "
    bash /work/scripts/slim-appdir.sh '${APPDIR_PATH}'
  "

# ── 8) 打包 AppImage（mksquashfs zstd + runtime）────────
echo ""
echo "[8/8] 打包 AppImage (zstd -19) ..."

$DOCKER run --rm -t \
  -v "$PWD:/work" \
  -w /work \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    APPDIR=$(cat /work/.cache/appdir-path.txt)

    echo "  [step8] mksquashfs ${APPDIR} → squashfs.img (zstd -19) ..."
    rm -f /work/.cache/squashfs.img
    mksquashfs "${APPDIR}" /work/.cache/squashfs.img \
      -root-owned -noappend \
      -comp zstd -Xcompression-level 19

    echo "  [step8] 拼接 runtime + squashfs → AppImage ..."
    cat /work/.cache/runtime-x86_64 /work/.cache/squashfs.img > /work/dist/SGLang.AppImage
    chmod +x /work/dist/SGLang.AppImage
    rm -f /work/.cache/squashfs.img

    echo "  [step8] 完成"
  '

echo ""
echo "============================================"
echo " 构建完成！"
echo " 输出: dist/SGLang.AppImage"
SIZE="$(du -sh dist/SGLang.AppImage | cut -f1)"
echo " 大小: ${SIZE}"
echo " 版本: sglang@${SGLANG_COMMIT} + kt@${KT_COMMIT}"
echo "============================================"
