#!/usr/bin/env bash
# bump-package.sh — Generic ebuild bump script for CI/CD
# Env vars expected:
#   PKG_CATEGORY    — e.g. media-libs
#   PKG_NAME        — e.g. mesa
#   VERSION         — new version
#   CURRENT         — current version (latest ebuild)
#   DOWNLOADS       — JSON array: [{"url":"...","filename":"..."}]
#   LLVM_ENABLED    — "true" or "false"
#   LLVM_MAX        — max LLVM slot (e.g. 22)
#   LLVM_MIN        — min LLVM slot (e.g. 18), for range-style LLVM_COMPAT
#   LLVM_STYLE      — "range" for {min..max} or "list" for explicit list
set -euo pipefail

PKG_DIR="${PKG_CATEGORY}/${PKG_NAME}"

echo "=== Bumping ${PKG_DIR} from ${CURRENT} to ${VERSION} ==="

cd "${PKG_DIR}"

# --- Find template ebuild ---
# Prefer current version, fall back to latest
TEMPLATE=""
for pattern in "${PKG_NAME}-${CURRENT}.ebuild" "${PKG_NAME}-${CURRENT}-r"*.ebuild; do
  if compgen -G "$pattern" >/dev/null 2>&1; then
    TEMPLATE=$(ls $pattern 2>/dev/null | sort -V | tail -1)
    break
  fi
done
if [ -z "$TEMPLATE" ]; then
  TEMPLATE=$(ls ${PKG_NAME}-*.ebuild 2>/dev/null | sort -V | tail -1)
fi
if [ -z "$TEMPLATE" ]; then
  echo "ERROR: No template ebuild found in ${PKG_DIR}"
  exit 1
fi

NEW_EBUILD="${PKG_NAME}-${VERSION}.ebuild"
echo "  Template: ${TEMPLATE} -> ${NEW_EBUILD}"
cp "${TEMPLATE}" "${NEW_EBUILD}"

# --- Update LLVM_COMPAT if needed ---
if [ "${LLVM_ENABLED}" = "true" ] && [ -n "${LLVM_MAX}" ]; then
  echo "  Updating LLVM_COMPAT (max=${LLVM_MAX}, min=${LLVM_MIN:-18}, style=${LLVM_STYLE:-range})"
  if [ "${LLVM_STYLE}" = "list" ]; then
    # Explicit list: LLVM_COMPAT=( 17 18 19 20 21 22 )
    LIST=$(seq "${LLVM_MIN:-17}" "${LLVM_MAX}" | tr '\n' ' ' | sed 's/ *$//')
    sed -i "s/LLVM_COMPAT=( [0-9 ]* )/LLVM_COMPAT=( ${LIST} )/" "${NEW_EBUILD}"
  else
    # Range: LLVM_COMPAT=( {18..22} )
    sed -i "s/LLVM_COMPAT=( {[0-9]*\.\.[0-9]*} )/LLVM_COMPAT=( {${LLVM_MIN:-18}..${LLVM_MAX}} )/" "${NEW_EBUILD}"
  fi
fi

# --- Compute EBUILD checksum ---
EBUILD_SIZE=$(stat -c%s "${NEW_EBUILD}")
EBUILD_BLAKE2B=$(b2sum "${NEW_EBUILD}" | awk '{print $1}')
EBUILD_SHA512=$(sha512sum "${NEW_EBUILD}" | awk '{print $1}')

echo "  EBUILD ${NEW_EBUILD} ${EBUILD_SIZE} bytes"

# --- Download distfiles and compute DIST checksums ---
DIST_LINES=""
echo "${DOWNLOADS}" | jq -c '.[]' | while read -r entry; do
  URL=$(echo "$entry" | jq -r '.url' | sed "s/{VERSION}/${VERSION}/g")
  FILENAME=$(echo "$entry" | jq -r '.filename' | sed "s/{VERSION}/${VERSION}/g")

  echo "  Downloading: ${FILENAME}"
  wget -q -O "/tmp/${FILENAME}" "${URL}"

  SIZE=$(stat -c%s "/tmp/${FILENAME}")
  BLAKE2B=$(b2sum "/tmp/${FILENAME}" | awk '{print $1}')
  SHA512=$(sha512sum "/tmp/${FILENAME}" | awk '{print $1}')

  echo "DIST ${FILENAME} ${SIZE} BLAKE2B ${BLAKE2B} SHA512 ${SHA512}" >> /tmp/new_dist_lines.txt
  rm -f "/tmp/${FILENAME}"
done

# --- Update Manifest ---
echo "  Updating Manifest"

# Build new Manifest: keep existing entries, add new ones
{
  # New EBUILD entry
  echo "EBUILD ${NEW_EBUILD} ${EBUILD_SIZE} BLAKE2B ${EBUILD_BLAKE2B} SHA512 ${EBUILD_SHA512}"
  # Existing EBUILD entries (excluding new version if re-running)
  grep "^EBUILD" Manifest 2>/dev/null | grep -v "${NEW_EBUILD}" || true
  # New DIST entries
  cat /tmp/new_dist_lines.txt 2>/dev/null || true
  # Existing DIST entries (keep all — dedup handles overlaps)
  grep "^DIST" Manifest 2>/dev/null || true
  # MISC entries (metadata.xml etc)
  grep "^MISC" Manifest 2>/dev/null || true
  # AUX entries (patches etc)
  grep "^AUX" Manifest 2>/dev/null || true
} | sort -t' ' -k1,1 -k2,2V -u > Manifest.new

mv Manifest.new Manifest
rm -f /tmp/new_dist_lines.txt

echo "=== Done: ${PKG_DIR}-${VERSION} ==="
