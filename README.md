# llama.cpp for Snapdragon Android

Prebuilt `llama-cli` / `llama-server` (and friends) for Android arm64-v8a,
targeting **Snapdragon 8 Gen 3** and **7+ Gen 3**, in two variants, installed
side by side:

- **opencl** — CPU + OpenCL (Adreno GPU) — `~/llama.cpp-opencl/{bin,lib}`
- **hexagon** — CPU + OpenCL + **Hexagon NPU (HTP)** — `~/llama.cpp-hexagon/{bin,lib}`

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

This installs both variants in one go. Add aliases so each variant's binaries
pick up their own libraries automatically (the installer prints these exact
lines after a successful install — copy them from there to get the real
resolved paths; run this once, re-running duplicates the lines):

```bash
cat >> ~/.alias <<'EOF'
alias llama-cli-npu="LD_LIBRARY_PATH=${HOME}/llama.cpp-hexagon/lib ADSP_LIBRARY_PATH=${HOME}/llama.cpp-hexagon/lib ${HOME}/llama.cpp-hexagon/bin/llama-cli"
alias llama-server-npu="LD_LIBRARY_PATH=${HOME}/llama.cpp-hexagon/lib ADSP_LIBRARY_PATH=${HOME}/llama.cpp-hexagon/lib ${HOME}/llama.cpp-hexagon/bin/llama-server"
alias llama-cli-gpu="LD_LIBRARY_PATH=${HOME}/llama.cpp-opencl/lib ${HOME}/llama.cpp-opencl/bin/llama-cli"
alias llama-server-gpu="LD_LIBRARY_PATH=${HOME}/llama.cpp-opencl/lib ${HOME}/llama.cpp-opencl/bin/llama-server"

EOF

. ~/.bashrc
```

`llama-cli-npu`/`llama-server-npu` run the Hexagon NPU + GPU + CPU build;
`llama-cli-gpu`/`llama-server-gpu` run the OpenCL GPU + CPU build. Both are
always installed, so switching between them is just picking which alias to run.

## Uninstall

Remove both installs and their revert backups:

```bash
llama-install --uninstall
```

or

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash -s -- --uninstall
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

Then drop the `llama-*-npu` / `llama-*-gpu` alias lines (and the
`. ~/.alias` line) from `~/.bashrc`.

## Update

```bash
llama-install --update
```

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash -s -- --update
```

Updates both variants, skips whichever is already current, and backs up each
variant's previous version separately (`~/.llama.cpp-bin-backup-opencl` /
`~/.llama.cpp-bin-backup-hexagon`) first.

## Revert

```bash
llama-install --revert
```

or

```bash
curl -fsSL https://raw.githubusercontent.com/midnightkoderr/llama.cpp-android/main/install.sh | bash -s -- --revert
```

Restores both variants' previous version from backup (one level kept each).

## Backup & Restore

Zip both installs (+ your `~/.alias`) into a single portable archive — handy
before wiping Termux, resetting the device, or moving to a new phone. Requires
`zip`/`unzip` (`pkg install zip unzip` in Termux).

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

Note: this only covers the active installs and `~/.alias` — not the internal
`--update`/`--revert` backups.

## Variants

| | **opencl** | **hexagon** |
|---|---|---|
| Install path | `~/llama.cpp-opencl/` | `~/llama.cpp-hexagon/` |
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
