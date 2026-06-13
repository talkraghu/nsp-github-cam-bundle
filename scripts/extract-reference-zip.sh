#!/usr/bin/env bash
# #cursor generated code - start
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP="${1:-${ROOT}/reference/nsp-ne-backup-1.41.0.zip}"
DEST="${2:-${ROOT}/source-bundle}"

if [[ ! -f "${ZIP}" ]]; then
  echo "Reference zip not found: ${ZIP}" >&2
  echo "Copy nsp-ne-backup-1.41.0.zip into reference/ or pass path as first argument." >&2
  exit 1
fi

rm -rf "${DEST}"
mkdir -p "${DEST}"
unzip -q "${ZIP}" -d "${DEST}"
echo "Extracted ${ZIP} -> ${DEST}"
# #cursor generated code - end
