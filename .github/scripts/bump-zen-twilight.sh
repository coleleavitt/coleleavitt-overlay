#!/usr/bin/env bash
# Mirror Zen's mutable twilight-1 assets to an immutable overlay release and
# generate a timestamped www-client/zen-browser-bin ebuild.
set -euo pipefail

: "${PKG_CATEGORY:?PKG_CATEGORY is required}"
: "${PKG_NAME:?PKG_NAME is required}"
: "${VERSION:?VERSION is required}"
: "${CURRENT:?CURRENT is required}"
: "${MIRROR_REPOSITORY:?MIRROR_REPOSITORY is required}"

UPSTREAM_REPOSITORY="zen-browser/desktop"
UPSTREAM_TAG="twilight-1"
PKG_DIR="${PKG_CATEGORY}/${PKG_NAME}"
MIRROR_TAG="zen-browser-${VERSION}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

release_json() {
  gh api "repos/${UPSTREAM_REPOSITORY}/releases/tags/${UPSTREAM_TAG}"
}

asset_field() {
  local json=$1 name=$2 field=$3
  jq -er --arg name "${name}" --arg field "${field}" \
    '.assets[] | select(.name == $name) | .[$field]' <<<"${json}"
}

version_from_release() {
  local json=$1 base updated stamp
  base=$(jq -er '.name | capture("Twilight build - (?<version>[0-9]+\\.[0-9]+t)").version' <<<"${json}")
  updated=$(asset_field "${json}" "zen.linux-x86_64.tar.xz" "updated_at")
  stamp=$(date --utc --date="${updated}" +%Y%m%d%H%M%S)
  printf '%s_p%s\n' "${base}" "${stamp}"
}

echo "=== Mirroring ${UPSTREAM_REPOSITORY}:${UPSTREAM_TAG} as ${PKG_NAME}-${VERSION} ==="
initial_json=$(release_json)
detected_version=$(version_from_release "${initial_json}")
if [[ "${detected_version}" != "${VERSION}" ]]; then
  echo "ERROR: requested version ${VERSION} does not match current upstream ${detected_version}" >&2
  exit 1
fi

for arch in x86_64 aarch64; do
  asset="zen.linux-${arch}.tar.xz"
  url=$(asset_field "${initial_json}" "${asset}" "browser_download_url")
  echo "Downloading ${asset}"
  curl --fail --location --retry 3 --output "${WORK_DIR}/${asset}" "${url}"
done

# The upstream release is mutable. Refuse to publish if it changed while the
# two architecture assets were being downloaded.
final_json=$(release_json)
for asset in zen.linux-x86_64.tar.xz zen.linux-aarch64.tar.xz; do
  initial_id=$(asset_field "${initial_json}" "${asset}" "id")
  final_id=$(asset_field "${final_json}" "${asset}" "id")
  initial_updated=$(asset_field "${initial_json}" "${asset}" "updated_at")
  final_updated=$(asset_field "${final_json}" "${asset}" "updated_at")
  if [[ "${initial_id}:${initial_updated}" != "${final_id}:${final_updated}" ]]; then
    echo "ERROR: upstream ${asset} changed during download; retry on the next run" >&2
    exit 1
  fi
done

if [[ "${DRY_RUN:-false}" != "true" ]]; then
  if ! gh release view "${MIRROR_TAG}" --repo "${MIRROR_REPOSITORY}" >/dev/null 2>&1; then
    gh release create "${MIRROR_TAG}" \
      --repo "${MIRROR_REPOSITORY}" \
      --target "${GITHUB_SHA:-master}" \
      --title "Zen Twilight ${VERSION}" \
      --notes "Immutable mirror of Zen Twilight ${VERSION} from ${UPSTREAM_REPOSITORY}:${UPSTREAM_TAG}."
  fi
  gh release upload "${MIRROR_TAG}" \
    --repo "${MIRROR_REPOSITORY}" \
    --clobber \
    "${WORK_DIR}/zen.linux-x86_64.tar.xz" \
    "${WORK_DIR}/zen.linux-aarch64.tar.xz"
else
  echo "DRY_RUN=true: skipping mirror release creation/upload"
fi

cd "${PKG_DIR}"
TEMPLATE=$(find . -maxdepth 1 -type f \
  \( -name "${PKG_NAME}-${CURRENT}.ebuild" -o -name "${PKG_NAME}-${CURRENT}-r*.ebuild" \) \
  -printf '%f\n' | sort -V | tail -1)
if [[ -z "${TEMPLATE}" ]]; then
  TEMPLATE=$(find . -maxdepth 1 -type f -name "${PKG_NAME}-*.ebuild" -printf '%f\n' | sort -V | tail -1)
fi
if [[ -z "${TEMPLATE}" ]]; then
  echo "ERROR: no ${PKG_NAME} ebuild template found" >&2
  exit 1
fi

NEW_EBUILD="${PKG_NAME}-${VERSION}.ebuild"
cp "${TEMPLATE}" "${NEW_EBUILD}"
MIRROR_REPOSITORY_VALUE="${MIRROR_REPOSITORY}" python3 - "${NEW_EBUILD}" <<'PY'
from pathlib import Path
import os
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
repo = os.environ["MIRROR_REPOSITORY_VALUE"]
replacement = f'''ZEN_TWILIGHT_TAG="zen-browser-${{PV}}"
SRC_URI="
\tamd64? (
\t\thttps://github.com/{repo}/releases/download/${{ZEN_TWILIGHT_TAG}}/zen.linux-x86_64.tar.xz
\t\t-> ${{P}}-x86_64.tar.xz
\t)
\tarm64? (
\t\thttps://github.com/{repo}/releases/download/${{ZEN_TWILIGHT_TAG}}/zen.linux-aarch64.tar.xz
\t\t-> ${{P}}-aarch64.tar.xz
\t)
"'''
text, count = re.subn(r'ZEN_PV=.*?\nSRC_URI=".*?\n"', replacement, text, count=1, flags=re.DOTALL)
if count != 1:
    raise SystemExit("failed to replace stable SRC_URI block")
path.write_text(text)
PY

: > "${WORK_DIR}/new-dist-lines"
for arch in x86_64 aarch64; do
  source_file="${WORK_DIR}/zen.linux-${arch}.tar.xz"
  dist_file="${PKG_NAME}-${VERSION}-${arch}.tar.xz"
  size=$(stat -c%s "${source_file}")
  blake2b=$(b2sum "${source_file}" | awk '{print $1}')
  sha512=$(sha512sum "${source_file}" | awk '{print $1}')
  printf 'DIST %s %s BLAKE2B %s SHA512 %s\n' \
    "${dist_file}" "${size}" "${blake2b}" "${sha512}" >> "${WORK_DIR}/new-dist-lines"
done

_checksum_file() {
  local file=$1 type=$2 name=$3 size blake2b sha512
  size=$(stat -c%s "${file}")
  blake2b=$(b2sum "${file}" | awk '{print $1}')
  sha512=$(sha512sum "${file}" | awk '{print $1}')
  printf '%s %s %s BLAKE2B %s SHA512 %s\n' "${type}" "${name}" "${size}" "${blake2b}" "${sha512}"
}

: > "${WORK_DIR}/manifest-entries"
cat "${WORK_DIR}/new-dist-lines" >> "${WORK_DIR}/manifest-entries"
grep '^DIST ' Manifest >> "${WORK_DIR}/manifest-entries" 2>/dev/null || true
for file in *.ebuild; do
  _checksum_file "${file}" EBUILD "${file}" >> "${WORK_DIR}/manifest-entries"
done
for file in *.xml; do
  [[ -f "${file}" ]] && _checksum_file "${file}" MISC "${file}" >> "${WORK_DIR}/manifest-entries"
done
if [[ -d files ]]; then
  for file in files/*; do
    [[ -f "${file}" ]] && _checksum_file "${file}" AUX "$(basename "${file}")" >> "${WORK_DIR}/manifest-entries"
  done
fi
sort -t' ' -k1,1 -k2,2V -u "${WORK_DIR}/manifest-entries" > Manifest

echo "=== Done: ${PKG_DIR}/${NEW_EBUILD} (${MIRROR_TAG}) ==="
