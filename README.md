# llama.cpp for Snapdragon Android

Prebuilt `llama-cli` / `llama-server` (and friends) for Android arm64-v8a,
targeting **Snapdragon 8 Gen 3** and **7+ Gen 3**, installed side by side under
one base dir:

- **gpu** — CPU + OpenCL (Adreno GPU) — `~/llama.cpp/gpu/{bin,lib}`
- **npu** — CPU + OpenCL + **Hexagon NPU (HTP)** — `~/llama.cpp/npu/{bin,lib}`
- **cpu** — CPU only, `~/llama.cpp/cpu/` — reuses the gpu build in CPU-only
  mode (`-ngl 0`); no separate package needed

Prebuilt archives are on the [Releases](../../releases) page (built
automatically via GitHub Actions).

## Install

Run in Termux (recommended) or `adb shell`. This saves the installer as
`llama-install` on your `PATH`, so every later command (`--update`,
`--uninstall`, `--backup`, ...) is just `llama-install <flag>` instead of
re-downloading:

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh -o "${HOME}/.local/bin/llama-install"
chmod +x "${HOME}/.local/bin/llama-install"

llama-install
```

On plain `adb shell` (no Termux), run it via `bash ~/.local/bin/llama-install`
instead — the saved script's shebang targets Termux's bash path.

With no argument, `llama-install` sets up all three (gpu, npu, cpu) in one go.
To install just one, pass it as the first argument — this works with
`--update`, `--uninstall`, and `--revert` too, not just a fresh install:

```bash
llama-install gpu    # OpenCL GPU + CPU only
llama-install npu    # Hexagon NPU + GPU + CPU only
llama-install cpu    # CPU-only build, no gpu/ — binaries land in cpu/ itself
llama-install all    # everything (same as passing nothing)
```

Each install gets its own `run.sh` and an `env.sh`. Quickest path —
`run.sh <model.gguf> [llama-cli args...]` applies sensible per-variant
defaults, no setup needed:

```bash
~/llama.cpp/npu/run.sh model-Q4_0.gguf -p "Hello"   # Hexagon NPU + GPU + CPU
~/llama.cpp/gpu/run.sh model.gguf -p "Hello"        # OpenCL GPU + CPU
~/llama.cpp/cpu/run.sh model.gguf -p "Hello"        # CPU only (reuses the gpu build)
```

Defaults (thread count, context, NPU/GPU offload, `taskset` core pinning) are
tunable via env vars — see [docs/USAGE.md](docs/USAGE.md) for per-SoC values.

For manual flag control instead, `source` a variant's `env.sh` to put its
tools on `PATH` for the current shell, then call `llama-cli`/`llama-server`
directly:

```bash
source ~/llama.cpp/npu/env.sh
llama-cli -m model-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 -p "Hello"
```

Sourcing more than one variant's `env.sh` in the same shell just means
whichever you source last wins on `PATH` — all three ship binaries with the
same names.

## Uninstall

Remove everything (all installs + their revert backups):

```bash
llama-install --uninstall
```

or

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash -s -- --uninstall
```

Remove just one target — `llama-install <cpu|gpu|npu> --uninstall`. `npu`
removes only `~/llama.cpp/npu/`. `gpu` removes `~/llama.cpp/gpu/` **and**
`cpu/` with it, since `cpu/` can't function without the gpu build. `cpu` is
the one exception — it removes only the `cpu/` wrapper, leaving `gpu/` (and
whatever's using it) untouched:

```bash
llama-install npu --uninstall
llama-install gpu --uninstall   # also removes cpu/
llama-install cpu --uninstall   # removes only cpu/, keeps gpu/
```

Keep the revert backups instead of deleting them:

```bash
llama-install --uninstall --keep-backup
```

Preview without deleting:

```bash
llama-install --uninstall --dry-run
```

or

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash -s -- --uninstall --dry-run
```

## Update

```bash
llama-install --update
```

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash -s -- --update
```

Updates everything installed, skips whichever is already current, and backs
up each variant's previous version separately
(`~/.llama.cpp-bin-backup-opencl` / `~/.llama.cpp-bin-backup-hexagon`) first.
Add a target to update just that one, e.g. `llama-install npu --update`.

## Revert

```bash
llama-install --revert
```

or

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash -s -- --revert
```

Restores the previous version from backup (one level kept each). Add a
target to revert just that one, e.g. `llama-install gpu --revert`.

## Backup & Restore

Zip the whole install into a single portable archive — handy before wiping
Termux, resetting the device, or moving to a new phone. Requires `zip`/`unzip`
(`pkg install zip unzip` in Termux).

```bash
llama-install --backup
```

Custom path/name (default is `~/llama-cpp-backup-<timestamp>.zip`):

```bash
llama-install --backup ~/storage/shared/llama-cpp-backup.zip
```

Restore from a backup archive (works on a fresh install too):

```bash
llama-install --restore ~/storage/shared/llama-cpp-backup.zip
```

Note: this only covers the active install (`~/llama.cpp/`) — not the internal
`--update`/`--revert` backups.

## Variants

| | **gpu** | **npu** | **cpu** |
|---|---|---|---|
| Install path | `~/llama.cpp/gpu/` | `~/llama.cpp/npu/` | `~/llama.cpp/cpu/` |
| Backends | CPU + OpenCL (Adreno GPU) | CPU + OpenCL + **Hexagon NPU (HTP)** | CPU only (reuses the gpu build) |
| Offload | `-ngl N` (GPU) | `--device HTP0 -ngl 99` (NPU) or `-ngl N` (GPU) | none — `-ngl 0`, forced |
| Linking | static + `libomp.so` | shared `libggml-*.so` incl. HTP kernels | static + `libomp.so` (shared with gpu) |
| Runtime env | `LD_LIBRARY_PATH` | `LD_LIBRARY_PATH` + `ADSP_LIBRARY_PATH` | `LD_LIBRARY_PATH` |
| Footprint | small | larger (HTP kernels for every Hexagon version) | none extra — no binaries of its own |

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
