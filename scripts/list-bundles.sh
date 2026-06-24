#!/usr/bin/env bash
# #cursor generated code - start
set -euo pipefail

_dbg() {
  if [[ "${UPLOAD_INSTALL_DEBUG:-}" == "1" || "${DEBUG:-}" == "1" || "${ACTIONS_STEP_DEBUG:-}" == "true" ]]; then
    echo "[list-bundles][debug] $*" >&2
  fi
}

_log() {
  echo "[list-bundles] $*" >&2
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
fi

NSP_BASE_URL="${NSP_BASE_URL:?Set NSP_BASE_URL in .env or environment (e.g. https://lab-ip)}"
CAM_TOKEN="${CAM_TOKEN:?Set CAM_TOKEN in .env or environment (JWT without Bearer prefix)}"
CAM_BASE_PATH="${CAM_BASE_PATH:-/cam}"
if [[ -n "${CAM_REST_API_VERSION:-}" ]]; then
  _list_versions=("${CAM_REST_API_VERSION}")
else
  _list_versions=(v3 v2 v1)
fi
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-30}"
CURL_MAX_TIME="${CURL_MAX_TIME:-600}"

CURL_OPTS=( -sS -f --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" )
if [[ "${NSP_TLS_INSECURE:-}" == "1" ]]; then
  CURL_OPTS+=( --insecure )
fi
if [[ -n "${CURL_CA_BUNDLE:-}" ]]; then
  CURL_OPTS+=( --cacert "${CURL_CA_BUNDLE}" )
fi

_log "config: NSP_BASE_URL=${NSP_BASE_URL}"
_log "config: CAM_BASE_PATH=${CAM_BASE_PATH} CAM_REST_API_VERSION=${CAM_REST_API_VERSION:-<auto: ${_list_versions[*]}>}"
_log "config: CURL_CONNECT_TIMEOUT=${CURL_CONNECT_TIMEOUT}s CURL_MAX_TIME=${CURL_MAX_TIME}s"
_log "config: NSP_TLS_INSECURE=${NSP_TLS_INSECURE:-<unset>} CURL_CA_BUNDLE=${CURL_CA_BUNDLE:-<unset>}"
_log "auth: CAM_TOKEN length=${#CAM_TOKEN} characters (value not logged)"

_ls_ec=1
for _ver in "${_list_versions[@]}"; do
  LIST_URL="${NSP_BASE_URL}${CAM_BASE_PATH}/rest/api/${_ver}/artifactBundle/"
  _log "GET list bundles try REST ${_ver}: ${LIST_URL}"
  set +e
  RESPONSE="$("${CURL_EXE}" "${CURL_OPTS[@]}" -X GET "${LIST_URL}" \
    -H "Authorization: Bearer ${CAM_TOKEN}" \
    -H "Accept: application/json, application/problem+json")"
  _ls_ec=$?
  set -e
  _log "list ${_ver} curl exit=${_ls_ec}"
  if [[ "${_ls_ec}" -eq 0 ]]; then
    echo "${RESPONSE}"
    break
  fi
done

[[ "${_ls_ec}" -eq 0 ]]
echo
_log "finished OK"
# #cursor generated code - end
