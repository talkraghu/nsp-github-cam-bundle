#!/usr/bin/env bash
# #cursor generated code - start
set -euo pipefail

# Optional: UPLOAD_INSTALL_DEBUG=1 or DEBUG=1 or ACTIONS_STEP_DEBUG=true for extra stderr logs.
# Never prints CAM_TOKEN value.

_dbg() {
  if [[ "${UPLOAD_INSTALL_DEBUG:-}" == "1" || "${DEBUG:-}" == "1" || "${ACTIONS_STEP_DEBUG:-}" == "true" ]]; then
    echo "[uninstall-bundle][debug] $*" >&2
  fi
}

_log() {
  echo "[uninstall-bundle] $*" >&2
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

# Batch uninstall: POST JSON {"bundles":["<zip-basename>"]} to CAM artifactBundle API.
# v3 path suffix is lowercase "uninstall"; v1/v2 use camelCase "unInstall" (see cam-server-app controllers).
#
# Required:
#   NSP_BASE_URL
#   CAM_TOKEN
#   BUNDLE_FILE_NAME   e.g. nsp-ne-backup-1.41.0.zip (must match bundle on the cluster)
#
# Optional:
#   CAM_BASE_PATH           default /cam
#   CAM_REST_API_VERSION    if set, only that version is tried. If unset, tries v3 then v2 then v1.
#   CURL_CONNECT_TIMEOUT    default 30
#   CURL_MAX_TIME             default 600
#   NSP_TLS_INSECURE          1 = curl --insecure (lab)
#   CURL_CA_BUNDLE
#   UPLOAD_INSTALL_DEBUG

NSP_BASE_URL="${NSP_BASE_URL:?Set NSP_BASE_URL in .env or environment (e.g. https://lab-ip)}"
CAM_TOKEN="${CAM_TOKEN:?Set CAM_TOKEN in .env or environment (JWT without Bearer prefix)}"
BUNDLE_FILE_NAME="${BUNDLE_FILE_NAME:?Set BUNDLE_FILE_NAME (e.g. nsp-ne-backup-1.41.0.zip)}"
CAM_BASE_PATH="${CAM_BASE_PATH:-/cam}"
if [[ -n "${CAM_REST_API_VERSION:-}" ]]; then
  _uninstall_versions=("${CAM_REST_API_VERSION}")
else
  _uninstall_versions=(v3 v2 v1)
fi
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-30}"
CURL_MAX_TIME="${CURL_MAX_TIME:-600}"

BODY=$(printf '{"bundles":["%s"]}' "${BUNDLE_FILE_NAME}")

_log "config: NSP_BASE_URL=${NSP_BASE_URL}"
_log "config: CAM_BASE_PATH=${CAM_BASE_PATH} BUNDLE_FILE_NAME=${BUNDLE_FILE_NAME} CAM_REST_API_VERSION=${CAM_REST_API_VERSION:-<auto: ${_uninstall_versions[*]}>}"
_log "config: CURL_CONNECT_TIMEOUT=${CURL_CONNECT_TIMEOUT}s CURL_MAX_TIME=${CURL_MAX_TIME}s"
_log "config: NSP_TLS_INSECURE=${NSP_TLS_INSECURE:-<unset>} CURL_CA_BUNDLE=${CURL_CA_BUNDLE:-<unset>}"
_log "auth: CAM_TOKEN length=${#CAM_TOKEN} characters (value not logged)"
_log "uninstall JSON body: ${BODY}"

CURL_OPTS=( -sS -f --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" )
if [[ "${NSP_TLS_INSECURE:-}" == "1" ]]; then
  CURL_OPTS+=( --insecure )
fi
if [[ -n "${CURL_CA_BUNDLE:-}" ]]; then
  CURL_OPTS+=( --cacert "${CURL_CA_BUNDLE}" )
fi
_dbg "CURL_OPTS count=${#CURL_OPTS[@]} args: ${CURL_OPTS[*]}"

_in_ec=1
for _ver in "${_uninstall_versions[@]}"; do
  if [[ "${_ver}" == "v3" ]]; then
    _path_suffix="uninstall"
  else
    _path_suffix="unInstall"
  fi
  UNINSTALL_URL="${NSP_BASE_URL}${CAM_BASE_PATH}/rest/api/${_ver}/artifactBundle/${_path_suffix}"
  _log "POST uninstall try REST ${_ver}: ${UNINSTALL_URL}"
  set +e
  "${CURL_EXE}" "${CURL_OPTS[@]}" -X POST "${UNINSTALL_URL}" \
    -H "Authorization: Bearer ${CAM_TOKEN}" \
    -H "Accept: application/json, application/problem+json" \
    -H "Content-Type: application/json" \
    -d "${BODY}"
  _in_ec=$?
  set -e
  _log "uninstall ${_ver} curl exit=${_in_ec}"
  if [[ "${_in_ec}" -eq 0 ]]; then
    break
  fi
done
[[ "${_in_ec}" -eq 0 ]]
echo
_log "finished OK"
# #cursor generated code - end
