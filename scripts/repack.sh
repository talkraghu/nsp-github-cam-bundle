#!/usr/bin/env bash
# #cursor generated code - start
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER_DIR="${ROOT}/builder"
INPUT_DIR="${ROOT}/source-bundle"
OUT_DIR="${ROOT}/dist"

UNSIGNED="${UNSIGNED:-1}"
AUTHOR="${AUTHOR:-ci}"
PK_FILE="${PK_FILE:-}"

mkdir -p "${OUT_DIR}"
rm -f "${BUILDER_DIR}"/*.zip "${OUT_DIR}"/*.zip
cd "${BUILDER_DIR}"
go build -o artifact-bundle-builder .

ARGS=( -input-bundle "${INPUT_DIR}" )
if [[ "${UNSIGNED}" == "1" ]]; then
  ARGS+=( -unsigned )
else
  ARGS+=( -author "${AUTHOR}" -pk-file "${PK_FILE}" )
fi

if [[ -n "${BUNDLE_VERSION_OVERRIDE:-}" ]]; then
  ARGS+=( -version "${BUNDLE_VERSION_OVERRIDE}" )
fi

./artifact-bundle-builder "${ARGS[@]}"
# Move produced zip (current dir is builder/) to dist/
shopt -s nullglob
for z in *.zip; do
  mv -f "${z}" "${OUT_DIR}/"
  echo "Wrote ${OUT_DIR}/${z}"
done
# #cursor generated code - end
