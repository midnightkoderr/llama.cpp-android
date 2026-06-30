#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

BASE_DIR="${HOME}/llama.cpp"
INSTALL_DIR="${BASE_DIR}/bin"
LIB_DIR="${BASE_DIR}/lib"
BACKUP_DIR="${HOME}/.llama.cpp-bin-backup"
KEEP_BACKUP=0
DRY_RUN=0

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: uninstall.sh [options]

  --keep-backup    Keep the revert backup at ${BACKUP_DIR}
  --dry-run        List what would be removed, delete nothing
  -h, --help       Show this help

Removes the install at ${BASE_DIR} (bin/ + lib/) and the revert backup.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-backup) KEEP_BACKUP=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) die "Unknown argument: $1  (try --help)" ;;
  esac
done

# ── report what's installed ───────────────────────────────────────────────────
tag="unknown"; var="unknown"
[[ -f "${LIB_DIR}/llama-cpp.version" ]] && tag=$(cat "${LIB_DIR}/llama-cpp.version")
[[ -f "${LIB_DIR}/llama-cpp.variant" ]] && var=$(cat "${LIB_DIR}/llama-cpp.variant")
log "Uninstalling llama.cpp (${tag}, variant: ${var}) from ${BASE_DIR}"
[[ "${DRY_RUN}" == "1" ]] && log "DRY RUN — nothing will be deleted"

removed=0
rm_path() {
  local p="$1"
  [[ -e "$p" || -L "$p" ]] || return 0
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '    remove %s\n' "$p"
  else
    rm -rf "$p"
  fi
  removed=$((removed + 1))
}

# bin/ and lib/ are created and owned by the installer — remove them wholesale.
rm_path "${INSTALL_DIR}"
rm_path "${LIB_DIR}"
[[ "${KEEP_BACKUP}" == "0" ]] && rm_path "${BACKUP_DIR}"

# remove the base dir only if nothing else (e.g. downloaded models) remains
if [[ -d "${BASE_DIR}" && -z "$(ls -A "${BASE_DIR}" 2>/dev/null)" ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '    rmdir  %s (empty)\n' "${BASE_DIR}"
  else
    rmdir "${BASE_DIR}" 2>/dev/null || true
  fi
elif [[ -d "${BASE_DIR}" ]]; then
  warn "Kept ${BASE_DIR} — it still contains other files"
fi

if [[ "${removed}" == "0" ]]; then
  warn "Nothing found to remove (already uninstalled?)"
else
  log "Done — removed ${removed} item(s)."
fi

if [[ "${DRY_RUN}" != "1" ]]; then
  cat <<EOF

Note: remove the PATH / LD_LIBRARY_PATH / ADSP_LIBRARY_PATH lines for
${BASE_DIR} from your ~/.bashrc if you no longer need them.
EOF
fi
