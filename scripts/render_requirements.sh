#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

set -a
source recipe/versions.env
set +a

# shellcheck disable=SC2001
envsubst < recipe/requirements.in.tmpl > recipe/requirements.in

echo "[OK] Wrote recipe/requirements.in"
