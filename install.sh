#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

REPO="${REPO:-midnightkoderr/llama.cpp-android}"
BASE_DIR="${HOME}/llama.cpp"
INSTALL_DIR="${BASE_DIR}/bin"
LIB_DIR="${BASE_DIR}/lib"
VARIANT="${VARIANT:-}"           # opencl | hexagon  (empty = auto: keep installed, else opencl)
UPDATE=0
REVERT=0

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: install.sh [options]

  --variant <v>    Backend variant: 'opencl' (Adreno GPU) or 'hexagon' (NPU + GPU + CPU)
  --opencl         Shorthand for --variant opencl (default for a fresh install)
  --hexagon        Shorthand for --variant hexagon
  --update         Update to the latest release (keeps the installed variant)
  --revert         Restore the previous version from backup
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant)       VARIANT="$2"; shift 2 ;;
    --variant=*)     VARIANT="${1#*=}"; shift ;;
    --opencl)        VARIANT="opencl"; shift ;;
    --hexagon|--npu) VARIANT="hexagon"; shift ;;
    --update)        UPDATE=1; shift ;;
    --revert)        REVERT=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) die "Unknown argument: $1  (try --help)" ;;
  esac
done

shopt -s nullglob

for t in curl tar; do
  command -v "$t" >/dev/null 2>&1 || die "Missing: ${t}"
done

VERSION_FILE="${LIB_DIR}/llama-cpp.version"
VARIANT_FILE="${LIB_DIR}/llama-cpp.variant"
BACKUP_DIR="${HOME}/.llama.cpp-bin-backup"

installed_variant() { [[ -f "${VARIANT_FILE}" ]] && cat "${VARIANT_FILE}" || echo ""; }

# Resolve which variant we're operating on:
#   explicit flag wins; else keep what's installed; else default to opencl.
if [[ -z "${VARIANT}" ]]; then
  VARIANT="$(installed_variant)"
  [[ -z "${VARIANT}" ]] && VARIANT="opencl"
fi
case "${VARIANT}" in
  opencl|hexagon) ;;
  *) die "Invalid --variant '${VARIANT}' (expected: opencl | hexagon)" ;;
esac

# ── revert ────────────────────────────────────────────────────────────────────
if [[ "${REVERT}" == "1" ]]; then
  [[ -d "${BACKUP_DIR}" ]] || die "No backup found in ${BACKUP_DIR} — nothing to revert to"
  prev="unknown"
  [[ -f "${BACKUP_DIR}/llama-cpp.version" ]] && prev=$(cat "${BACKUP_DIR}/llama-cpp.version")
  pvar="unknown"
  [[ -f "${BACKUP_DIR}/llama-cpp.variant" ]] && pvar=$(cat "${BACKUP_DIR}/llama-cpp.variant")
  log "Reverting to ${prev} (${pvar})"

  mkdir -p "${INSTALL_DIR}" "${LIB_DIR}"
  cp "${BACKUP_DIR}"/bin/* "${INSTALL_DIR}/" 2>/dev/null || die "Backup has no binaries"
  cp "${BACKUP_DIR}"/lib/*.so "${LIB_DIR}/" 2>/dev/null || true
  [[ -f "${BACKUP_DIR}/llama-cpp.version" ]] && cp "${BACKUP_DIR}/llama-cpp.version" "${VERSION_FILE}"
  [[ -f "${BACKUP_DIR}/llama-cpp.variant" ]] && cp "${BACKUP_DIR}/llama-cpp.variant" "${VARIANT_FILE}"
  chmod +x "${INSTALL_DIR}"/llama-* 2>/dev/null || true
  rm -rf "${BACKUP_DIR}"
  log "Reverted to ${prev} (${pvar})"
  exit 0
fi

# ── fetch release info ────────────────────────────────────────────────────────
log "Variant: ${VARIANT}"
log "Fetching latest release info for ${REPO}"
release=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")

tag=$(printf '%s' "${release}" | grep '"tag_name"' | head -n1 | sed 's/.*"tag_name": *"\(.*\)".*/\1/')
# Pick the .tar.gz asset whose name carries the requested variant (…-opencl-… / …-hexagon-…)
url=$(printf '%s' "${release}" | grep '"browser_download_url"' | grep '\.tar\.gz"' \
        | grep -- "-${VARIANT}-" | head -n1 | sed 's/.*"browser_download_url": *"\(.*\)".*/\1/')
sha_url=$(printf '%s' "${release}" | grep '"browser_download_url"' | grep '\.tar\.gz\.sha256"' \
        | grep -- "-${VARIANT}-" | head -n1 | sed 's/.*"browser_download_url": *"\(.*\)".*/\1/')

[[ -n "${tag}" ]] || die "Could not parse release tag — does the repo have any releases?"
[[ -n "${url}" ]] || die "No '${VARIANT}' .tar.gz asset in release ${tag}. Available variants may differ — try --variant opencl or --variant hexagon."

# ── update: version check + backup ───────────────────────────────────────────
if [[ "${UPDATE}" == "1" ]]; then
  current="none"; cur_var="$(installed_variant)"
  [[ -f "${VERSION_FILE}" ]] && current=$(cat "${VERSION_FILE}")
  if [[ "${current}" == "${tag}" && "${cur_var}" == "${VARIANT}" ]]; then
    log "Already up to date (${tag}, ${VARIANT})"
    exit 0
  fi
  log "Updating ${current} (${cur_var:-none}) → ${tag} (${VARIANT})"

  if [[ -f "${INSTALL_DIR}/llama-cli" ]]; then
    log "Backing up current install to ${BACKUP_DIR}"
    rm -rf "${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}/bin" "${BACKUP_DIR}/lib"
    for b in "${INSTALL_DIR}"/llama-*; do [[ -f "$b" ]] && cp "$b" "${BACKUP_DIR}/bin/"; done
    for l in "${LIB_DIR}"/*.so;     do [[ -f "$l" ]] && cp "$l" "${BACKUP_DIR}/lib/"; done
    [[ -f "${VERSION_FILE}" ]] && cp "${VERSION_FILE}" "${BACKUP_DIR}/"
    [[ -f "${VARIANT_FILE}" ]] && cp "${VARIANT_FILE}" "${BACKUP_DIR}/"
  fi
else
  log "Latest release: ${tag}"
fi

# ── download + install ────────────────────────────────────────────────────────
log "Downloading: $(basename "${url}")"

mkdir -p "${INSTALL_DIR}" "${LIB_DIR}"
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT

curl -fsSL --progress-bar "${url}" -o "${tmp}/llama.tar.gz"

# Optional checksum verification when the .sha256 asset and sha256sum are present
if [[ -n "${sha_url}" ]] && command -v sha256sum >/dev/null 2>&1; then
  log "Verifying checksum"
  curl -fsSL "${sha_url}" -o "${tmp}/llama.tar.gz.sha256"
  expected=$(awk '{print $1}' "${tmp}/llama.tar.gz.sha256")
  actual=$(sha256sum "${tmp}/llama.tar.gz" | awk '{print $1}')
  [[ "${expected}" == "${actual}" ]] || die "Checksum mismatch (expected ${expected}, got ${actual})"
fi

tar -xzf "${tmp}/llama.tar.gz" -C "${tmp}"

# Both variants ship the same layout: bin/<binaries> + lib/*.so .
[[ -d "${tmp}/bin" && -d "${tmp}/lib" ]] || die "Unexpected archive layout (no bin/ + lib/)"

# binaries → INSTALL_DIR (only llama-* — never .so or other files)
bins=( "${tmp}"/bin/llama-* )
[[ ${#bins[@]} -gt 0 ]] || die "No llama-* binaries found in archive"
cp "${bins[@]}" "${INSTALL_DIR}/"

# shared libs → LIB_DIR
libs=( "${tmp}"/lib/*.so )
[[ ${#libs[@]} -gt 0 ]] && cp "${libs[@]}" "${LIB_DIR}/"

chmod +x "${INSTALL_DIR}"/llama-* 2>/dev/null || true
printf '%s' "${tag}"     > "${VERSION_FILE}"
printf '%s' "${VARIANT}" > "${VARIANT_FILE}"

log "Binaries → ${INSTALL_DIR}:"
ls -lh "${INSTALL_DIR}"/llama-* 2>/dev/null || true
log "Libraries → ${LIB_DIR}:"
ls -lh "${LIB_DIR}"/*.so 2>/dev/null || true

# ── post-install help (variant-aware) ─────────────────────────────────────────
if [[ "${VARIANT}" == "hexagon" ]]; then
cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  llama.cpp ${tag} installed · variant: hexagon (NPU + GPU + CPU)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Add to ~/.bashrc (PATH for the binaries, plus the library paths —
ADSP_LIBRARY_PATH lets FastRPC find the HTP kernels):

  echo 'export PATH="${INSTALL_DIR}:\${PATH}"' >> ~/.bashrc
  echo 'export LD_LIBRARY_PATH="/vendor/lib64:${LIB_DIR}:${LD_LIBRARY_PATH:-}"' >> ~/.bashrc
  echo 'export ADSP_LIBRARY_PATH="${LIB_DIR}"'                  >> ~/.bashrc
  source ~/.bashrc

── NPU (Hexagon HTP) ────────────────────────────────────
  # 8 Gen 3 → Hexagon v75 · 7+ Gen 3 → Hexagon v73 (auto-selected)
  llama-cli -m model-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 -p "Hello"

  Best with Q4_0 / Q8_0 / MXFP4 weights. One NPU session maps ~3.5GB; for
  bigger models split: GGML_HEXAGON_NDEV=2 llama-cli ... --device HTP0,HTP1

── GPU (OpenCL / Adreno) ────────────────────────────────
  # the same package also ships the OpenCL backend
  taskset -c 2-7 llama-cli -m model.gguf -t 4 -ngl 28 -c 4096 -p "Hello"

── Server (OpenAI-compatible API) ───────────────────────
  llama-server -m model.gguf --host 0.0.0.0 --port 8080 --device HTP0 -ngl 99

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
else
cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  llama.cpp ${tag} installed · variant: opencl (GPU + CPU)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Add to ~/.bashrc (PATH for the binaries + library path for libomp.so):

  echo 'export PATH="${INSTALL_DIR}:\${PATH}"' >> ~/.bashrc
  echo 'export LD_LIBRARY_PATH="/vendor/lib64:${LIB_DIR}:${LD_LIBRARY_PATH:-}"' >> ~/.bashrc
  source ~/.bashrc

── CPU only ─────────────────────────────────────────────
  # SD 8 Gen 3 (6 P-cores: cpu2-7)
  taskset -c 2-7 llama-cli -m model.gguf -t 6 -ngl 0 -c 2048 -p "Hello"
  # SD 7+ Gen 3 (4 P-cores: cpu4-7)
  taskset -c 4-7 llama-cli -m model.gguf -t 4 -ngl 0 -c 2048 -p "Hello"

── GPU (OpenCL / Adreno) ────────────────────────────────
  # SD 8 Gen 3 — Adreno 750
  taskset -c 2-7 llama-cli -m model.gguf -t 4 -ngl 28 -c 4096 -p "Hello"
  # SD 7+ Gen 3 — Adreno 732
  taskset -c 4-7 llama-cli -m model.gguf -t 2 -ngl 28 -c 2048 -p "Hello"

  Start with -ngl 10 and increase until it slows or crashes.

── Server (OpenAI-compatible API) ───────────────────────
  llama-server -m model.gguf --host 0.0.0.0 --port 8080 -t 4 -ngl 28 -c 4096

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
fi
