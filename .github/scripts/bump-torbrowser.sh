#!/usr/bin/env bash
# bump-torbrowser.sh — Template www-client/torbrowser from Tor Project release data.
#
# Env vars expected:
#   PKG_CATEGORY    — www-client
#   PKG_NAME        — torbrowser
#   VERSION         — new ebuild version, e.g. 140.10.1_p15011 (no -r suffix)
#   CURRENT         — current local version (for template selection)
#   UPSTREAM_REPO   — MeisterP/torbrowser-overlay (fallback mirror source)
#   UPSTREAM_PATH   — www-client/torbrowser
#   LLVM_MAX        — max LLVM slot to ensure is in LLVM_COMPAT
set -euo pipefail

PKG_DIR="${PKG_CATEGORY}/${PKG_NAME}"
NEW_EBUILD="${PKG_NAME}-${VERSION}-r1.ebuild"

echo "=== Bumping ${PKG_DIR} to ${VERSION} ==="

mkdir -p "${PKG_DIR}/files"
cd "${PKG_DIR}"

# --- Derive Tor Project version variables from ebuild VERSION ---
FF_VER="${VERSION/_p*/}"
TOR_PV_ENCODED="${VERSION#*_p}"
# Decode _p suffix: 15011 → 15.0.11 (first 2 digits = major.minor, rest = patch)
# Pattern: series=15, minor_series=0, patch=11 → 15.0.11
# Detect from AUS API instead for accuracy
TOR_DL_JSON=$(curl -sL "https://aus1.torproject.org/torbrowser/update_3/release/downloads.json")
TOR_PV=$(echo "$TOR_DL_JSON" | jq -r '.version')
TBB_TAG=$(echo "$TOR_DL_JSON" | jq -r '.tag')
BUILD_SUFFIX="${TBB_TAG#tbb-${TOR_PV}-}"

echo "  FF_VER=${FF_VER} TOR_PV=${TOR_PV} BUILD_SUFFIX=${BUILD_SUFFIX}"

# Fetch NoScript version from tor-browser-build config
NOSCRIPT_VERSION=$(curl -sL "https://gitlab.torproject.org/api/v4/projects/tpo%2Fapplications%2Ftor-browser-build/repository/files/projects%2Fbrowser%2Fconfig/raw?ref=${TBB_TAG}" \
  | grep -oP 'noscript-\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "  NOSCRIPT_VERSION=${NOSCRIPT_VERSION}"

# --- Find template ebuild (previous version or MeisterP mirror) ---
TEMPLATE=""
if ls ${PKG_NAME}-*.ebuild 1>/dev/null 2>&1; then
  TEMPLATE=$(ls ${PKG_NAME}-*.ebuild | sort -V | tail -1)
fi

if [ -z "$TEMPLATE" ]; then
  RAW="https://raw.githubusercontent.com/${UPSTREAM_REPO}/master/${UPSTREAM_PATH}"
  UPSTREAM_EB=$(curl -sL "https://api.github.com/repos/${UPSTREAM_REPO}/contents/${UPSTREAM_PATH}" \
    | jq -r '.[].name' | grep '\.ebuild$' | sort -V | tail -1)
  if [ -n "$UPSTREAM_EB" ]; then
    curl -sL -f "${RAW}/${UPSTREAM_EB}" -o "_template.ebuild"
    TEMPLATE="_template.ebuild"
    echo "  Fetched template from MeisterP: ${UPSTREAM_EB}"
  fi
fi

if [ -z "$TEMPLATE" ]; then
  echo "ERROR: No template ebuild found"
  exit 1
fi

echo "  Template: ${TEMPLATE}"
cp "${TEMPLATE}" "${NEW_EBUILD}"

# --- Substitute version variables ---
TOR_TAG="${TOR_PV%.*}-1-${BUILD_SUFFIX}"
CHANGELOG_TAG="${TOR_PV}-${BUILD_SUFFIX}"

sed -i "s/^TOR_PV=\"[^\"]*\"/TOR_PV=\"${TOR_PV}\"/" "${NEW_EBUILD}"
sed -i "s/^TOR_TAG=\"[^\"]*\"/TOR_TAG=\"\${TOR_PV%.*}-1-${BUILD_SUFFIX}\"/" "${NEW_EBUILD}"
sed -i "s/^NOSCRIPT_VERSION=\"[^\"]*\"/NOSCRIPT_VERSION=\"${NOSCRIPT_VERSION}\"/" "${NEW_EBUILD}"
sed -i "s/^CHANGELOG_TAG=\"[^\"]*\"/CHANGELOG_TAG=\"\${TOR_PV}-${BUILD_SUFFIX}\"/" "${NEW_EBUILD}"

echo "  Substituted: TOR_PV=${TOR_PV} TOR_TAG=${TOR_TAG} NOSCRIPT=${NOSCRIPT_VERSION}"

# --- Mirror metadata.xml and files/* from MeisterP (patches are overlay-specific) ---
RAW="https://raw.githubusercontent.com/${UPSTREAM_REPO}/master/${UPSTREAM_PATH}"
API="https://api.github.com/repos/${UPSTREAM_REPO}/contents/${UPSTREAM_PATH}"

curl -sL -f "${RAW}/metadata.xml" -o metadata.xml 2>/dev/null || echo "  metadata.xml: keeping existing"

UPSTREAM_FILES=$(curl -sL -f "${API}/files" 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)
for fname in $UPSTREAM_FILES; do
  if [ ! -f "files/${fname}" ]; then
    curl -sL -f "${RAW}/files/${fname}" -o "files/${fname}" 2>/dev/null && echo "  Mirrored: files/${fname}"
  fi
done

# --- Patch LLVM_COMPAT: ensure LLVM_MAX is included ---
if [ -n "${LLVM_MAX:-}" ]; then
  CURRENT_LIST=$(grep -oP 'LLVM_COMPAT=\(\K[^)]+' "${NEW_EBUILD}" | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -nu)
  if echo "$CURRENT_LIST" | grep -qx "${LLVM_MAX}"; then
    echo "  LLVM_COMPAT already includes ${LLVM_MAX}"
  else
    NEW_LIST=$(printf '%s\n%s\n' "${CURRENT_LIST}" "${LLVM_MAX}" | sort -nu | tr '\n' ' ' | sed 's/ *$//')
    sed -i "s/LLVM_COMPAT=( [0-9 ]* )/LLVM_COMPAT=( ${NEW_LIST} )/" "${NEW_EBUILD}"
    echo "  Patched LLVM_COMPAT: ( ${NEW_LIST} )"
  fi
fi

# --- Drop stale ebuilds ---
for old in ${PKG_NAME}-*.ebuild; do
  [ "$old" = "${NEW_EBUILD}" ] && continue
  [ "$old" = "_template.ebuild" ] && continue
  rm -f "$old"
  echo "  Removed stale: ${old}"
done
rm -f _template.ebuild

# --- Regenerate Manifest ---
echo "  Regenerating Manifest (DIST entries from distfile downloads)"

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

for f in files/*; do
  [ -f "$f" ] && _checksum_file "$f" "AUX" "$(basename "$f")" >> /tmp/torbrowser_manifest_entries.txt
done

# DIST: download each distfile, checksum, delete
MOZ_PV="${FF_VER}esr"
TOR_SRC="src-firefox-tor-browser-${MOZ_PV}-${TOR_TAG}.tar.xz"
TOR_BIN="tor-browser-linux-x86_64-${TOR_PV}.tar.xz"
NOSCRIPT_FILE="noscript-${NOSCRIPT_VERSION}.xpi"
CHANGELOG_FILE="${PKG_NAME}-${VERSION}-ChangeLog.txt"

DISTFILES=(
  "https://dist.torproject.org/torbrowser/${TOR_PV}/${TOR_SRC}|${TOR_SRC}"
  "https://dist.torproject.org/torbrowser/${TOR_PV}/${TOR_BIN}|${TOR_BIN}"
  "https://dist.torproject.org/torbrowser/noscript/${NOSCRIPT_FILE}|${NOSCRIPT_FILE}"
  "https://gitlab.torproject.org/tpo/applications/tor-browser-build/-/raw/tbb-${CHANGELOG_TAG}/projects/browser/Bundle-Data/Docs-TBB/ChangeLog.txt|${CHANGELOG_FILE}"
)

# Reuse DIST from existing Manifest if filenames match (avoids re-downloading 700MB)
for entry in "${DISTFILES[@]}"; do
  URL="${entry%%|*}"
  FNAME="${entry##*|}"
  EXISTING=$(grep "^DIST ${FNAME} " Manifest 2>/dev/null || true)
  if [ -n "$EXISTING" ]; then
    echo "$EXISTING" >> /tmp/torbrowser_manifest_entries.txt
    echo "  Reused DIST: ${FNAME}"
  else
    echo "  Downloading: ${FNAME}"
    wget -q -O "/tmp/${FNAME}" "${URL}"
    _checksum_file "/tmp/${FNAME}" "DIST" "${FNAME}" >> /tmp/torbrowser_manifest_entries.txt
    rm -f "/tmp/${FNAME}"
  fi
done

# Also pull firefox patchset DIST from Gentoo or existing Manifest
PATCHSET=$(grep -oP 'FIREFOX_PATCHSET="\K[^"]+' "${NEW_EBUILD}")
PATCHSET_DIST=$(grep "^DIST ${PATCHSET} " Manifest 2>/dev/null || true)
if [ -n "$PATCHSET_DIST" ]; then
  echo "$PATCHSET_DIST" >> /tmp/torbrowser_manifest_entries.txt
  echo "  Reused DIST: ${PATCHSET}"
else
  GENTOO_MANIFEST=$(curl -sL -f "https://raw.githubusercontent.com/gentoo-mirror/gentoo/master/www-client/firefox/Manifest" 2>/dev/null || true)
  PATCHSET_DIST=$(echo "$GENTOO_MANIFEST" | grep "^DIST ${PATCHSET} " || true)
  if [ -n "$PATCHSET_DIST" ]; then
    echo "$PATCHSET_DIST" >> /tmp/torbrowser_manifest_entries.txt
    echo "  Pulled DIST from gentoo: ${PATCHSET}"
  else
    echo "  WARNING: Could not find DIST for ${PATCHSET}"
  fi
fi

for f in *.ebuild; do
  [ -f "$f" ] && _checksum_file "$f" "EBUILD" "$f" >> /tmp/torbrowser_manifest_entries.txt
done

for f in *.xml; do
  [ -f "$f" ] && _checksum_file "$f" "MISC" "$f" >> /tmp/torbrowser_manifest_entries.txt
done

sort -t' ' -k1,1 -k2,2V -u /tmp/torbrowser_manifest_entries.txt > Manifest
rm -f /tmp/torbrowser_manifest_entries.txt

echo "=== Done: ${PKG_DIR}-${VERSION}-r1 ==="
