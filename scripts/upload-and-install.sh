#!/usr/bin/env bash
# #cursor generated code - start
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ROOT}/.env"
  set +a
fi

# Upload a bundle ZIP to NSP file service (CAM bundle dir) then request CAM install.
#
# Required env (export them, or put them in repo-root .env -- file is gitignored):
#   NSP_BASE_URL       e.g. https://100.120.90.89
#   CAM_TOKEN          Bearer token value (without "Bearer " prefix)
#
# Optional:
#   BUNDLE_ZIP              path to zip (default: dist/nsp-ne-backup-*.zip first match)
#   FS_UPLOAD_PATH          default /nsp-file-service-app/rest/api/v1/file/uploadFile (file service is not versioned under CAM v3)
#   CAM_BASE_PATH           default /cam
#   CAM_REST_API_VERSION    default v3 (CAM batch install). Use v1 or v2 if your cluster has no v3 surface yet.
#   BUNDLE_FILE_NAME        override zip basename on server (default: basename of BUNDLE_ZIP)
#   CURL_CONNECT_TIMEOUT    seconds (default 30)
#   CURL_MAX_TIME           seconds for whole transfer (default 600)

NSP_BASE_URL="${NSP_BASE_URL:?Set NSP_BASE_URL in .env or environment (e.g. https://lab-ip)}"
CAM_TOKEN="${CAM_TOKEN:?Set CAM_TOKEN in .env or environment (JWT without Bearer prefix)}"
FS_UPLOAD_PATH="${FS_UPLOAD_PATH:-/nsp-file-service-app/rest/api/v1/file/uploadFile}"
CAM_BASE_PATH="${CAM_BASE_PATH:-/cam}"
CAM_REST_API_VERSION="${CAM_REST_API_VERSION:-v3}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-30}"
CURL_MAX_TIME="${CURL_MAX_TIME:-600}"
if [[ -n "${BUNDLE_ZIP:-}" ]]; then
  ZIP="${BUNDLE_ZIP}"
else
  ZIP="$(ls -1 "${ROOT}"/dist/*.zip 2>/dev/null | head -1 || true)"
fi
[[ -n "${ZIP}" && -f "${ZIP}" ]] || { echo "No bundle zip; set BUNDLE_ZIP or run scripts/repack.sh" >&2; exit 1; }

NAME="${BUNDLE_FILE_NAME:-$(basename "${ZIP}")}"
UPLOAD_URL="${NSP_BASE_URL}${FS_UPLOAD_PATH}?dirName=/nokia/nsp/cam/artifacts/bundle&overwrite=true"

echo "Uploading ${ZIP} as ${NAME} ..."
curl -sS -f --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" -X POST "${UPLOAD_URL}" \
  -H "Authorization: Bearer ${CAM_TOKEN}" \
  -F "file=@${ZIP};filename=${NAME}" \
  -F "dirName=/nokia/nsp/cam/artifacts/bundle" \
  -F "overwrite=true" \
  | head -c 400 || true
echo

INSTALL_URL="${NSP_BASE_URL}${CAM_BASE_PATH}/rest/api/${CAM_REST_API_VERSION}/artifactBundle/install"
BODY=$(printf '{"bundles":["%s"]}' "${NAME}")

echo "Requesting install: POST ${INSTALL_URL}"
curl -sS -f --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" -X POST "${INSTALL_URL}" \
  -H "Authorization: Bearer ${CAM_TOKEN}" \
  -H "Accept: application/json, application/problem+json" \
  -H "Content-Type: application/json" \
  -d "${BODY}"
echo
# #cursor generated code - end
