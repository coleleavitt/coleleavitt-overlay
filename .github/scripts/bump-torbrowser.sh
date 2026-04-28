#!/usr/bin/env bash
# bump-torbrowser.sh — Mirror www-client/torbrowser from upstream overlay and patch LLVM_COMPAT.
#
# torbrowser ebuilds are too complex for the generic bump-package.sh:
#   - Multiple internal version pins (TOR_PV, NOSCRIPT_VERSION, FIREFOX_PATCHSET, CHANGELOG_TAG)
#   - 5 distfiles with cross-referenced versions
#   - Tor Project tagging conventions diverge from semver
# Strategy: mirror upstream MeisterP/torbrowser-overlay verbatim, rename to -r1 to
# signal local revision, patch LLVM_COMPAT to add max LLVM slot, regenerate Manifest.
#
# Env vars expected:
#   PKG_CATEGORY    — www-client (always)
#   PKG_NAME        — torbrowser (always)
#   VERSION         — new upstream version, e.g. 140.10.0_p15010 (no -r suffix)
#   CURRENT         — current local upstream-version (for logging only)
#   UPSTREAM_REPO   — MeisterP/torbrowser-overlay
#   UPSTREAM_PATH   — www-client/torbrowser
#   LLVM_MAX        — max LLVM slot to ensure is in LLVM_COMPAT (e.g. 22)
set -euo pipefail

PKG_DIR="${PKG_CATEGORY}/${PKG_NAME}"
NEW_EBUILD="${PKG_NAME}-${VERSION}-r1.ebuild"
UPSTREAM_EBUILD="${PKG_NAME}-${VERSION}.ebuild"
RAW="https://raw.githubusercontent.com/${UPSTREAM_REPO}/master/${UPSTREAM_PATH}"
API="https://api.github.com/repos/${UPSTREAM_REPO}/contents/${UPSTREAM_PATH}"

echo "=== Mirroring ${PKG_DIR} ${VERSION} from ${UPSTREAM_REPO} ==="

mkdir -p "${PKG_DIR}/files"
cd "${PKG_DIR}"

# --- Mirror upstream ebuild as -r1 ---
curl -sL -f "${RAW}/${UPSTREAM_EBUILD}" -o "${NEW_EBUILD}"
echo "  Mirrored: ${UPSTREAM_EBUILD} -> ${NEW_EBUILD}"

# --- Mirror metadata.xml ---
curl -sL -f "${RAW}/metadata.xml" -o metadata.xml
echo "  Mirrored: metadata.xml"

# --- Mirror files/* via GitHub API listing ---
# Wipe stale files first so removed-upstream entries don't linger
rm -f files/*
FILES_LISTING=$(curl -sL -f "${API}/files" | jq -r '.[].name')
for fname in $FILES_LISTING; do
  curl -sL -f "${RAW}/files/${fname}" -o "files/${fname}"
  echo "  Mirrored: files/${fname}"
done

# --- Mirror upstream Manifest (used for DIST checksums; sources unchanged) ---
curl -sL -f "${RAW}/Manifest" -o /tmp/upstream-torbrowser-manifest
echo "  Fetched: upstream Manifest (DIST entries)"

# --- Patch LLVM_COMPAT: ensure LLVM_MAX is included ---
# Upstream uses list-style: LLVM_COMPAT=( 20 21 ). We extend with our max slot.
if [ -n "${LLVM_MAX:-}" ]; then
  CURRENT_LIST=$(grep -oP 'LLVM_COMPAT=\(\K[^)]+' "${NEW_EBUILD}" | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -nu)
  if echo "$CURRENT_LIST" | grep -qx "${LLVM_MAX}"; then
    echo "  LLVM_COMPAT already includes ${LLVM_MAX} (${CURRENT_LIST//$'\n'/ }), no patch needed"
  else
    NEW_LIST=$(printf '%s\n%s\n' "${CURRENT_LIST}" "${LLVM_MAX}" | sort -nu | tr '\n' ' ' | sed 's/ *$//')
    sed -i "s/LLVM_COMPAT=( [0-9 ]* )/LLVM_COMPAT=( ${NEW_LIST} )/" "${NEW_EBUILD}"
    echo "  Patched LLVM_COMPAT: ( ${CURRENT_LIST//$'\n'/ } ) -> ( ${NEW_LIST} )"
  fi
fi

# --- Drop stale ebuilds (we keep only the newly mirrored -r1) ---
for old in ${PKG_NAME}-*.ebuild; do
  if [ "$old" != "${NEW_EBUILD}" ]; then
    rm -f "$old"
    echo "  Removed stale ebuild: ${old}"
  fi
done

# --- Regenerate Manifest ---
echo "  Regenerating Manifest"

shopt -s nullglob

_checksum_file() {
  local file="$1" type="$2" name="$3"
  local size blake2b sha512
  size=$(stat -c%s "$file")
  blake2b=$(b2sum "$file" | awk '{print $1}')
  sha512=$(sha512sum "$file" | awk '{print $1}')
  printf '%s %s %s BLAKE2B %s SHA512 %s\n' "$type" "$name" "$size" "$blake2b" "$sha512"
}

: > /tmp/torbrowser_manifest_entries.txt

# AUX entries (files/*)
for f in files/*; do
  [ -f "$f" ] && _checksum_file "$f" "AUX" "$(basename "$f")" >> /tmp/torbrowser_manifest_entries.txt
done

# DIST entries from upstream Manifest (sources are byte-identical)
grep "^DIST" /tmp/upstream-torbrowser-manifest >> /tmp/torbrowser_manifest_entries.txt

# EBUILD entries (only our new -r1)
for f in *.ebuild; do
  [ -f "$f" ] && _checksum_file "$f" "EBUILD" "$f" >> /tmp/torbrowser_manifest_entries.txt
done

# MISC entries (metadata.xml)
for f in *.xml; do
  [ -f "$f" ] && _checksum_file "$f" "MISC" "$f" >> /tmp/torbrowser_manifest_entries.txt
done

# Sort: AUX → DIST → EBUILD → MISC, then by version-aware filename, dedupe
sort -t' ' -k1,1 -k2,2V -u /tmp/torbrowser_manifest_entries.txt > Manifest

rm -f /tmp/upstream-torbrowser-manifest /tmp/torbrowser_manifest_entries.txt

echo "=== Done: ${PKG_DIR}-${VERSION}-r1 ==="
