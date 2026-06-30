# llama.cpp for Snapdragon Android

Cross-compiled `llama-cli` / `llama-server` (and friends) for Android arm64-v8a,
targeting **Snapdragon 8 Gen 3** and **SD 7+ Gen 3**. Two build variants:

| | **opencl** | **hexagon** |
|---|---|---|
| Backends | CPU + OpenCL (Adreno GPU) | CPU + OpenCL + **Hexagon NPU (HTP)** |
| Offload flag | `-ngl N` (GPU) | `--device HTP0 -ngl 99` (NPU) or `-ngl N` (GPU) |
| Layout | `bin/` + `lib/` | `bin/` + `lib/` |
| Linking | static (self-contained binaries + `libomp.so`) | shared `libggml-*.so` set incl. HTP kernels |
| Extra runtime env | `LD_LIBRARY_PATH` | `LD_LIBRARY_PATH` + `ADSP_LIBRARY_PATH` |
| Footprint | small | larger (ships HTP kernels for every Hexagon version) |
| Build toolchain | Android NDK | Qualcomm toolchain (Hexagon SDK, via Docker) |

The Hexagon package's NPU kernel libs (`libggml-htp-v*.so`) cover every Hexagon
version; the right one is selected at runtime:

| SoC | Model | Hexagon |
|---|---|---|
| Snapdragon 8 Gen 3 | SM8650 | **v75** |
| Snapdragon 7+ Gen 3 | SM7675 | **v73** |

Builds are published automatically via GitHub Actions — both variants attach to
the same release. Download from the [Releases](../../releases) page.

## Install

Run on your Android device in Termux or `adb shell`. Pick a variant
(default is `opencl`):

OpenCL GPU build (default):

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/installer.sh | bash
```

Hexagon NPU build:

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/installer.sh | bash -s -- --hexagon
```

`--hexagon` is shorthand for `--variant hexagon`; `--opencl` / `--variant opencl`
selects the GPU build. Installs to `~/llama.cpp/`:

- `~/llama.cpp/bin` — `llama-cli`, `llama-server`, `llama-bench`, `llama-quantize`, `llama-mtmd-cli`, `llama-gguf-split`
- `~/llama.cpp/lib` — `*.so`, `llama-cpp.version`, `llama-cpp.variant`

Custom location (`PREFIX` sets both, or override individually):

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/installer.sh | bash -s -- --hexagon --install-dir ~/llama.cpp/bin --lib-dir ~/llama.cpp/lib
```

The installer prints the exact lines to add to `~/.bashrc`. Put the binaries on `PATH`:

```bash
echo 'export PATH=${HOME}/llama.cpp/bin:${PATH}' >> ~/.bashrc
```

Point the loader at the libraries:

```bash
echo 'export LD_LIBRARY_PATH=${HOME}/llama.cpp/lib:${LD_LIBRARY_PATH}' >> ~/.bashrc
```

Hexagon only — let FastRPC find the HTP kernel libs:

```bash
echo 'export ADSP_LIBRARY_PATH=${HOME}/llama.cpp/lib' >> ~/.bashrc
```

Reload:

```bash
source ~/.bashrc
```

## Update

```bash
curl -fsSL .../installer.sh | bash -s -- --update
```

Keeps whichever variant is already installed (recorded in `llama-cpp.variant`),
checks the latest release against the installed version, and skips if current.
Before overwriting, backs up the current binaries, `.so`, version and variant to
`~/.llama.cpp-bin-backup`. Pass `--hexagon` / `--opencl` alongside `--update` to
switch variants. When a `.tar.gz.sha256` asset is present, the download is
checksum-verified.

## Revert

```bash
curl -fsSL .../installer.sh | bash -s -- --revert
```

Restores binaries, libraries, version and variant from
`~/.llama.cpp-bin-backup`, then removes the backup. Only one previous version is
kept.

## Uninstall

Removes the installed binaries, libraries, version/variant markers and the
backup — only files this installer creates, so it's safe with a shared dir:

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/uninstall.sh | bash
```

Preview without deleting anything:

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/uninstall.sh | bash -s -- --dry-run
```

Match a custom install location with `--prefix` (or `--install-dir`/`--lib-dir`),
and pass `--keep-backup` to leave the revert backup in place. Afterwards, drop
the `PATH` / `LD_LIBRARY_PATH` / `ADSP_LIBRARY_PATH` lines you added to `~/.bashrc`.

## Device reference

| | SD 8 Gen 3 (S24) | SD 7+ Gen 3 (Pad 7) |
|---|---|---|
| CPU | 1× X4 (3.3 GHz) + 5× A720 + 2× A520 | 1× X4 (2.8 GHz) + 3× A720 + 4× A520 |
| P-cores | 6 (cpu2–7) | 4 (cpu4–7) |
| E-cores | 2 (cpu0–1) | 4 (cpu0–3) |
| GPU | Adreno 750 | Adreno 732 |
| NPU | Hexagon v75 | Hexagon v73 |
| Mem bandwidth | ~77 GB/s | ~51 GB/s |

Both chips share CPU microarchitectures (X4, A720, A520) and ISA extensions —
one binary runs on both.

## Running

### NPU (Hexagon — `hexagon` variant only)

Offload to the NPU with `--device HTP0 -ngl 99`. Works best with **Q4_0 / Q8_0 /
MXFP4** weights (those are repacked for the NPU).

```bash
llama-cli -m model-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 -p "Hello"
```

A single NPU session (process domain) maps ~3.5 GB. For larger models, split
across multiple devices:

```bash
GGML_HEXAGON_NDEV=2 llama-cli -m big-Q4_0.gguf --device HTP0,HTP1 -ngl 99 ...
```

### GPU (OpenCL / Adreno — both variants)

Use `-ngl N` to offload `N` layers. Start at `10` and increase until inference
slows or the process crashes (unified memory limit). CPU and GPU share RAM —
keep the model under ~50% of total RAM.

SD 8 Gen 3 (Adreno 750):

```bash
taskset -c 2-7 llama-cli -m model.gguf -t 4 -ngl 28 -c 4096 -p "Hello"
```

SD 7+ Gen 3 (Adreno 732):

```bash
taskset -c 4-7 llama-cli -m model.gguf -t 2 -ngl 28 -c 2048 -p "Hello"
```

### CPU only (both variants)

SD 8 Gen 3 (6 P-cores: cpu2-7):

```bash
taskset -c 2-7 llama-cli -m model.gguf -t 6 -ngl 0 -c 2048 -p "Hello"
```

SD 7+ Gen 3 (4 P-cores: cpu4-7):

```bash
taskset -c 4-7 llama-cli -m model.gguf -t 4 -ngl 0 -c 2048 -p "Hello"
```

### llama-server (OpenAI-compatible API)

GPU:

```bash
llama-server -m model.gguf --host 0.0.0.0 --port 8080 -t 4 -ngl 28 -c 4096
```

NPU (hexagon variant):

```bash
llama-server -m model-Q4_0.gguf --host 0.0.0.0 --port 8080 --device HTP0 -ngl 99
```

Access at `http://localhost:8080`.

## Recommended flags

| Flag | SD 8 Gen 3 | SD 7+ Gen 3 | Effect |
|------|---|---|---|
| `-t` | `6` | `4` | Thread count — match P-core count |
| `-t` (with offload) | `4` | `2` | Fewer threads needed when GPU/NPU offloads |
| `-c` | `2048`–`4096` | `2048` | Context length |
| `-ngl 0` | ✓ | ✓ | CPU-only mode |
| `--device HTP0 -ngl 99` | ✓ | ✓ | Full NPU offload (hexagon variant) |
| `--mlock` | ✓ | ✓ | Lock weights in RAM, prevents swapping |
| `-b 512` | ✓ | ✓ | Batch size for prompt processing |

## P-core pinning

Pin inference to performance cores — E-cores hurt throughput in llama.cpp.
Install `util-linux` for `taskset` if needed:

```bash
command -v taskset >/dev/null || pkg install util-linux
```

- **SD 8 Gen 3** — P-cores are `cpu2–7`: `taskset -c 2-7 llama-cli -t 6 ...`
- **SD 7+ Gen 3** — P-cores are `cpu4–7`: `taskset -c 4-7 llama-cli -t 4 ...`

## libomp.so (opencl variant)

Android doesn't ship `libomp.so`. The OpenCL build is OpenMP-threaded, so the
installer places `libomp.so` in `~/llama.cpp/lib`; the `LD_LIBRARY_PATH` export
makes it discoverable. (The Hexagon build is not OpenMP-threaded and doesn't
need it.)

## Build from source

Both build harnesses run on a **Linux x86_64** host and cross-compile for the
phone. See each variant's README for details.

### opencl-gpu — needs only the Android NDK

Set the NDK path:

```bash
export ANDROID_NDK=$HOME/android-sdk/ndk/26.3.11579264
```

Build (output in `llama.cpp/android-bin/{bin,lib}`):

```bash
./opencl-gpu/build.sh --opencl
```

### hexagon-npu — needs the Hexagon SDK (provided via Qualcomm's Docker image)

Build inside the toolchain container (output in `hexagon-npu/llama.cpp/pkg-snapdragon/llama.cpp/{bin,lib}`):

```bash
./hexagon-npu/build.sh
```

See [`hexagon-npu/README.md`](hexagon-npu/README.md) for the Docker toolchain,
native-build notes, and deploy instructions.
