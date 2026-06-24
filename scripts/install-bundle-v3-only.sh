#!/usr/bin/env bash
# #cursor generated code - start
set -euo pipefail

# Install-only helper for preloaded bundles.
# Calls only CAM v3 artifact bundle install API.

_dbg() {
  if [[ "${UPLOAD_INSTALL_DEBUG:-}" == "1" || "${DEBUG:-}" == "1" || "${ACTIONS_STEP_DEBUG:-}" == "true" ]]; then
    echo "[install-bundle-v3-only][debug] $*" >&2
  fi
}

_log() {
  echo "[install-bundle-v3-only] $*" >&2
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_log "starting (ROOT=${ROOT})"
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ROOT}/.env"
  set +a
  _dbg "sourced ${ROOT}/.env"
fi

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  if [[ -z "${NSP_TLS_INSECURE:-}" ]]; then
    NSP_TLS_INSECURE=1
    export NSP_TLS_INSECURE
    _log "GITHUB_ACTIONS: NSP_TLS_INSECURE unset; defaulting to 1 (curl --insecure, lab only). Set NSP_TLS_INSECURE=0 to verify."
  fi
fi

_us="$(uname -s 2>/dev/null || true)"
CURL_EXE=curl
if [[ "${_us}" == MINGW* || "${_us}" == MSYS* || "${_us}" == CYGWIN* || "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
  for _curl_dir in \
    "/c/Program Files/Git/usr/bin" \
    "/c/Program Files (x86)/Git/usr/bin" \
    "/c/Program Files/Git/mingw64/bin" \
    "/c/Program Files (x86)/Git/mingw64/bin"; do
    if [[ -x "${_curl_dir}/curl.exe" ]]; then
      CURL_EXE="${_curl_dir}/curl.exe"
      PATH="${_curl_dir}:${PATH}"
      export PATH
      _log "selected Git curl: ${CURL_EXE}"
      break
    fi
  done
  if [[ "${CURL_EXE}" == "curl" ]]; then
    _log "NOTE: Git curl.exe not found under usr/bin or mingw64/bin; using PATH curl"
  fi
fi

_log "uname: $(uname -a 2>/dev/null || echo unknown)"
_log "OSTYPE=${OSTYPE:-} BASH_VERSION=${BASH_VERSION:-}"
if command -v "${CURL_EXE}" >/dev/null 2>&1; then
  _log "curl resolved: $(command -v "${CURL_EXE}")"
  _log "curl version: $("${CURL_EXE}" --version 2>/dev/null | head -1 || echo unknown)"
else
  _log "WARNING: cannot resolve CURL_EXE='${CURL_EXE}' via command -v"
fi
_dbg "PATH(first entries)=$(echo "${PATH}" | tr ':' '\n' | head -10)"

NSP_BASE_URL="${NSP_BASE_URL:?Set NSP_BASE_URL in .env or environment (e.g. https://lab-ip)}"
CAM_TOKEN="${CAM_TOKEN:?Set CAM_TOKEN in .env or environment (JWT without Bearer prefix)}"
BUNDLE_FILE_NAME="${BUNDLE_FILE_NAME:?Set BUNDLE_FILE_NAME (e.g. nsp-ne-backup-1.41.0.zip)}"
CAM_BASE_PATH="${CAM_BASE_PATH:-/cam}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-30}"
CURL_MAX_TIME="${CURL_MAX_TIME:-600}"

_log "config: NSP_BASE_URL=${NSP_BASE_URL}"
_log "config: CAM_BASE_PATH=${CAM_BASE_PATH} BUNDLE_FILE_NAME=${BUNDLE_FILE_NAME}"
_log "config: CURL_CONNECT_TIMEOUT=${CURL_CONNECT_TIMEOUT}s CURL_MAX_TIME=${CURL_MAX_TIME}s"
_log "config: NSP_TLS_INSECURE=${NSP_TLS_INSECURE:-<unset>} CURL_CA_BUNDLE=${CURL_CA_BUNDLE:-<unset>}"
_log "auth: CAM_TOKEN length=${#CAM_TOKEN} characters (value not logged)"
_log "precondition: bundle file is already present on file-service path /nokia/nsp/cam/artifacts/bundle/${BUNDLE_FILE_NAME}"

CURL_OPTS=( -sS -f --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" )
if [[ "${NSP_TLS_INSECURE:-}" == "1" ]]; then
  CURL_OPTS+=( --insecure )
fi
if [[ -n "${CURL_CA_BUNDLE:-}" ]]; then
  CURL_OPTS+=( --cacert "${CURL_CA_BUNDLE}" )
fi
_dbg "CURL_OPTS count=${#CURL_OPTS[@]} args: ${CURL_OPTS[*]}"

BODY=$(printf '{"bundles":["%s"]}' "${BUNDLE_FILE_NAME}")
INSTALL_URL="${NSP_BASE_URL}${CAM_BASE_PATH}/rest/api/v3/artifactBundle/install"
_log "install JSON body: ${BODY}"
_log "POST install v3: ${INSTALL_URL}"

"${CURL_EXE}" "${CURL_OPTS[@]}" -X POST "${INSTALL_URL}" \
  -H "Authorization: Bearer ${CAM_TOKEN}" \
  -H "Accept: application/json, application/problem+json" \
  -H "Content-Type: application/json" \
  -d "${BODY}"

echo
_log "finished OK"
# #cursor generated code - end
