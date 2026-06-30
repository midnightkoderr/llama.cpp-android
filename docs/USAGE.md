# Usage & tuning

Running the installed binaries, per-SoC tuning, and core pinning. Install first
with the top-level [README](../README.md).

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

## NPU (Hexagon — `hexagon` variant only)

Offload to the NPU with `--device HTP0 -ngl 99`. Best with **Q4_0 / Q8_0 /
MXFP4** weights (those are repacked for the NPU):

```bash
llama-cli -m model-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 -p "Hello"
```

A single NPU session maps ~3.5 GB. Split larger models across devices:

```bash
GGML_HEXAGON_NDEV=2 llama-cli -m big-Q4_0.gguf --device HTP0,HTP1 -ngl 99 -c 4096 -p "Hello"
```

## GPU (OpenCL / Adreno — both variants)

Offload `N` layers with `-ngl N`. Start at `10` and raise until inference slows
or the process crashes (unified memory limit). CPU and GPU share RAM — keep the
model under ~50% of total RAM.

SD 8 Gen 3 (Adreno 750):

```bash
taskset -c 2-7 llama-cli -m model.gguf -t 4 -ngl 28 -c 4096 -p "Hello"
```

SD 7+ Gen 3 (Adreno 732):

```bash
taskset -c 4-7 llama-cli -m model.gguf -t 2 -ngl 28 -c 2048 -p "Hello"
```

## CPU only (both variants)

SD 8 Gen 3 (6 P-cores: cpu2-7):

```bash
taskset -c 2-7 llama-cli -m model.gguf -t 6 -ngl 0 -c 2048 -p "Hello"
```

SD 7+ Gen 3 (4 P-cores: cpu4-7):

```bash
taskset -c 4-7 llama-cli -m model.gguf -t 4 -ngl 0 -c 2048 -p "Hello"
```

## llama-server (OpenAI-compatible API)

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
installer places `libomp.so` in `~/llama.cpp/lib` and the `LD_LIBRARY_PATH`
export makes it discoverable. The Hexagon build isn't OpenMP-threaded and
doesn't need it.
