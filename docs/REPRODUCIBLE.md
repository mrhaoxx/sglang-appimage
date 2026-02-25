# Design notes

## Why uv + hashes?

`uv pip compile --generate-hashes` can emit hash-locked requirements, and `uv` can be configured to require hashes for installs.
This prevents “same pins, different wheels” drift when a package is yanked/re-uploaded.

## Why unsetting SOURCE_DATE_EPOCH?

`appimagetool` generates the SquashFS using `mksquashfs ... -mkfs-time 0`.
If the environment provides `SOURCE_DATE_EPOCH`, `mksquashfs` can error out: it forbids combining env-based timestamps and CLI timestamp options.
So we explicitly `unset SOURCE_DATE_EPOCH` right before packaging.

## CUDA libraries and legal bits

You are typically allowed to redistribute *specific CUDA runtime components* (see NVIDIA’s EULA “Attachment A / Redistributable Software”),
but you should:
- redistribute only what you ship with your application (e.g. `nvidia-cuda-runtime-cu12` wheel’s `.so`s),
- include all relevant license texts in your bundle,
- avoid shipping the NVIDIA kernel driver (users must install it).

`nvidia-cuda-runtime-cu12` and friends are marked as proprietary on PyPI; treat them as “redistributable under conditions”, not as OSS.
