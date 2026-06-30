# hexagon-npu — Hexagon NPU build

Cross-compiles llama.cpp for Snapdragon with the **Hexagon NPU (HTP)** backend,
plus CPU and OpenCL (Adreno GPU). Produces a `bin/` + `lib/` package whose NPU
kernel libs (`libggml-htp-v*.so`) cover every Hexagon version; the right one is
picked at runtime.

| SoC | Model | Hexagon |
|---|---|---|
| Snapdragon 8 Gen 3 | SM8650 | v75 |
| Snapdragon 7+ Gen 3 | SM7675 | v73 |

## Why Docker

The on-NPU kernels must be compiled with Qualcomm's proprietary **Hexagon SDK**
+ Hexagon tools. Instead of installing that by hand, the build runs inside
Qualcomm's official toolchain image
([snapdragon-toolchain](https://github.com/snapdragon-toolchain)), which bundles
the Android NDK, OpenCL SDK, Hexagon SDK and tools. The host only needs **Docker**
and **git**; it's an `x86_64`-only cross-compile.

## Build

Build llama.cpp master:

```bash
./build.sh
```

Build a specific upstream tag/branch/commit:

```bash
./build.sh --tag b6904
```

Pull the toolchain image first:

```bash
./build.sh --pull
```

Options: `--tag <ref>`, `--image <ref>`, `--jobs <n>`, `--no-strip`,
`--full` (keep headers/cmake/all tools — default prunes to runtime files),
`--pull`, `--clean`, `--clean-all`. Env overrides: `SRC_DIR`, `LLAMA_REPO`,
`TOOLCHAIN_IMAGE`, `LLAMACPP_TAG`.

Tests are skipped, and the package is pruned to a runtime tool set
(`llama-cli`, `llama-server`, `llama-bench`, `llama-quantize`, `llama-mtmd-cli`,
`llama-gguf-split`) plus the `.so` they need.

Output:

- `llama.cpp/pkg-snapdragon/llama.cpp/{bin,lib}` — the installable package
- `llama-android-arm64-hexagon[-<tag>].tar.gz` (+ `.sha256`) in this directory

## Native build (no Docker)

The build is an ordinary cross-compile — Docker only ships the SDKs. To build
natively on Linux x86_64 you must install the Android NDK, an OpenCL SDK, and the
proprietary **Hexagon SDK 6.6.x** (via Qualcomm Package Manager — free account).
Then set `ANDROID_NDK_ROOT`, `OPENCL_SDK_ROOT`, `HEXAGON_SDK_ROOT`,
`HEXAGON_TOOLS_ROOT` and configure the `arm64-android-snapdragon-release` preset
from `llama.cpp/docs/backend/snapdragon/CMakeUserPresets.json` directly.

## Deploy & run on device

Push the package:

```bash
adb push llama.cpp/pkg-snapdragon/llama.cpp /data/local/tmp/llama.cpp
```

On the device, set the library paths (`ADSP_LIBRARY_PATH` lets FastRPC find the
HTP kernels):

```bash
export LD_LIBRARY_PATH=/data/local/tmp/llama.cpp/lib
```

```bash
export ADSP_LIBRARY_PATH=/data/local/tmp/llama.cpp/lib
```

Offload to the NPU (best with Q4_0 / Q8_0 / MXFP4 weights):

```bash
./bin/llama-cli -m model-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 -p "Hello"
```

A single NPU session maps ~3.5 GB. Split bigger models across devices:

```bash
GGML_HEXAGON_NDEV=2 ./bin/llama-cli -m big-Q4_0.gguf --device HTP0,HTP1 -ngl 99 -c 4096 -p "Hello"
```

See `llama.cpp/docs/backend/snapdragon/` for full backend documentation, and
[../docs/USAGE.md](../docs/USAGE.md) for tuning across both SoCs.
