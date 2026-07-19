# qnn-builder — QNN SDK + Hexagon NPU FastRPC builds

Builds two extra Snapdragon backends by wrapping
[chraac/llama-cpp-qnn-builder](https://github.com/chraac/llama-cpp-qnn-builder),
which targets **chraac's own llama.cpp fork** (`dev-refactoring` branch) —
independent from the upstream `ggml-org/llama.cpp` this repo's `opencl-gpu/`
and `hexagon-npu/` builds use.

| Flavor | Backend | Notes |
|---|---|---|
| `qnn` | Official Qualcomm **QNN SDK** | NPU/GPU acceleration via Qualcomm's AI Engine Direct SDK |
| `hexagon` | Custom **Hexagon NPU FastRPC** | Built from scratch on Qualcomm's FastRPC framework + raw HVX intrinsics — a *different* implementation from the official `ggml-hexagon` backend already built by [`../hexagon-npu`](../hexagon-npu/) |

Both exist here for comparison/experimentation against the repo's main
OpenCL + official-Hexagon build path.

## Why Docker

The whole build runs inside chraac's own Docker images
(`chraac/llama-cpp-qnn-builder`, `chraac/llama-cpp-qnn-hexagon-builder`),
which already bundle the Android NDK, the Qualcomm QNN SDK, and (for the
`hexagon` flavor) the Hexagon SDK — confirmed by chraac's own CI building
both flavors on plain `ubuntu-latest` runners with no extra SDK setup. The
host only needs **Docker** and **git**; it's an `x86_64`-only cross-compile
targeting `android arm64-v8a`.

## Build

Build both flavors:

```bash
./build.sh
```

Build one flavor:

```bash
./build.sh --flavor qnn
./build.sh --flavor hexagon
```

Build a specific `llama-cpp-qnn-builder` branch/tag/commit:

```bash
./build.sh --tag main
```

Options: `--flavor <qnn|hexagon|both>` (default `both`), `--tag <ref>`,
`--pull` (pull latest builder images first), `--full` (keep every built tool
— `test-backend-ops`, `lldb-server`/`gdbserver`, `sysMonApp`, all `llama-*`
tools — default prunes to `llama-cli`, `llama-server`, `llama-bench`,
`llama-quantize`, `llama-mtmd-cli`, `llama-gguf-split`), `--no-strip` (keep
debug symbols), `--clean` (clear this flavor's build output before
building), `--clean-all` (also re-clone the source). Env overrides:
`SRC_DIR`, `BUILDER_REPO`, `BUILDER_TAG`.

The upstream build ships every tool unstripped (several hundred MB); by
default this script prunes to the runtime set above and strips symbols via
`llvm-strip` from the same Docker image used to build, bringing each package
down to a size comparable to this repo's other Termux packages.

Output:

- `pkg-qnn/`, `pkg-hexagon/` — the raw packaged output (flat `bin` + `.so` dir,
  as produced by chraac's own build)
- `llama-android-arm64-qnn-sdk[-<tag>].tar.gz` (+ `.sha256`)
- `llama-android-arm64-qnn-hexagon-fastrpc[-<tag>].tar.gz` (+ `.sha256`)

## Deploy & run on Termux

Push the extracted tarball contents to the device (via `adb push` or
Termux's own storage access), then from that directory:

```bash
export LD_LIBRARY_PATH=.
chmod +x llama-cli

# QNN SDK build
./llama-cli -m model-Q4_0.gguf -p "Hello"

# Hexagon NPU FastRPC build
./llama-cli -m model-Q4_0.gguf --device HTP0 -ngl 99 -p "Hello"
```

## No manual SDK setup needed

Unlike the [Hexagon SDK setup](https://github.com/chraac/llama-cpp-qnn-builder/blob/main/docs/how-to-build.md#hexagon-sdk-setup)
section in chraac's own docs (for building a *local* image with your own
Hexagon SDK), the public Docker images this script pulls already have what's
needed baked in — no Qualcomm account or manual SDK download required here.
