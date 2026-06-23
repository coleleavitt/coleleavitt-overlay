#!/usr/bin/env bash
# bump-cursor.sh — Bump app-editors/cursor from upstream Cursor release data.
#
# Cursor's SRC_URI is keyed on BOTH the version (PV) and the build commit
# (BUILD_ID / commitSha), so the generic bump-package.sh can't handle it.
# This script clones the latest ebuild, rewrites BUILD_ID + renames to the
# new PV, downloads both arch .deb files, and regenerates the Manifest.
#
# Env vars expected:
#   PKG_CATEGORY    — app-editors
#   PKG_NAME        — cursor
#   VERSION         — new version, e.g. 3.8.22
#   CURRENT         — current local version (for template selection)
#   BUILD_ID        — upstream commitSha for the new version
set -euo pipefail

PKG_DIR="${PKG_CATEGORY}/${PKG_NAME}"
NEW_EBUILD="${PKG_NAME}-${VERSION}.ebuild"

echo "=== Bumping ${PKG_DIR} to ${VERSION} (build ${BUILD_ID}) ==="

cd "${PKG_DIR}"

# --- Find template ebuild (latest existing) ---
TEMPLATE=""
if ls ${PKG_NAME}-*.ebuild 1>/dev/null 2>&1; then
  TEMPLATE=$(ls ${PKG_NAME}-*.ebuild | sort -V | tail -1)
fi
if [ -z "$TEMPLATE" ]; then
  echo "ERROR: No template ebuild found in ${PKG_DIR}"
  exit 1
fi

echo "  Template: ${TEMPLATE} -> ${NEW_EBUILD}"
cp "${TEMPLATE}" "${NEW_EBUILD}"

# --- Rewrite BUILD_ID (the upstream commit sha) ---
sed -i "s/^BUILD_ID=\"[^\"]*\"/BUILD_ID=\"${BUILD_ID}\"/" "${NEW_EBUILD}"
echo "  Set BUILD_ID=\"${BUILD_ID}\""

# --- Drop stale ebuilds (keep only the new one) ---
for old in ${PKG_NAME}-*.ebuild; do
  [ "$old" = "${NEW_EBUILD}" ] && continue
  rm -f "$old"
  echo "  Removed stale: ${old}"
done

# --- Download distfiles and compute DIST checksums ---
: > /tmp/cursor_manifest_entries.txt

declare -A DISTFILES=(
  ["${PKG_NAME}-${VERSION}-amd64.deb"]="https://downloads.cursor.com/production/${BUILD_ID}/linux/x64/deb/amd64/deb/cursor_${VERSION}_amd64.deb"
  ["${PKG_NAME}-${VERSION}-arm64.deb"]="https://downloads.cursor.com/production/${BUILD_ID}/linux/arm64/deb/arm64/deb/cursor_${VERSION}_arm64.deb"
)

_checksum_file() {
  local file="$1" type="$2" name="$3"
  local size blake2b sha512
  size=$(stat -c%s "$file")
  blake2b=$(b2sum "$file" | awk '{print $1}')
  sha512=$(sha512sum "$file" | awk '{print $1}')
  printf '%s %s %s BLAKE2B %s SHA512 %s\n' "$type" "$name" "$size" "$blake2b" "$sha512"
}

for FNAME in "${!DISTFILES[@]}"; do
  URL="${DISTFILES[$FNAME]}"
  echo "  Downloading: ${FNAME}"
  wget -q -O "/tmp/${FNAME}" "${URL}"
  _checksum_file "/tmp/${FNAME}" "DIST" "${FNAME}" >> /tmp/cursor_manifest_entries.txt
  rm -f "/tmp/${FNAME}"
done

# --- Regenerate full Manifest from disk ---
echo "  Regenerating Manifest"
shopt -s nullglob

for f in *.ebuild; do
  [ -f "$f" ] && _checksum_file "$f" "EBUILD" "$f" >> /tmp/cursor_manifest_entries.txt
done

for f in *.xml; do
  [ -f "$f" ] && _checksum_file "$f" "MISC" "$f" >> /tmp/cursor_manifest_entries.txt
done

sort -t' ' -k1,1 -k2,2V -u /tmp/cursor_manifest_entries.txt > Manifest
rm -f /tmp/cursor_manifest_entries.txt

echo "=== Done: ${PKG_DIR}-${VERSION} ==="
