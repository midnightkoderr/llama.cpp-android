#!/usr/bin/env bash
set -euo pipefail

ANDROID_NDK="${ANDROID_NDK:-}"
ANDROID_ABI="arm64-v8a"
ANDROID_API="30"
# Cortex-A78/A76/A77 + A55 (Dimensity 1200 and similar Armv8.2-A MediaTek
# chips) support dotprod + fp16, but NOT i8mm/bf16 — those are Armv8.6-A
# extensions first implemented in the Cortex-A710/X2 generation (2021+).
# opencl-gpu/build.sh's armv8.7a+i8mm+bf16 flags SIGILL on this hardware;
# this baseline is the safe subset for older/mid-range Armv8.2-A cores.
ARCH_FLAGS="-march=armv8.2-a+fp16+dotprod -O3 -flto=thin -ffunction-sections -fdata-sections"
LLAMA_REPO="https://github.com/ggml-org/llama.cpp.git"
SRC_DIR="${SRC_DIR:-$PWD/llama.cpp}"
BUILD_DIR="$SRC_DIR/build-android-mtk"
CLEAN=0
CLEAN_ALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)     CLEAN=1; shift ;;
    --clean-all) CLEAN_ALL=1; CLEAN=1; shift ;;
    --ndk)       ANDROID_NDK="$2"; shift 2 ;;
    --ndk=*)     ANDROID_NDK="${1#*=}"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -n "$ANDROID_NDK" ]] || die "Set ANDROID_NDK or pass --ndk /path/to/ndk"
[[ -f "$ANDROID_NDK/build/cmake/android.toolchain.cmake" ]] || die "android.toolchain.cmake not found under $ANDROID_NDK"

for t in cmake ninja git; do
  command -v "$t" >/dev/null 2>&1 || die "Missing: $t  (sudo apt install cmake ninja-build git)"
done

NDK_TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64"
LIBOMP="$(find "$NDK_TOOLCHAIN" -path '*aarch64/libomp.so' 2>/dev/null | head -n1 || true)"
[[ -n "$LIBOMP" ]] || die "aarch64 libomp.so not found under $NDK_TOOLCHAIN"

log "NDK:    $ANDROID_NDK"
log "libomp: $LIBOMP"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  log "Cloning llama.cpp"
  git clone --depth 1 "$LLAMA_REPO" "$SRC_DIR"
fi

if [[ "$CLEAN_ALL" == "1" ]]; then
  [[ -d "$BUILD_DIR" ]]                  && { log "Cleaning $BUILD_DIR";        rm -rf "$BUILD_DIR"; }
  [[ -d "$SRC_DIR/android-bin-mtk" ]]    && { log "Cleaning android-bin-mtk";   rm -rf "$SRC_DIR/android-bin-mtk"; }
elif [[ "$CLEAN" == "1" && -d "$BUILD_DIR" ]]; then
  log "Cleaning $BUILD_DIR"
  rm -rf "$BUILD_DIR"
fi

log "Configuring (CPU only)"
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ANDROID_ABI" \
  -DANDROID_PLATFORM="android-$ANDROID_API" \
  -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_OPENMP=ON \
  -DGGML_LLAMAFILE=ON \
  -DGGML_NATIVE=OFF \
  -DCMAKE_C_FLAGS="$ARCH_FLAGS" \
  -DCMAKE_CXX_FLAGS="$ARCH_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="-flto=thin -Wl,--gc-sections -Wl,--strip-all" \
  -DOpenMP_C_FLAGS="-fopenmp" \
  -DOpenMP_CXX_FLAGS="-fopenmp" \
  -DOpenMP_C_LIB_NAMES="omp" \
  -DOpenMP_CXX_LIB_NAMES="omp" \
  -DOpenMP_omp_LIBRARY="$LIBOMP" \
  -DLLAMA_CURL=OFF \
  -DBUILD_TESTING=OFF \
  -DLLAMA_BUILD_TESTS=OFF

# Same runtime tool set as the other variants.
BINS=(llama-cli llama-server llama-bench llama-quantize llama-mtmd-cli llama-gguf-split)

log "Building"
ninja -C "$BUILD_DIR" -j"$(nproc)" "${BINS[@]}"

LLVM_STRIP="$NDK_TOOLCHAIN/bin/llvm-strip"

OUT="$SRC_DIR/android-bin-mtk"
rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib"
for b in "${BINS[@]}"; do
  cp "$BUILD_DIR/bin/$b" "$OUT/bin/"
done
cp "$LIBOMP" "$OUT/lib/"

log "Stripping binaries"
for b in "${BINS[@]}"; do
  "$LLVM_STRIP" --strip-all "$OUT/bin/$b"
done
"$LLVM_STRIP" --strip-unneeded "$OUT/lib/libomp.so"

log "Done — package in $OUT"
find "$OUT" -type f | sort | sed 's/^/    /'
