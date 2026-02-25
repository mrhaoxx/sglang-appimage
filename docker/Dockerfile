# syntax=docker/dockerfile:1.7

ARG DEBIAN_BASE=debian:bookworm-slim
FROM ${DEBIAN_BASE}

ARG DEBIAN_FRONTEND=noninteractive

# (Optional) Freeze apt to a snapshot for stronger reproducibility.
# Pass e.g. --build-arg DEBIAN_SNAPSHOT=20260201T000000Z
ARG DEBIAN_SNAPSHOT=""
RUN if [ -n "${DEBIAN_SNAPSHOT}" ]; then \
      echo "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ bookworm main" > /etc/apt/sources.list; \
      echo "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}/ bookworm-security main" >> /etc/apt/sources.list; \
      echo "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ bookworm-updates main" >> /etc/apt/sources.list; \
    fi

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git xz-utils file \
      python3 python3-venv python3-pip \
      patchelf squashfs-tools zstd \
      findutils coreutils \
    && rm -rf /var/lib/apt/lists/*

# Pin build tooling versions
ARG UV_VERSION=0.8.22
ARG PYTHON_APPIMAGE_VERSION=1.4.5

RUN python3 -m pip install --no-cache-dir --break-system-packages --upgrade pip \
 && python3 -m pip install --no-cache-dir --break-system-packages \
      "uv==${UV_VERSION}" \
      "python-appimage==${PYTHON_APPIMAGE_VERSION}" \
      build setuptools wheel setuptools-scm

WORKDIR /work
