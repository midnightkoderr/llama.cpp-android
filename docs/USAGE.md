# Usage & tuning

Running the installed binaries, per-SoC tuning, and core pinning. Install first
with the top-level [README](../README.md).

## Quick start

`llama-install` (see the top-level [README](../README.md#install)) installs
all three by default, or just one if you pass it as the first argument:

```bash
llama-install gpu    # OpenCL GPU + CPU only
llama-install npu    # Hexagon NPU + GPU + CPU only
llama-install cpu    # CPU-only build, no gpu/ — binaries land in cpu/ itself
llama-install all    # everything (same as passing nothing)
```

The same target also scopes `--update`, `--uninstall`, and `--revert` — e.g.
`llama-install npu --update` updates only the npu install.

Each installed variant has a `run.sh` that applies sensible defaults — no
manual env sourcing needed. Set `MODEL_DIR` in that variant's `env.sh` to
your `.gguf` folder; `run.sh` lists what's there and prompts you to pick one:

```bash
~/llama.cpp/npu/run.sh -p "Hello"
~/llama.cpp/gpu/run.sh -p "Hello"
~/llama.cpp/cpu/run.sh -p "Hello"
```

Defaults are tunable via env vars without editing anything — `NGL`, `CTX`,
`THREADS`, and (gpu/cpu only) `CORES` for `taskset` pinning, matching the
per-SoC values used throughout the rest of this doc:

```bash
CORES=2-7 THREADS=4 ~/llama.cpp/gpu/run.sh -p "Hello"
```

The rest of this doc covers those same flags manually. Source a variant's
`env.sh` first to put `llama-cli`/`llama-server` on `PATH` for the shell:

```bash
source ~/llama.cpp/npu/env.sh   # or gpu/env.sh, or cpu/env.sh
```

## Device reference

| | SD 8 Gen 3 (S24) | SD 7+ Gen 3 (Pad 7) |
|---|---|---|
| CPU | 1× X4 (3.3 GHz) + 5× A720 + 2× A520 | 1× X4 (2.8 GHz) + 4× A720 + 3× A520 |
| P-cores | 6 (cpu2–7) | 5 (cpu3–7) |
| E-cores | 2 (cpu0–1) | 3 (cpu0–2) |
| GPU | Adreno 750 | Adreno 732 |
| NPU | Hexagon v75 | Hexagon v73 |
| Mem bandwidth | ~77 GB/s | ~51 GB/s |

Both chips share CPU microarchitectures (X4, A720, A520) and ISA extensions —
one binary runs on both.

## NPU (Hexagon)

Offload to the NPU with `--device HTP0 -ngl 99`. Best with **Q4_0 / Q8_0 /
MXFP4** weights (those are repacked for the NPU):

```bash
source ~/llama.cpp/npu/env.sh
llama-cli -m model-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 -p "Hello"
```

A single NPU session maps ~3.5 GB. Split larger models across devices:

```bash
GGML_HEXAGON_NDEV=2 llama-cli -m big-Q4_0.gguf --device HTP0,HTP1 -ngl 99 -c 4096 -p "Hello"
```

## GPU (OpenCL / Adreno)

Offload `N` layers with `-ngl N`. Start at `10` and raise until inference slows
or the process crashes (unified memory limit). CPU and GPU share RAM — keep the
model under ~50% of total RAM.

```bash
source ~/llama.cpp/gpu/env.sh
```

SD 8 Gen 3 (Adreno 750):

```bash
taskset -c 2-7 llama-cli -m model.gguf -t 4 -ngl 28 -c 4096 -p "Hello"
```

SD 7+ Gen 3 (Adreno 732):

```bash
taskset -c 3-7 llama-cli -m model.gguf -t 3 -ngl 28 -c 2048 -p "Hello"
```

## CPU only (`~/llama.cpp/cpu/`, reuses the gpu build with `-ngl 0`)

```bash
source ~/llama.cpp/cpu/env.sh
```

SD 8 Gen 3 (6 P-cores: cpu2-7):

```bash
taskset -c 2-7 llama-cli -m model.gguf -t 6 -ngl 0 -c 2048 -p "Hello"
```

SD 7+ Gen 3 (5 P-cores: cpu3-7):

```bash
taskset -c 3-7 llama-cli -m model.gguf -t 5 -ngl 0 -c 2048 -p "Hello"
```

## llama-server (OpenAI-compatible API)

GPU:

```bash
source ~/llama.cpp/gpu/env.sh
llama-server -m model.gguf --host 0.0.0.0 --port 8080 -t 4 -ngl 28 -c 4096
```

NPU:

```bash
source ~/llama.cpp/npu/env.sh
llama-server -m model-Q4_0.gguf --host 0.0.0.0 --port 8080 --device HTP0 -ngl 99
```

Access at `http://localhost:8080`.

## Recommended flags

| Flag | SD 8 Gen 3 | SD 7+ Gen 3 | Effect |
|------|---|---|---|
| `-t` | `6` | `5` | Thread count — match P-core count |
| `-t` (with offload) | `4` | `3` | Fewer threads needed when GPU/NPU offloads |
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
- **SD 7+ Gen 3** — P-cores are `cpu3–7`: `taskset -c 3-7 llama-cli -t 5 ...`

## libomp.so (gpu / cpu variants)

Android doesn't ship `libomp.so`. The OpenCL build is OpenMP-threaded, so the
installer places `libomp.so` in `~/llama.cpp/gpu/lib` (the `cpu/` variant
reuses it from there too), and sourcing `gpu/env.sh` or `cpu/env.sh` sets
`LD_LIBRARY_PATH` so it's discoverable. The Hexagon build isn't
OpenMP-threaded and doesn't need it.
