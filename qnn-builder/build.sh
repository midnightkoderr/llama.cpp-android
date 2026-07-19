#!/usr/bin/env bash
# Build the QNN-SDK and/or Hexagon-NPU-FastRPC Android backends from
# chraac/llama-cpp-qnn-builder — a separate builder wrapping chraac's own
# llama.cpp fork (dev-refactoring branch), distinct from the official
# ggml-hexagon backend already built by ../hexagon-npu/build.sh.
#
# The whole build runs inside chraac's own Docker images (they already bundle
# the Android NDK, the Qualcomm QNN SDK, and — for the hexagon flavor — the
# Hexagon SDK), mirroring exactly what that repo's own CI does
# (.github/workflows/build_and_run_tests.yml, jobs build-android-qnn and
# build-android-hexagon-npu). The host only needs Docker; it's an x86_64-only
# cross-compile targeting android arm64-v8a.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SRC_DIR:-$PROJECT_ROOT/llama-cpp-qnn-builder}"

BUILDER_REPO="${BUILDER_REPO:-https://github.com/chraac/llama-cpp-qnn-builder.git}"
BUILDER_TAG="${BUILDER_TAG:-}"   # empty = default branch (main)
FLAVOR="both"                    # qnn | hexagon | both
PULL=0
CLEAN=0
CLEAN_ALL=0

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [options]

  --flavor <qnn|hexagon|both>  Which backend(s) to build (default: both)
  --tag <ref>                  Build a specific llama-cpp-qnn-builder branch/tag/commit (default: main)
  --pull                       docker pull the latest builder images before building
  --clean                      Remove this flavor's build output dir before building
  --clean-all                  Remove the cloned source (and build output), then re-clone
  -h, --help                   Show this help

Env overrides: SRC_DIR, BUILDER_REPO, BUILDER_TAG

Output:
  qnn-builder/llama-android-arm64-qnn-sdk[-<tag>].tar.gz             (QNN SDK backend)
  qnn-builder/llama-android-arm64-qnn-hexagon-fastrpc[-<tag>].tar.gz (Hexagon NPU FastRPC backend)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flavor)    FLAVOR="$2"; shift 2 ;;
    --flavor=*)  FLAVOR="${1#*=}"; shift ;;
    --tag)       BUILDER_TAG="$2"; shift 2 ;;
    --tag=*)     BUILDER_TAG="${1#*=}"; shift ;;
    --pull)      PULL=1; shift ;;
    --clean)     CLEAN=1; shift ;;
    --clean-all) CLEAN_ALL=1; CLEAN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) die "Unknown arg: $1  (try --help)" ;;
  esac
done

case "$FLAVOR" in
  qnn)     FLAVORS=(qnn) ;;
  hexagon) FLAVORS=(hexagon) ;;
  both)    FLAVORS=(qnn hexagon) ;;
  *) die "--flavor must be qnn, hexagon, or both (got: $FLAVOR)" ;;
esac

command -v docker >/dev/null 2>&1 || die "docker not found — install Docker to use the builder images"
docker info >/dev/null 2>&1        || die "docker daemon not reachable — is Docker running / are you in the docker group?"
command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1 || \
  die "docker compose not found (need either the 'docker-compose' binary or the 'docker compose' plugin)"

log "Builder repo : $BUILDER_REPO"
log "Builder ref  : ${BUILDER_TAG:-<default branch>}"
log "Source dir   : $SRC_DIR"
log "Flavor(s)    : ${FLAVORS[*]}"

# ── source ──────────────────────────────────────────────────────────────────
if [[ "$CLEAN_ALL" == "1" && -d "$SRC_DIR" ]]; then
  log "Removing $SRC_DIR"
  rm -rf "$SRC_DIR"
fi

if [[ ! -d "$SRC_DIR/.git" ]]; then
  log "Cloning $BUILDER_REPO"
  git clone --recurse-submodules "$BUILDER_REPO" "$SRC_DIR"
else
  log "Reusing existing checkout at $SRC_DIR"
fi

if [[ -n "$BUILDER_TAG" ]]; then
  log "Checking out $BUILDER_TAG"
  git -C "$SRC_DIR" fetch --depth 1 origin "$BUILDER_TAG"
  git -C "$SRC_DIR" checkout FETCH_HEAD
fi

log "Syncing submodules"
git -C "$SRC_DIR" submodule update --init --recursive

[[ -x "$SRC_DIR/docker/docker_compose_compile.sh" ]] || \
  die "docker/docker_compose_compile.sh not found in $SRC_DIR — unexpected repo layout"

if [[ "$PULL" == "1" ]]; then
  log "Pulling latest builder images"
  ( cd "$SRC_DIR/docker" && docker compose -f docker-compose-compile.yml pull ) || true
  ( cd "$SRC_DIR/docker" && docker compose -f docker-compose-compile-qnn.yml pull ) || true
fi

BUILD_OUT_DIR="$SRC_DIR/build_qnn_arm64-v8a"
SUFFIX="${BUILDER_TAG:+-$BUILDER_TAG}"

build_flavor() {
  local flavor="$1" flags="$2" tarball_name="$3"

  if [[ "$CLEAN" == "1" || -d "$BUILD_OUT_DIR" ]]; then
    log "[$flavor] Clearing stale output dir (avoids mixing with a prior flavor's build)"
    rm -rf "$BUILD_OUT_DIR"
  fi

  log "[$flavor] Building (Release) — this can take a while on first pull"
  ( cd "$SRC_DIR" && ./docker/docker_compose_compile.sh -r $flags )

  [[ -d "$BUILD_OUT_DIR" ]] || die "[$flavor] Build did not produce $BUILD_OUT_DIR"

  local pkg_dir="$PROJECT_ROOT/pkg-$flavor"
  rm -rf "$pkg_dir"
  mkdir -p "$pkg_dir"
  cp -a "$BUILD_OUT_DIR/." "$pkg_dir/"

  local tarball="$PROJECT_ROOT/${tarball_name}${SUFFIX}.tar.gz"
  log "[$flavor] Packing $tarball"
  tar -C "$pkg_dir" -czf "$tarball" .
  ( cd "$PROJECT_ROOT" && sha256sum "$(basename "$tarball")" > "$(basename "$tarball").sha256" )

  echo
  echo "[$flavor] Package contents:"
  ( cd "$pkg_dir" && find . -maxdepth 1 -type f | sort | sed 's/^/    /' )
  echo
  echo "[$flavor] Tarball: $tarball"
}

for flavor in "${FLAVORS[@]}"; do
  case "$flavor" in
    qnn)
      build_flavor qnn "--qnn-only --disable-ggml-hexagon" "llama-android-arm64-qnn-sdk"
      ;;
    hexagon)
      build_flavor hexagon "--hexagon-npu-only --enable-dequant --disable-ggml-hexagon" "llama-android-arm64-qnn-hexagon-fastrpc"
      ;;
  esac
done

log "Done."
