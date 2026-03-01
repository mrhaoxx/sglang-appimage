# syntax=docker/dockerfile:1.7

ARG DEBIAN_BASE=debian:trixie-slim
FROM ${DEBIAN_BASE}

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git xz-utils file \
      python3 python3-dev python3-venv python3-pip \
      squashfs-tools zstd \
      findutils coreutils \
      cmake make g++ pkg-config libhwloc-dev libnuma-dev \
    && rm -rf /var/lib/apt/lists/*

# Pin build tooling versions
ARG UV_VERSION=0.8.22
ARG PYTHON_APPIMAGE_VERSION=1.4.5

# Install patchelf 0.18+ (needed for --page-size to fix ELF alignment in AppImage)
ARG PATCHELF_VERSION=0.18.0
RUN curl -fSL "https://github.com/NixOS/patchelf/releases/download/${PATCHELF_VERSION}/patchelf-${PATCHELF_VERSION}-x86_64.tar.gz" \
      | tar -xz -C /usr/local && \
    patchelf --version

RUN python3 -m pip install --no-cache-dir --break-system-packages --upgrade pip \
 && python3 -m pip install --no-cache-dir --break-system-packages \
      "uv==${UV_VERSION}" \
      "python-appimage==${PYTHON_APPIMAGE_VERSION}" \
      build setuptools wheel setuptools-scm

WORKDIR /work
