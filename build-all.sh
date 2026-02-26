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

# ── 读取版本配置 ───────────────────────────────────────
set -a
source recipe/versions.env
set +a

IMAGE=sglang-appimage-builder

echo "============================================"
echo " SGLang AppImage 全流程构建 (从源码)"
echo " Python ${PYTHON_SHORT}"
echo " Repo   ${SGLANG_REPO}@${SGLANG_REF}"
echo "============================================"

# ── 1) 构建 Docker 镜像 ──────────────────────────────
echo ""
echo "[1/7] 构建 Docker 构建镜像 ..."
$DOCKER build -t "$IMAGE" -f docker/Dockerfile docker
echo "[OK]  镜像 ${IMAGE}"

# ── 2) 克隆 sglang 源码 ─────────────────────────────
echo ""
echo "[2/7] 克隆 sglang 源码 (${SGLANG_REF}) ..."
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

# ── 3) 构建 sglang wheel ────────────────────────────
echo ""
echo "[3/7] 构建 sglang wheel ..."
mkdir -p dist .cache/uv .cache/pip-cache .cache/python-appimage .cache/wheels

$DOCKER run --rm -t \
  -v "$PWD:/work" \
  -w /work \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    export PIP_INDEX_URL=${PYPI_INDEX}
    export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

    # 清理残留的 build 产物，防止 setuptools 将其递归打包进 wheel
    rm -rf /work/.cache/sglang-src/python/build/

    echo '  [build] pip wheel --no-deps ...'
    pip wheel --no-deps -w /work/.cache/wheels /work/.cache/sglang-src/python/ 2>&1 | tail -5

    WHEEL=\$(ls -t /work/.cache/wheels/sglang-*.whl | head -1)
    WHEEL_NAME=\$(basename \"\${WHEEL}\")
    cp -f \"\${WHEEL}\" /work/recipe/
    echo \"  [build] wheel: \${WHEEL_NAME}\"

    echo \"/work/recipe/\${WHEEL_NAME}\" > /work/recipe/requirements.txt
    echo '  [build] requirements.txt:'
    cat /work/recipe/requirements.txt
  "
echo "[OK]  wheel + requirements.txt"

# ── 4) 预下载 appimagetool + runtime ─────────────────
echo ""
echo "[4/7] 准备 appimagetool + runtime ..."
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

# ── 5) 构建 AppImage（两步流程：构建 AppDir → 瘦身 → 打包）───
echo ""
echo "[5/7] 构建 AppDir ..."

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
    export https_proxy=http://192.168.200.14:17890
    export no_proxy=".cn"
    mkdir -p ${PIP_CACHE_DIR}
    chown -R "$(id -u):$(id -g)" ${PIP_CACHE_DIR}
    unset SOURCE_DATE_EPOCH 2>/dev/null || true

    # 固定 TMPDIR 便于后续找到 AppDir
    export TMPDIR=/work/.cache/appdir-tmp
    rm -rf ${TMPDIR}
    mkdir -p ${TMPDIR}

    echo "  [step5] 运行 python-appimage build app ..."
    echo "  [step5] TMPDIR=${TMPDIR}"
    echo "  [step5] PIP_CACHE_DIR=${PIP_CACHE_DIR}"
    echo "  [step5] PIP_INDEX_URL=${PIP_INDEX_URL}"

    # 运行 python-appimage（仅构建 AppDir，不需要它成功打包最终 AppImage）
    set +e
    python-appimage build app \
      -p '"${PYTHON_SHORT}"' \
      -n SGLang \
      recipe
    RC=$?
    set -e

    echo "  [step5] python-appimage 退出码: ${RC}"

    # 查找 AppDir（python-appimage 成功时也可能在 TMPDIR 留有 AppDir）
    APPDIR=""
    # python-appimage 成功时会生成 .AppImage 文件，但我们需要 AppDir
    # 先尝试从 TMPDIR 查找
    APPDIR=$(find ${TMPDIR} -maxdepth 3 -name AppDir -type d | head -1)

    # 如果 python-appimage 成功且 TMPDIR 无 AppDir，需要解包
    if [ ${RC} -eq 0 ] && [ -z "${APPDIR}" ]; then
      echo "  [step5] python-appimage 成功，解包 AppImage 以获取 AppDir ..."
      AIF=$(ls -t SGLang*.AppImage 2>/dev/null | head -1)
      if [ -n "${AIF}" ]; then
        chmod +x "${AIF}"
        APPDIR="${TMPDIR}/AppDir"
        "${AIF}" --appimage-extract 2>/dev/null
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
    echo "  [step5] AppDir: ${APPDIR}"
    echo "  [step5] AppDir 大小: $(du -sh ${APPDIR} | cut -f1)"
  '

# ── 6) 瘦身 AppDir ──────────────────────────────────────
echo ""
echo "[6/7] 瘦身 AppDir ..."

APPDIR_PATH=$(cat .cache/appdir-path.txt)

$DOCKER run --rm -t \
  -v "$PWD:/work" \
  -w /work \
  "$IMAGE" \
  bash -lc "
    bash /work/scripts/slim-appdir.sh '${APPDIR_PATH}'
  "

# ── 7) 打包 AppImage（mksquashfs zstd + runtime）────────
echo ""
echo "[7/7] 打包 AppImage (zstd -19) ..."

$DOCKER run --rm -t \
  -v "$PWD:/work" \
  -w /work \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    APPDIR=$(cat /work/.cache/appdir-path.txt)

    echo "  [step7] mksquashfs ${APPDIR} → squashfs.img (zstd -19) ..."
    rm -f /work/.cache/squashfs.img
    mksquashfs "${APPDIR}" /work/.cache/squashfs.img \
      -root-owned -noappend \
      -comp zstd -Xcompression-level 19

    echo "  [step7] 拼接 runtime + squashfs → AppImage ..."
    cat /work/.cache/runtime-x86_64 /work/.cache/squashfs.img > /work/dist/SGLang.AppImage
    chmod +x /work/dist/SGLang.AppImage
    rm -f /work/.cache/squashfs.img

    echo "  [step7] 完成"
  '

echo ""
echo "============================================"
echo " 构建完成！"
echo " 输出: dist/SGLang.AppImage"
SIZE="$(du -sh dist/SGLang.AppImage | cut -f1)"
echo " 大小: ${SIZE}"
echo " 版本: sglang@${SGLANG_COMMIT}"
echo "============================================"
