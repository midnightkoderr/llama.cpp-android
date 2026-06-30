#!/usr/bin/env bash
# Cross-compile llama.cpp for Snapdragon with the Hexagon NPU (HTP) backend.
#
# Unlike the OpenCL build, the Hexagon backend needs Qualcomm's proprietary
# Hexagon SDK + Hexagon tools to compile the on-NPU kernel libraries
# (libggml-htp-vNN.so). Rather than ask you to register for and install that
# SDK by hand, this script builds inside Qualcomm's official toolchain Docker
# image, which bundles the Android NDK, OpenCL SDK, Hexagon SDK and Hexagon
# tools (see https://github.com/snapdragon-toolchain).
#
# The build produces HTP kernel libs for every Hexagon version (v68..v81) and
# the correct one is picked at runtime, so a single package covers both
# target SoCs:
#
#   Snapdragon 8 Gen 3  (SM8650)  -> Hexagon v75
#   Snapdragon 7+ Gen 3 (SM7675)  -> Hexagon v73
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SRC_DIR:-$PROJECT_ROOT/llama.cpp}"
BUILD_DIR_NAME="build-snapdragon"
PKG_DIR_NAME="pkg-snapdragon"

LLAMA_REPO="${LLAMA_REPO:-https://github.com/ggml-org/llama.cpp.git}"
IMAGE="${TOOLCHAIN_IMAGE:-ghcr.io/snapdragon-toolchain/arm64-android:v0.7}"
PRESET="arm64-android-snapdragon-release"

LLAMACPP_TAG="${LLAMACPP_TAG:-}"   # empty = default branch (master)
JOBS="$(nproc)"
DO_STRIP=1
CLEAN=0
CLEAN_ALL=0
PULL=0

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [options]

  --tag <ref>      Build a specific llama.cpp tag/branch/commit (default: master)
  --image <ref>    Toolchain Docker image (default: $IMAGE)
  --jobs <n>       Parallel build jobs (default: nproc = $JOBS)
  --no-strip       Keep symbols (do not strip the output libraries/binaries)
  --pull           docker pull the toolchain image before building
  --clean          Remove the build dir before configuring
  --clean-all      Remove the cloned source + build dir, then re-clone
  -h, --help       Show this help

Env overrides: SRC_DIR, LLAMA_REPO, TOOLCHAIN_IMAGE, LLAMACPP_TAG
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)       LLAMACPP_TAG="$2"; shift 2 ;;
    --tag=*)     LLAMACPP_TAG="${1#*=}"; shift ;;
    --image)     IMAGE="$2"; shift 2 ;;
    --image=*)   IMAGE="${1#*=}"; shift ;;
    --jobs)      JOBS="$2"; shift 2 ;;
    --jobs=*)    JOBS="${1#*=}"; shift ;;
    --no-strip)  DO_STRIP=0; shift ;;
    --pull)      PULL=1; shift ;;
    --clean)     CLEAN=1; shift ;;
    --clean-all) CLEAN_ALL=1; CLEAN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) die "Unknown arg: $1  (try --help)" ;;
  esac
done

command -v docker >/dev/null 2>&1 || die "docker not found — install Docker to use the toolchain image"
docker info >/dev/null 2>&1        || die "docker daemon not reachable — is Docker running / are you in the docker group?"

log "Toolchain image : $IMAGE"
log "llama.cpp source: $SRC_DIR"
log "llama.cpp ref   : ${LLAMACPP_TAG:-master}"
log "Strip output    : $([[ $DO_STRIP == 1 ]] && echo yes || echo no)"

# ── source ──────────────────────────────────────────────────────────────────
if [[ "$CLEAN_ALL" == "1" ]]; then
  [[ -d "$SRC_DIR" ]] && { log "Removing $SRC_DIR"; rm -rf "$SRC_DIR"; }
fi

if [[ ! -d "$SRC_DIR/.git" ]]; then
  log "Cloning llama.cpp"
  if [[ -n "$LLAMACPP_TAG" ]]; then
    git clone --depth 1 --branch "$LLAMACPP_TAG" "$LLAMA_REPO" "$SRC_DIR"
  else
    git clone --depth 1 "$LLAMA_REPO" "$SRC_DIR"
  fi
else
  log "Reusing existing checkout at $SRC_DIR"
fi

[[ -f "$SRC_DIR/docs/backend/snapdragon/CMakeUserPresets.json" ]] || \
  die "This llama.cpp checkout has no Hexagon backend (docs/backend/snapdragon missing). Use a newer ref via --tag."

if [[ "$CLEAN" == "1" && -d "$SRC_DIR/$BUILD_DIR_NAME" ]]; then
  log "Cleaning $SRC_DIR/$BUILD_DIR_NAME"
  rm -rf "$SRC_DIR/$BUILD_DIR_NAME"
fi

[[ "$PULL" == "1" ]] && { log "Pulling toolchain image"; docker pull --platform linux/amd64 "$IMAGE"; }

# ── build inside the toolchain container ──────────────────────────────────────
# /workspace is bind-mounted to the source tree, so build-snapdragon/ and
# pkg-snapdragon/ land back on the host. The image ships ANDROID_NDK_ROOT,
# OPENCL_SDK_ROOT, HEXAGON_SDK_ROOT and HEXAGON_TOOLS_ROOT pre-set in its env;
# the CMake preset reads those.
log "Building (this can take a while; the image is multi-GB on first pull)"
docker run --rm \
  --platform linux/amd64 \
  -u "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e PRESET="$PRESET" \
  -e BUILD="$BUILD_DIR_NAME" \
  -e PKG="$PKG_DIR_NAME" \
  -e JOBS="$JOBS" \
  -e DO_STRIP="$DO_STRIP" \
  -v "$SRC_DIR":/workspace \
  -w /workspace \
  "$IMAGE" \
  bash -euo pipefail -c '
    git config --global --add safe.directory /workspace 2>/dev/null || true

    cp docs/backend/snapdragon/CMakeUserPresets.json .

    cmake --preset "$PRESET" -B "$BUILD"
    cmake --build "$BUILD" -j "$JOBS"

    rm -rf "$PKG"
    cmake --install "$BUILD" --prefix "$PKG/llama.cpp"

    if [ "$DO_STRIP" = "1" ]; then
      STRIP="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
      if [ -x "$STRIP" ]; then
        echo "==> Stripping aarch64 binaries and libraries"
        for f in "$PKG"/llama.cpp/bin/*; do
          [ -f "$f" ] && "$STRIP" --strip-all "$f" 2>/dev/null || true
        done
        for f in "$PKG"/llama.cpp/lib/*.so; do
          # Leave the Hexagon (HTP) kernel libs untouched — they are Hexagon
          # ELF objects loaded by FastRPC, not host aarch64 objects.
          case "$f" in
            *libggml-htp-*) : ;;
            *) "$STRIP" --strip-unneeded "$f" 2>/dev/null || true ;;
          esac
        done
      else
        echo "WARN: llvm-strip not found at $STRIP — skipping strip" >&2
      fi
    fi
  '

# ── package ───────────────────────────────────────────────────────────────────
PKG_PATH="$SRC_DIR/$PKG_DIR_NAME/llama.cpp"
[[ -d "$PKG_PATH/lib" ]] || die "Build did not produce $PKG_PATH/lib"

SUFFIX="${LLAMACPP_TAG:+-$LLAMACPP_TAG}"
TARBALL="$PROJECT_ROOT/llama-android-arm64-hexagon${SUFFIX}.tar.gz"
log "Packing $TARBALL"
tar -C "$PKG_PATH" -czf "$TARBALL" .
( cd "$PROJECT_ROOT" && sha256sum "$(basename "$TARBALL")" > "$(basename "$TARBALL").sha256" )

log "Done."
echo
echo "Package tree:"
( cd "$PKG_PATH" && find . -maxdepth 2 -type f | sort | sed 's/^/    /' )
echo
echo "Hexagon kernel libs present (auto-selected at runtime):"
ls -1 "$PKG_PATH/lib/" | grep 'libggml-htp-' | sed 's/^/    /' || true
echo
echo "Tarball: $TARBALL"
