#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

PREFIX="${PREFIX:-${HOME}/llama.cpp}"
INSTALL_DIR="${INSTALL_DIR:-}"
LIB_DIR="${LIB_DIR:-}"
BACKUP_DIR="${HOME}/.llama.cpp-bin-backup"
KEEP_BACKUP=0
DRY_RUN=0

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: uninstall.sh [options]

  --prefix D       Install prefix to remove (default: ${PREFIX})
  --install-dir D  Binary dir (default: <prefix>/bin)
  --lib-dir D      Library dir (default: <prefix>/lib)
  --keep-backup    Keep the revert backup at ${BACKUP_DIR}
  --dry-run        List what would be removed, delete nothing
  -h, --help       Show this help

Removes only files this installer creates (llama-* binaries, libggml*/libllama*/
libmtmd*/libomp libraries, version/variant markers) — safe to run even when the
dirs are shared with other tools.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)        PREFIX="$2"; shift 2 ;;
    --prefix=*)      PREFIX="${1#*=}"; shift ;;
    --install-dir)   INSTALL_DIR="$2"; shift 2 ;;
    --install-dir=*) INSTALL_DIR="${1#*=}"; shift ;;
    --lib-dir)       LIB_DIR="$2"; shift 2 ;;
    --lib-dir=*)     LIB_DIR="${1#*=}"; shift ;;
    --keep-backup)   KEEP_BACKUP=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) die "Unknown argument: $1  (try --help)" ;;
  esac
done

INSTALL_DIR="${INSTALL_DIR:-${PREFIX}/bin}"
LIB_DIR="${LIB_DIR:-${PREFIX}/lib}"

VERSION_FILE="${LIB_DIR}/llama-cpp.version"
VARIANT_FILE="${LIB_DIR}/llama-cpp.variant"

shopt -s nullglob

# ── report what's installed ───────────────────────────────────────────────────
tag="unknown"; var="unknown"
[[ -f "${VERSION_FILE}" ]] && tag=$(cat "${VERSION_FILE}")
[[ -f "${VARIANT_FILE}" ]] && var=$(cat "${VARIANT_FILE}")
log "Uninstalling llama.cpp (${tag}, variant: ${var})"
[[ "${DRY_RUN}" == "1" ]] && log "DRY RUN — nothing will be deleted"

# ── collect targets (only files we install) ───────────────────────────────────
bins=( "${INSTALL_DIR}"/llama-* )
libs=( "${LIB_DIR}"/libggml*.so "${LIB_DIR}"/libllama*.so "${LIB_DIR}"/libmtmd*.so "${LIB_DIR}"/libomp.so )
meta=( "${VERSION_FILE}" "${VARIANT_FILE}" )

removed=0
rm_one() {
  local f="$1"
  [[ -e "$f" || -L "$f" ]] || return 0
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '    remove %s\n' "$f"
  else
    rm -f "$f"
  fi
  removed=$((removed + 1))
}

prune_dir() {
  local d="$1"
  [[ -d "$d" ]] || return 0
  [[ -z "$(ls -A "$d" 2>/dev/null)" ]] || return 0   # leave non-empty dirs alone
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '    rmdir  %s (empty)\n' "$d"
  else
    rmdir "$d" 2>/dev/null || true
  fi
}

# ── remove ────────────────────────────────────────────────────────────────────
log "Binaries in ${INSTALL_DIR}"
for f in "${bins[@]}";  do rm_one "$f"; done

log "Libraries in ${LIB_DIR}"
for f in "${libs[@]}";  do rm_one "$f"; done
for f in "${meta[@]}";  do rm_one "$f"; done

if [[ "${KEEP_BACKUP}" == "0" && -d "${BACKUP_DIR}" ]]; then
  log "Backup ${BACKUP_DIR}"
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '    remove %s\n' "${BACKUP_DIR}"
  else
    rm -rf "${BACKUP_DIR}"
  fi
  removed=$((removed + 1))
fi

# clean up now-empty dirs (lib first, then bin, then the prefix itself)
prune_dir "${LIB_DIR}"
prune_dir "${INSTALL_DIR}"
prune_dir "${PREFIX}"

if [[ "${removed}" == "0" ]]; then
  warn "Nothing found to remove under ${PREFIX} (already uninstalled?)"
else
  log "Done — removed ${removed} item(s)."
fi

if [[ "${DRY_RUN}" != "1" ]]; then
  cat <<EOF

Note: remove the PATH / LD_LIBRARY_PATH / ADSP_LIBRARY_PATH lines you added to
~/.bashrc for ${PREFIX} if you no longer need them.
EOF
fi
