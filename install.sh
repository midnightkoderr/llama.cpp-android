#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

REPO="${REPO:-midnightkoderr/llama.cpp-android}"
VARIANTS=(opencl hexagon)
UPDATE=0
REVERT=0
UNINSTALL=0
KEEP_BACKUP=0
DRY_RUN=0
BACKUP=0
BACKUP_FILE=""
RESTORE=0
RESTORE_FILE=""

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: install.sh [options]

Installs both variants side by side (no need to choose one):
  ${HOME}/llama.cpp-opencl/   CPU + OpenCL (Adreno GPU)
  ${HOME}/llama.cpp-hexagon/  CPU + OpenCL + Hexagon NPU (HTP)

  --update           Update both to the latest release
  --revert           Restore both from their backups
  --uninstall        Remove both installs (and their backups)
  --keep-backup      With --uninstall, keep the revert backups
  --dry-run          With --uninstall, list what would be removed, delete nothing
  --backup [file]    Zip both installs (+ ~/.alias) into one archive
                     (default: ~/llama-cpp-backup-<timestamp>.zip)
  --restore <file>   Restore both installs (+ ~/.alias) from a --backup archive
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)      UPDATE=1; shift ;;
    --revert)      REVERT=1; shift ;;
    --uninstall)   UNINSTALL=1; shift ;;
    --keep-backup) KEEP_BACKUP=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --backup)
      BACKUP=1
      if [[ $# -ge 2 && "$2" != -* ]]; then BACKUP_FILE="$2"; shift 2; else shift; fi
      ;;
    --restore)
      RESTORE=1
      [[ $# -ge 2 ]] || die "--restore requires a path to a backup zip"
      RESTORE_FILE="$2"; shift 2
      ;;
    -h|--help)     usage; exit 0 ;;
    *) die "Unknown argument: $1  (try --help)" ;;
  esac
done

shopt -s nullglob

for t in curl tar; do
  command -v "$t" >/dev/null 2>&1 || die "Missing: ${t}"
done

dir_for()    { printf '%s/llama.cpp-%s' "${HOME}" "$1"; }
backup_for() { printf '%s/.llama.cpp-bin-backup-%s' "${HOME}" "$1"; }

# ── uninstall ─────────────────────────────────────────────────────────────────
if [[ "${UNINSTALL}" == "1" ]]; then
  [[ "${DRY_RUN}" == "1" ]] && log "DRY RUN — nothing will be deleted"

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

  removed=0
  for VARIANT in "${VARIANTS[@]}"; do
    BASE_DIR="$(dir_for "${VARIANT}")"
    INSTALL_DIR="${BASE_DIR}/bin"
    LIB_DIR="${BASE_DIR}/lib"
    BACKUP_DIR="$(backup_for "${VARIANT}")"

    if [[ ! -d "${BASE_DIR}" ]]; then
      warn "${VARIANT}: not installed — skipping"
      continue
    fi

    tag="unknown"
    [[ -f "${LIB_DIR}/llama-cpp.version" ]] && tag=$(cat "${LIB_DIR}/llama-cpp.version")
    log "Uninstalling ${VARIANT} (${tag}) from ${BASE_DIR}"

    rm_path "${INSTALL_DIR}"
    rm_path "${LIB_DIR}"
    [[ "${KEEP_BACKUP}" == "0" ]] && rm_path "${BACKUP_DIR}"

    if [[ -d "${BASE_DIR}" && -z "$(ls -A "${BASE_DIR}" 2>/dev/null)" ]]; then
      if [[ "${DRY_RUN}" == "1" ]]; then
        printf '    rmdir  %s (empty)\n' "${BASE_DIR}"
      else
        rmdir "${BASE_DIR}" 2>/dev/null || true
      fi
    elif [[ -d "${BASE_DIR}" ]]; then
      warn "Kept ${BASE_DIR} — it still contains other files"
    fi
  done

  if [[ "${removed}" == "0" ]]; then
    warn "Nothing found to remove (already uninstalled?)"
  else
    log "Done — removed ${removed} item(s)."
  fi

  if [[ "${DRY_RUN}" != "1" ]]; then
    cat <<EOF

Note: remove the llama-*-npu / llama-*-gpu alias lines (and the
'. ~/.alias' line) from ~/.bashrc if you no longer need them.
EOF
  fi
  exit 0
fi

# ── backup ────────────────────────────────────────────────────────────────────
if [[ "${BACKUP}" == "1" ]]; then
  command -v zip >/dev/null 2>&1 || die "Missing: zip  (install with: pkg install zip)"
  [[ -n "${BACKUP_FILE}" ]] || BACKUP_FILE="${HOME}/llama-cpp-backup-$(date +%Y%m%d-%H%M%S).zip"

  items=()
  for VARIANT in "${VARIANTS[@]}"; do
    d="llama.cpp-${VARIANT}"
    [[ -d "${HOME}/${d}" ]] && items+=("${d}")
  done
  [[ -f "${HOME}/.alias" ]] && items+=(".alias")
  [[ ${#items[@]} -gt 0 ]] || die "Nothing installed to back up"

  log "Backing up: ${items[*]}"
  ( cd "${HOME}" && zip -rq "${BACKUP_FILE}" "${items[@]}" )
  log "Backup written to ${BACKUP_FILE}"
  exit 0
fi

# ── restore ───────────────────────────────────────────────────────────────────
if [[ "${RESTORE}" == "1" ]]; then
  command -v unzip >/dev/null 2>&1 || die "Missing: unzip  (install with: pkg install unzip)"
  [[ -f "${RESTORE_FILE}" ]] || die "Backup file not found: ${RESTORE_FILE}"

  log "Restoring ${RESTORE_FILE} into ${HOME}"
  unzip -oq "${RESTORE_FILE}" -d "${HOME}"

  for VARIANT in "${VARIANTS[@]}"; do
    BASE_DIR="$(dir_for "${VARIANT}")"
    [[ -d "${BASE_DIR}/bin" ]] && chmod +x "${BASE_DIR}/bin"/llama-* 2>/dev/null || true
  done
  log "Restore complete."
  exit 0
fi

# ── revert ────────────────────────────────────────────────────────────────────
if [[ "${REVERT}" == "1" ]]; then
  for VARIANT in "${VARIANTS[@]}"; do
    BASE_DIR="$(dir_for "${VARIANT}")"
    INSTALL_DIR="${BASE_DIR}/bin"
    LIB_DIR="${BASE_DIR}/lib"
    BACKUP_DIR="$(backup_for "${VARIANT}")"

    if [[ ! -d "${BACKUP_DIR}" ]]; then
      warn "${VARIANT}: no backup found in ${BACKUP_DIR} — skipping"
      continue
    fi

    prev="unknown"
    [[ -f "${BACKUP_DIR}/llama-cpp.version" ]] && prev=$(cat "${BACKUP_DIR}/llama-cpp.version")
    log "${VARIANT}: reverting to ${prev}"

    mkdir -p "${INSTALL_DIR}" "${LIB_DIR}"
    cp "${BACKUP_DIR}"/bin/* "${INSTALL_DIR}/" 2>/dev/null || die "${VARIANT}: backup has no binaries"
    cp "${BACKUP_DIR}"/lib/*.so "${LIB_DIR}/" 2>/dev/null || true
    [[ -f "${BACKUP_DIR}/llama-cpp.version" ]] && cp "${BACKUP_DIR}/llama-cpp.version" "${LIB_DIR}/llama-cpp.version"
    chmod +x "${INSTALL_DIR}"/llama-* 2>/dev/null || true
    rm -rf "${BACKUP_DIR}"
    log "${VARIANT}: reverted to ${prev}"
  done
  exit 0
fi

# ── fetch release info (once, shared by both variants) ────────────────────────
log "Fetching latest release info for ${REPO}"
release=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")
tag=$(printf '%s' "${release}" | grep '"tag_name"' | head -n1 | sed 's/.*"tag_name": *"\(.*\)".*/\1/')
[[ -n "${tag}" ]] || die "Could not parse release tag — does the repo have any releases?"
log "Latest release: ${tag}"

for VARIANT in "${VARIANTS[@]}"; do
  BASE_DIR="$(dir_for "${VARIANT}")"
  INSTALL_DIR="${BASE_DIR}/bin"
  LIB_DIR="${BASE_DIR}/lib"
  VERSION_FILE="${LIB_DIR}/llama-cpp.version"
  BACKUP_DIR="$(backup_for "${VARIANT}")"

  url=$(printf '%s' "${release}" | grep '"browser_download_url"' | grep '\.tar\.gz"' \
          | grep -- "-${VARIANT}-" | head -n1 | sed 's/.*"browser_download_url": *"\(.*\)".*/\1/')
  sha_url=$(printf '%s' "${release}" | grep '"browser_download_url"' | grep '\.tar\.gz\.sha256"' \
          | grep -- "-${VARIANT}-" | head -n1 | sed 's/.*"browser_download_url": *"\(.*\)".*/\1/')
  [[ -n "${url}" ]] || die "No '${VARIANT}' .tar.gz asset in release ${tag}"

  if [[ "${UPDATE}" == "1" ]]; then
    current="none"
    [[ -f "${VERSION_FILE}" ]] && current=$(cat "${VERSION_FILE}")
    if [[ "${current}" == "${tag}" ]]; then
      log "${VARIANT}: already up to date (${tag})"
      continue
    fi
    log "${VARIANT}: updating ${current} → ${tag}"
    if [[ -f "${INSTALL_DIR}/llama-cli" ]]; then
      rm -rf "${BACKUP_DIR}"
      mkdir -p "${BACKUP_DIR}/bin" "${BACKUP_DIR}/lib"
      for b in "${INSTALL_DIR}"/llama-*; do [[ -f "$b" ]] && cp "$b" "${BACKUP_DIR}/bin/"; done
      for l in "${LIB_DIR}"/*.so;     do [[ -f "$l" ]] && cp "$l" "${BACKUP_DIR}/lib/"; done
      [[ -f "${VERSION_FILE}" ]] && cp "${VERSION_FILE}" "${BACKUP_DIR}/"
    fi
  fi

  log "${VARIANT}: downloading $(basename "${url}")"
  mkdir -p "${INSTALL_DIR}" "${LIB_DIR}"
  tmp=$(mktemp -d)

  curl -fsSL --progress-bar "${url}" -o "${tmp}/llama.tar.gz"

  if [[ -n "${sha_url}" ]] && command -v sha256sum >/dev/null 2>&1; then
    curl -fsSL "${sha_url}" -o "${tmp}/llama.tar.gz.sha256"
    expected=$(awk '{print $1}' "${tmp}/llama.tar.gz.sha256")
    actual=$(sha256sum "${tmp}/llama.tar.gz" | awk '{print $1}')
    [[ "${expected}" == "${actual}" ]] || die "${VARIANT}: checksum mismatch (expected ${expected}, got ${actual})"
  fi

  tar -xzf "${tmp}/llama.tar.gz" -C "${tmp}"
  [[ -d "${tmp}/bin" && -d "${tmp}/lib" ]] || die "${VARIANT}: unexpected archive layout (no bin/ + lib/)"

  bins=( "${tmp}"/bin/llama-* )
  [[ ${#bins[@]} -gt 0 ]] || die "${VARIANT}: no llama-* binaries found in archive"
  cp "${bins[@]}" "${INSTALL_DIR}/"

  libs=( "${tmp}"/lib/*.so )
  [[ ${#libs[@]} -gt 0 ]] && cp "${libs[@]}" "${LIB_DIR}/"

  chmod +x "${INSTALL_DIR}"/llama-* 2>/dev/null || true
  printf '%s' "${tag}" > "${VERSION_FILE}"
  rm -rf "${tmp}"

  log "${VARIANT}: installed → ${BASE_DIR}"
done

OPENCL_DIR="$(dir_for opencl)"
HEXAGON_DIR="$(dir_for hexagon)"

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  llama.cpp ${tag} installed — both variants, side by side
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${OPENCL_DIR}   CPU + OpenCL (Adreno GPU)
  ${HEXAGON_DIR}  CPU + OpenCL + Hexagon NPU (HTP)

Add to ~/.alias (create it if it doesn't exist), then source it from
~/.bashrc with '. ~/.alias':

  alias llama-cli-npu="LD_LIBRARY_PATH=${HEXAGON_DIR}/lib ADSP_LIBRARY_PATH=${HEXAGON_DIR}/lib ${HEXAGON_DIR}/bin/llama-cli"
  alias llama-server-npu="LD_LIBRARY_PATH=${HEXAGON_DIR}/lib ADSP_LIBRARY_PATH=${HEXAGON_DIR}/lib ${HEXAGON_DIR}/bin/llama-server"
  alias llama-cli-gpu="LD_LIBRARY_PATH=${OPENCL_DIR}/lib ${OPENCL_DIR}/bin/llama-cli"
  alias llama-server-gpu="LD_LIBRARY_PATH=${OPENCL_DIR}/lib ${OPENCL_DIR}/bin/llama-server"

  echo '. ~/.alias' >> ~/.bashrc
  . ~/.bashrc

── NPU (Hexagon HTP) ────────────────────────────────────
  # 8 Gen 3 → Hexagon v75 · 7+ Gen 3 → Hexagon v73 (auto-selected)
  llama-cli-npu -m model-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 -p "Hello"

── GPU (OpenCL / Adreno) ────────────────────────────────
  taskset -c 2-7 llama-cli-gpu -m model.gguf -t 4 -ngl 28 -c 4096 -p "Hello"

── Server (OpenAI-compatible API) ───────────────────────
  llama-server-npu -m model.gguf --host 0.0.0.0 --port 8080 --device HTP0 -ngl 99
  llama-server-gpu -m model.gguf --host 0.0.0.0 --port 8080 -t 4 -ngl 28 -c 4096

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
