# opencl-gpu — OpenCL (Adreno GPU) build

Cross-compiles llama.cpp for Android arm64-v8a with the **OpenCL** backend
(Adreno GPU) + CPU. Statically linked tools — the only runtime dependency is
`libomp.so`, shipped alongside. Produces a `bin/` + `lib/` package.

Builds: `llama-cli`, `llama-server`, `llama-bench`, `llama-quantize`,
`llama-mtmd-cli`, `llama-gguf-split`.

## Requirements

Linux x86_64 host with `cmake`, `ninja-build`, `git`, and the Android NDK (r26+).
The OpenCL headers + ICD loader are fetched and cross-compiled automatically.

## Build

Set the NDK path:

```bash
export ANDROID_NDK=$HOME/android-sdk/ndk/26.3.11579264
```

Build with OpenCL:

```bash
./build.sh --opencl
```

Options: `--opencl` (enable GPU backend), `--clean`, `--clean-all`,
`--ndk <path>`. Output lands in `llama.cpp/android-bin/{bin,lib}`:

- `bin/` — the six tools above
- `lib/` — `libomp.so`

The CI workflow packs this into `llama-android-arm64-opencl-<tag>.tar.gz`.

## Run

Offload `N` layers to the GPU with `-ngl N` (start ~10, raise until it slows or
crashes — CPU and GPU share RAM). See [../docs/USAGE.md](../docs/USAGE.md) for
per-SoC tuning, thread/core pinning, and the server mode.

```bash
taskset -c 2-7 llama-cli -m model.gguf -t 4 -ngl 28 -c 4096 -p "Hello"
```
