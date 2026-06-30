# llama.cpp for Snapdragon Android

Prebuilt `llama-cli` / `llama-server` (and friends) for Android arm64-v8a,
targeting **Snapdragon 8 Gen 3** and **7+ Gen 3**, in two variants:

- **opencl** — CPU + OpenCL (Adreno GPU)
- **hexagon** — CPU + OpenCL + **Hexagon NPU (HTP)**

Everything installs to `~/llama.cpp/{bin,lib}`. Prebuilt archives are on the
[Releases](../../releases) page (built automatically via GitHub Actions).

## Install

Run in Termux or `adb shell`. OpenCL GPU build (default):

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash
```

Hexagon NPU build:

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash -s -- --hexagon
```

Then put the binaries on `PATH`:

```bash
echo 'export PATH=${HOME}/llama.cpp/bin:${PATH}' >> ~/.bashrc
```

Point the loader at the libraries:

```bash
echo 'export LD_LIBRARY_PATH=/vendor/lib64:${HOME}/llama.cpp/lib' >> ~/.bashrc
```

Hexagon only — let FastRPC find the NPU kernel libs:

```bash
echo 'export ADSP_LIBRARY_PATH=${HOME}/llama.cpp/lib' >> ~/.bashrc
```

Reload:

```bash
source ~/.bashrc
```

(The installer prints these exact lines after a successful install.)

## Uninstall

Remove `~/llama.cpp` and the revert backup:

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/uninstall.sh | bash
```

Preview without deleting:

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/uninstall.sh | bash -s -- --dry-run
```

Then drop the `PATH` / `LD_LIBRARY_PATH` / `ADSP_LIBRARY_PATH` lines from `~/.bashrc`.

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash -s -- --update
```

Keeps the installed variant, skips if already current, and backs up the previous
version to `~/.llama.cpp-bin-backup` first. Add `--hexagon` / `--opencl` to switch
variants.

## Revert

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash -s -- --revert
```

Restores the previous version from backup (one level kept).

## Variants

| | **opencl** | **hexagon** |
|---|---|---|
| Backends | CPU + OpenCL (Adreno GPU) | CPU + OpenCL + **Hexagon NPU (HTP)** |
| Offload | `-ngl N` (GPU) | `--device HTP0 -ngl 99` (NPU) or `-ngl N` (GPU) |
| Linking | static + `libomp.so` | shared `libggml-*.so` incl. HTP kernels |
| Runtime env | `LD_LIBRARY_PATH` | `LD_LIBRARY_PATH` + `ADSP_LIBRARY_PATH` |
| Footprint | small | larger (HTP kernels for every Hexagon version) |

| SoC | Model | GPU | NPU |
|---|---|---|---|
| Snapdragon 8 Gen 3 | SM8650 | Adreno 750 | Hexagon v75 |
| Snapdragon 7+ Gen 3 | SM7675 | Adreno 732 | Hexagon v73 |

One archive runs on both SoCs — the Hexagon package ships every HTP version and
selects the right one at runtime.

## Docs

- **[Usage & tuning](docs/USAGE.md)** — running on NPU / GPU / CPU, server mode, recommended flags, core pinning
- **[opencl-gpu/](opencl-gpu/README.md)** — build the OpenCL variant from source (Android NDK)
- **[hexagon-npu/](hexagon-npu/README.md)** — build the Hexagon variant from source (Qualcomm toolchain)
