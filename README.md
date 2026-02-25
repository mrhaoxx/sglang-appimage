# Reproducible SGLang AppImage build (template)

This template gives you a *repeatable* build pipeline for packaging **SGLang** into an **AppImage** that **bundles the CUDA runtime libraries shipped by your Python wheels** (e.g. PyTorch’s `nvidia-*-cu12` wheels), so you don’t depend on a system CUDA Toolkit.

It focuses on:
- **Reproducible dependency resolution** (pinned + hash-checked) using `uv`.
- **Reproducible build environment** using a Docker builder image.
- A `python-appimage` **app recipe** for producing the AppImage.

> You will still need an **NVIDIA driver** on the target machine. The driver is not legally or technically bundled here.

---

## 0) Prereqs

- Docker
- x86_64 Linux host (recommended)
- Network access during the first build (you can later cache wheels and reuse)

---

## 1) Set versions (edit once)

Edit `recipe/versions.env`:

- `PYTHON_SHORT` (e.g. 3.11)
- `TORCH_CUDA_INDEX` (e.g. `https://download.pytorch.org/whl/cu124`)
- `TORCH_PINS` (torch/vision/audio pins)
- `SGLANG_PIN` (your sglang version pin)

Then generate the concrete requirements input:

```bash
./scripts/render_requirements.sh
```

---

## 2) Lock dependencies with hashes (reproducible installs)

```bash
./scripts/lock.sh
```

This produces `recipe/requirements.lock` with `--hash=sha256:...` lines.

---

## 3) Build the AppImage in Docker

```bash
./scripts/build.sh
```

Your AppImage will be written to `dist/`.

---

## 4) Verify “self-contained CUDA runtime”

On a machine **without** the CUDA Toolkit (but with NVIDIA driver):

```bash
./dist/SGLang.AppImage --help
```

To inspect which CUDA libs are used at runtime, run:

```bash
./scripts/inspect_cuda_libs.sh ./dist/SGLang.AppImage
```

---

## Notes about reproducibility

- Hash-locked installs: `uv pip compile --generate-hashes` + enforcing hashes makes the Python dependency set reproducible.
- AppImage timestamps: many builders export `SOURCE_DATE_EPOCH`. `appimagetool` can fail if `SOURCE_DATE_EPOCH` is set while it also hardcodes `-mkfs-time 0`, so the scripts explicitly **unset** `SOURCE_DATE_EPOCH` before packaging.
- For “bit-for-bit” identical AppImages, you’ll additionally want to normalize file mtimes inside the AppDir and control SquashFS ordering. This template gets you *close* and avoids the most common nondeterminism sources.

---

## Where to plug in your custom SGLang launch

Edit `recipe/entrypoint.sh` and `recipe/app.desktop`.
