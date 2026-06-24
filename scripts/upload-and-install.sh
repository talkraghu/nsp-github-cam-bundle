#!/usr/bin/env bash
# #cursor generated code - start
set -euo pipefail

# Optional: UPLOAD_INSTALL_DEBUG=1 or DEBUG=1 or ACTIONS_STEP_DEBUG=true for extra stderr logs.
# Never prints CAM_TOKEN value.

_dbg() {
  if [[ "${UPLOAD_INSTALL_DEBUG:-}" == "1" || "${DEBUG:-}" == "1" || "${ACTIONS_STEP_DEBUG:-}" == "true" ]]; then
    echo "[upload-and-install][debug] $*" >&2
  fi
}

_log() {
  echo "[upload-and-install] $*" >&2
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

# GitHub Actions (self-hosted lab): Schannel curl often hits (60) on private CAs.
# Default NSP_TLS_INSECURE=1 when unset or empty so no extra repo secret is required.
# Set NSP_TLS_INSECURE=0 in the job env to enforce TLS verification.
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  if [[ -z "${NSP_TLS_INSECURE:-}" ]]; then
    NSP_TLS_INSECURE=1
    export NSP_TLS_INSECURE
    _log "GITHUB_ACTIONS: NSP_TLS_INSECURE unset; defaulting to 1 (curl --insecure, lab only). Set NSP_TLS_INSECURE=0 to verify."
  fi
fi

# Git Bash on Windows: prefer Git-bundled curl (usr/bin or mingw64/bin). Plain
# Windows System32 curl.exe uses Schannel and often fails (26) on MSYS paths for
# multipart file= and (60) on private lab CAs unless trusted.
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

# Upload a bundle ZIP to NSP file service (CAM bundle dir), or skip upload if the ZIP
# is already on cluster storage, then request CAM batch install.
#
# Required env (export them, or put them in repo-root .env -- file is gitignored):
#   NSP_BASE_URL       e.g. https://100.120.90.89
#   CAM_TOKEN          Bearer token value (without "Bearer " prefix)
#
# Optional:
#   SKIP_FILE_SERVICE_UPLOAD  defaults to 1 (skip REST upload) because many lab setups manually
#                             preload the ZIP under /nokia/nsp/cam/artifacts/bundle/ on file-service storage.
#                             Set SKIP_FILE_SERVICE_UPLOAD=0 to enable REST upload from this script.
#                             When skipping upload, set BUNDLE_FILE_NAME or keep a local zip for naming only.
#                             Install defaults to v3 only unless CAM_REST_API_VERSION is set.
#   BUNDLE_ZIP              path to zip (default: dist/nsp-ne-backup-*.zip first match); not required when
#                             SKIP_FILE_SERVICE_UPLOAD=1 if BUNDLE_FILE_NAME is set
#   FS_UPLOAD_PATH          default /nsp-file-service-app/rest/api/v1/file/uploadFile (ignored when skip upload)
#   CAM_BASE_PATH           default /cam
#   CAM_REST_API_VERSION    if set, install uses only this (e.g. v2). If unset and skip upload, v3 only; else v3 v2 v1.
#   BUNDLE_FILE_NAME        server bundle zip name (e.g. nsp-ne-backup-1.41.0.zip) when no local zip
#   CURL_CONNECT_TIMEOUT    seconds (default 30)
#   CURL_MAX_TIME           seconds for whole transfer (default 600)
#   NSP_TLS_INSECURE        1 = curl --insecure (lab). On GitHub Actions, defaults to 1 if unset/empty. Use 0 to verify TLS.
#   CURL_CA_BUNDLE          PEM path for curl --cacert (corporate CA)
#   UPLOAD_INSTALL_DEBUG    set to 1 (or DEBUG=1) for extra stderr logs (never logs CAM_TOKEN)
#   Windows: multipart file=@ uses cygpath -w when cygpath exists (MinGW curl + /c/...)

NSP_BASE_URL="${NSP_BASE_URL:?Set NSP_BASE_URL in .env or environment (e.g. https://lab-ip)}"
CAM_TOKEN="${CAM_TOKEN:?Set CAM_TOKEN in .env or environment (JWT without Bearer prefix)}"
FS_UPLOAD_PATH="${FS_UPLOAD_PATH:-/nsp-file-service-app/rest/api/v1/file/uploadFile}"
CAM_BASE_PATH="${CAM_BASE_PATH:-/cam}"
SKIP_FILE_SERVICE_UPLOAD="${SKIP_FILE_SERVICE_UPLOAD:-1}"
if [[ -n "${CAM_REST_API_VERSION:-}" ]]; then
  _install_versions=("${CAM_REST_API_VERSION}")
elif [[ "${SKIP_FILE_SERVICE_UPLOAD}" == "1" ]]; then
  _install_versions=(v3)
  _log "SKIP_FILE_SERVICE_UPLOAD=1: install REST limited to v3 (set CAM_REST_API_VERSION to use another version only)"
else
  _install_versions=(v3 v2 v1)
fi
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-30}"
CURL_MAX_TIME="${CURL_MAX_TIME:-600}"

if [[ "${SKIP_FILE_SERVICE_UPLOAD}" == "1" ]]; then
  _log "SKIP_FILE_SERVICE_UPLOAD=1: not calling file service upload API (bundle must already be on volume, e.g. .../nokia/nsp/cam/artifacts/bundle/)"
  if [[ -n "${BUNDLE_FILE_NAME:-}" ]]; then
    NAME="${BUNDLE_FILE_NAME}"
  elif [[ -n "${BUNDLE_ZIP:-}" && -f "${BUNDLE_ZIP}" ]]; then
    ZIP="${BUNDLE_ZIP}"
    NAME="$(basename "${ZIP}")"
    _log "bundle name from BUNDLE_ZIP: ${NAME}"
  else
    ZIP="$(ls -1 "${ROOT}"/dist/*.zip 2>/dev/null | head -1 || true)"
    if [[ -n "${ZIP}" && -f "${ZIP}" ]]; then
      NAME="$(basename "${ZIP}")"
      _log "bundle name from dist zip: ${NAME}"
    else
      _log "ERROR: SKIP_FILE_SERVICE_UPLOAD=1 needs BUNDLE_FILE_NAME (e.g. nsp-ne-backup-1.41.0.zip) or a local BUNDLE_ZIP/dist zip for naming"
      exit 1
    fi
  fi
  _log "expecting file on file service: /nokia/nsp/cam/artifacts/bundle/${NAME}"
else
  if [[ -n "${BUNDLE_ZIP:-}" ]]; then
    ZIP="${BUNDLE_ZIP}"
  else
    ZIP="$(ls -1 "${ROOT}"/dist/*.zip 2>/dev/null | head -1 || true)"
  fi
  [[ -n "${ZIP}" && -f "${ZIP}" ]] || { _log "ERROR: no bundle zip; set BUNDLE_ZIP or run scripts/repack.sh"; exit 1; }
  NAME="${BUNDLE_FILE_NAME:-$(basename "${ZIP}")}"
  _zip_bytes="$(wc -c < "${ZIP}" 2>/dev/null | tr -d ' ' || echo 0)"
  _log "bundle file: path=${ZIP} bytes=${_zip_bytes} readable=$([[ -r "${ZIP}" ]] && echo yes || echo no)"
  _dbg "$(ls -la "${ZIP}" 2>/dev/null || true)"
  _dbg "dist dir: $(ls -la "${ROOT}/dist" 2>/dev/null || echo '<missing>')"
fi

# createDirectory=true: file service returns 404 if dirName does not exist (DIR_NOT_EXIST).
UPLOAD_URL="${NSP_BASE_URL}${FS_UPLOAD_PATH}?dirName=/nokia/nsp/cam/artifacts/bundle&overwrite=true&createDirectory=true"

_log "config: NSP_BASE_URL=${NSP_BASE_URL}"
_log "config: SKIP_FILE_SERVICE_UPLOAD=${SKIP_FILE_SERVICE_UPLOAD} CAM_BASE_PATH=${CAM_BASE_PATH} FS_UPLOAD_PATH=${FS_UPLOAD_PATH} CAM_REST_API_VERSION=${CAM_REST_API_VERSION:-<auto: ${_install_versions[*]}>}"
_log "config: CURL_CONNECT_TIMEOUT=${CURL_CONNECT_TIMEOUT}s CURL_MAX_TIME=${CURL_MAX_TIME}s"
_log "config: NSP_TLS_INSECURE=${NSP_TLS_INSECURE:-<unset>} CURL_CA_BUNDLE=${CURL_CA_BUNDLE:-<unset>}"
_log "auth: CAM_TOKEN length=${#CAM_TOKEN} characters (value not logged)"

CURL_OPTS=( -sS -f --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" )
if [[ "${NSP_TLS_INSECURE:-}" == "1" ]]; then
  CURL_OPTS+=( --insecure )
fi
if [[ -n "${CURL_CA_BUNDLE:-}" ]]; then
  CURL_OPTS+=( --cacert "${CURL_CA_BUNDLE}" )
fi
_dbg "CURL_OPTS count=${#CURL_OPTS[@]} args: ${CURL_OPTS[*]}"

BODY=$(printf '{"bundles":["%s"]}' "${NAME}")
_log "install JSON body: ${BODY}"

if [[ "${SKIP_FILE_SERVICE_UPLOAD}" != "1" ]]; then
  # MinGW / Schannel curl needs a Windows path for multipart file=@... (curl 26 on /c/...).
  ZIP_UPLOAD="${ZIP}"
  if command -v cygpath >/dev/null 2>&1; then
    if [[ "${_us}" == MINGW* || "${_us}" == MSYS* || "${OSTYPE:-}" == msys* ]]; then
      _zipw="$(cygpath -w "${ZIP}" 2>/dev/null || true)"
      if [[ -n "${_zipw}" ]]; then
        ZIP_UPLOAD="${_zipw}"
        _log "multipart upload file path (cygpath -w): ${ZIP_UPLOAD}"
        _dbg "original ZIP path: ${ZIP}"
      fi
    fi
  fi

  _log "uploading file as NAME=${NAME} (response body snippet up to 400 chars on stdout)"
  _log "POST ${UPLOAD_URL}"
  set +o pipefail
  set +e
  "${CURL_EXE}" "${CURL_OPTS[@]}" -X POST "${UPLOAD_URL}" \
    -H "Authorization: Bearer ${CAM_TOKEN}" \
    -F "file=@${ZIP_UPLOAD};filename=${NAME}" \
    -F "dirName=/nokia/nsp/cam/artifacts/bundle" \
    -F "overwrite=true" \
    | head -c 400 || true
  _up_stat=("${PIPESTATUS[@]}")
  set -e
  set -o pipefail
  _log "upload curl pipe: curl_exit=${_up_stat[0]:-?} head_exit=${_up_stat[1]:-?}"
  echo
else
  _log "skipping file service POST (SKIP_FILE_SERVICE_UPLOAD=1)"
  echo
fi

_log "POST install (expect HTTP 2xx from one of: ${_install_versions[*]}; body on stdout)"
_in_ec=1
for _ver in "${_install_versions[@]}"; do
  INSTALL_URL="${NSP_BASE_URL}${CAM_BASE_PATH}/rest/api/${_ver}/artifactBundle/install"
  _log "install try REST ${_ver}: ${INSTALL_URL}"
  set +e
  "${CURL_EXE}" "${CURL_OPTS[@]}" -X POST "${INSTALL_URL}" \
    -H "Authorization: Bearer ${CAM_TOKEN}" \
    -H "Accept: application/json, application/problem+json" \
    -H "Content-Type: application/json" \
    -d "${BODY}"
  _in_ec=$?
  set -e
  _log "install ${_ver} curl exit=${_in_ec}"
  if [[ "${_in_ec}" -eq 0 ]]; then
    break
  fi
done
[[ "${_in_ec}" -eq 0 ]]
echo
_log "finished OK"
# #cursor generated code - end
