#!/usr/bin/env bash
set -euo pipefail

ANDROID_NDK="${ANDROID_NDK:-}"
ANDROID_ABI="arm64-v8a"
ANDROID_API="34"
ARCH_FLAGS="-march=armv8.6-a+i8mm+bf16+dotprod -O3 -flto=thin -ffunction-sections -fdata-sections"
LLAMA_REPO="https://github.com/ggml-org/llama.cpp.git"
SRC_DIR="${SRC_DIR:-$PWD/llama.cpp}"
BUILD_DIR="$SRC_DIR/build-android"
USE_OPENCL=0
CLEAN=0
CLEAN_ALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --opencl)    USE_OPENCL=1; shift ;;
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
[[ "$USE_OPENCL" == "1" ]] && log "OpenCL: enabled" || log "OpenCL: disabled"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  log "Cloning llama.cpp"
  git clone --depth 1 "$LLAMA_REPO" "$SRC_DIR"
fi

OPENCL_CMAKE_ARGS=()
if [[ "$USE_OPENCL" == "1" ]]; then
  OCL_INSTALL="$SRC_DIR/opencl-install"
  OCL_BUILD="$SRC_DIR/opencl-build"
  mkdir -p "$OCL_BUILD"

  # CMake's FindOpenCL finds host headers (detects version) but then searches
  # host library paths for libOpenCL.so — which only has x86_64 builds, not
  # aarch64. Fix: cross-compile the KhronosGroup ICD Loader for Android and
  # pass the path explicitly so FindOpenCL never falls back to system search.
  if [[ ! -f "$OCL_INSTALL/lib/libOpenCL.so" ]]; then
    log "Building OpenCL headers + ICD loader"
    [[ -d "$OCL_BUILD/OpenCL-Headers" ]] || \
      git clone --depth 1 https://github.com/KhronosGroup/OpenCL-Headers    "$OCL_BUILD/OpenCL-Headers"
    [[ -d "$OCL_BUILD/OpenCL-ICD-Loader" ]] || \
      git clone --depth 1 https://github.com/KhronosGroup/OpenCL-ICD-Loader "$OCL_BUILD/OpenCL-ICD-Loader"

    # Headers are installed for the host — only needed at compile time
    cmake -S "$OCL_BUILD/OpenCL-Headers" -B "$OCL_BUILD/headers-build" \
      -DCMAKE_INSTALL_PREFIX="$OCL_INSTALL" -DBUILD_TESTING=OFF >/dev/null
    cmake --install "$OCL_BUILD/headers-build" >/dev/null

    # ICD Loader is cross-compiled for aarch64 using the NDK toolchain
    cmake -S "$OCL_BUILD/OpenCL-ICD-Loader" -B "$OCL_BUILD/icd-build" -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$ANDROID_ABI" \
      -DANDROID_PLATFORM="android-$ANDROID_API" \
      -DCMAKE_INSTALL_PREFIX="$OCL_INSTALL" \
      -DCMAKE_PREFIX_PATH="$OCL_INSTALL" \
      -DOPENCL_ICD_LOADER_HEADERS_DIR="$OCL_INSTALL/include" \
      -DBUILD_TESTING=OFF
    cmake --build "$OCL_BUILD/icd-build" --target install
    log "Cleaning opencl-build temp files"
    rm -rf "$OCL_BUILD"
  fi

  # Explicit paths bypass FindOpenCL's system search entirely
  OPENCL_CMAKE_ARGS=(
    -DGGML_OPENCL=ON
    -DCMAKE_PREFIX_PATH="$OCL_INSTALL"
    -DOpenCL_LIBRARY="$OCL_INSTALL/lib/libOpenCL.so"
    -DOpenCL_INCLUDE_DIR="$OCL_INSTALL/include"
  )
fi

if [[ "$CLEAN_ALL" == "1" ]]; then
  [[ -d "$BUILD_DIR" ]]            && { log "Cleaning $BUILD_DIR";            rm -rf "$BUILD_DIR"; }
  [[ -d "$SRC_DIR/opencl-install" ]] && { log "Cleaning opencl-install";       rm -rf "$SRC_DIR/opencl-install"; }
  [[ -d "$SRC_DIR/opencl-build" ]]   && { log "Cleaning opencl-build";         rm -rf "$SRC_DIR/opencl-build"; }
  [[ -d "$SRC_DIR/android-bin" ]]    && { log "Cleaning android-bin";          rm -rf "$SRC_DIR/android-bin"; }
elif [[ "$CLEAN" == "1" && -d "$BUILD_DIR" ]]; then
  log "Cleaning $BUILD_DIR"
  rm -rf "$BUILD_DIR"
fi

log "Configuring"
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
  -DLLAMA_BUILD_TESTS=OFF \
  "${OPENCL_CMAKE_ARGS[@]}"

log "Building"
ninja -C "$BUILD_DIR" -j"$(nproc)" llama-cli llama-server

LLVM_STRIP="$NDK_TOOLCHAIN/bin/llvm-strip"

OUT="$SRC_DIR/android-bin"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$BUILD_DIR/bin/llama-cli" "$BUILD_DIR/bin/llama-server" "$OUT/"
cp "$LIBOMP" "$OUT/"

log "Stripping binaries"
"$LLVM_STRIP" --strip-all       "$OUT/llama-cli" "$OUT/llama-server"
"$LLVM_STRIP" --strip-unneeded  "$OUT/libomp.so"

log "Done — binaries in $OUT"
ls -lh "$OUT"
