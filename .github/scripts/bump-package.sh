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
GENTOO_MANIFEST="/var/db/repos/gentoo/${PKG_DIR}/Manifest"
GENTOO_CI_MANIFEST=""

echo "=== Bumping ${PKG_DIR} from ${CURRENT} to ${VERSION} ==="

cd "${PKG_DIR}"

# --- Find template ebuild ---
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
    LIST=$(seq "${LLVM_MIN:-17}" "${LLVM_MAX}" | tr '\n' ' ' | sed 's/ *$//')
    sed -i "s/LLVM_COMPAT=( [0-9 ]* )/LLVM_COMPAT=( ${LIST} )/" "${NEW_EBUILD}"
  else
    sed -i "s/LLVM_COMPAT=( {[0-9]*\.\.[0-9]*} )/LLVM_COMPAT=( {${LLVM_MIN:-18}..${LLVM_MAX}} )/" "${NEW_EBUILD}"
  fi
fi

# --- Download distfiles and compute DIST checksums ---
rm -f /tmp/new_dist_lines.txt
DOWNLOAD_COUNT=$(echo "${DOWNLOADS}" | jq -r 'length')
for i in $(seq 0 $((DOWNLOAD_COUNT - 1))); do
  MINOR_VERSION=$(echo "${VERSION}" | grep -oP '^[0-9]+\.[0-9]+')
  URL=$(echo "${DOWNLOADS}" | jq -r ".[$i].url" | sed "s/{VERSION}/${VERSION}/g; s/{MINOR_VERSION}/${MINOR_VERSION}/g")
  FILENAME=$(echo "${DOWNLOADS}" | jq -r ".[$i].filename" | sed "s/{VERSION}/${VERSION}/g; s/{MINOR_VERSION}/${MINOR_VERSION}/g")

  echo "  Downloading: ${FILENAME}"
  wget -q -O "/tmp/${FILENAME}" "${URL}"

  SIZE=$(stat -c%s "/tmp/${FILENAME}")
  BLAKE2B=$(b2sum "/tmp/${FILENAME}" | awk '{print $1}')
  SHA512=$(sha512sum "/tmp/${FILENAME}" | awk '{print $1}')

  echo "DIST ${FILENAME} ${SIZE} BLAKE2B ${BLAKE2B} SHA512 ${SHA512}" >> /tmp/new_dist_lines.txt
  rm -f "/tmp/${FILENAME}"
done

# --- Pull extra DIST entries from gentoo Manifest ---
# Packages like cmake reference additional distfiles (docs, signatures)
# that we don't download ourselves. Pull their checksums from gentoo.
if [ -f "$GENTOO_MANIFEST" ]; then
  echo "  Checking gentoo Manifest for extra distfiles"
  grep "^DIST" "$GENTOO_MANIFEST" 2>/dev/null | while read -r line; do
    DIST_NAME=$(echo "$line" | awk '{print $2}')
    # Skip if we already have this entry from our downloads
    if ! grep -q "$DIST_NAME" /tmp/new_dist_lines.txt 2>/dev/null; then
      # Skip if already in our existing Manifest
      if ! grep -q "$DIST_NAME" Manifest 2>/dev/null; then
        echo "  Pulling from gentoo: ${DIST_NAME}"
        echo "$line" >> /tmp/new_dist_lines.txt
      fi
    fi
  done
else
  # In CI, gentoo repo is synced by pkgcheck-action but not by auto-update.
  # Try fetching the Manifest directly from GitHub.
  GENTOO_CI_MANIFEST=$(curl -sL "https://raw.githubusercontent.com/gentoo-mirror/gentoo/master/${PKG_DIR}/Manifest" 2>/dev/null || true)
  if [ -n "$GENTOO_CI_MANIFEST" ]; then
    echo "  Checking gentoo Manifest (from GitHub) for extra distfiles"
    echo "$GENTOO_CI_MANIFEST" | grep "^DIST" | while read -r line; do
      DIST_NAME=$(echo "$line" | awk '{print $2}')
      if ! grep -q "$DIST_NAME" /tmp/new_dist_lines.txt 2>/dev/null; then
        if ! grep -q "$DIST_NAME" Manifest 2>/dev/null; then
          echo "  Pulling from gentoo: ${DIST_NAME}"
          echo "$line" >> /tmp/new_dist_lines.txt
        fi
      fi
    done
  fi
fi

# --- Regenerate full Manifest from disk (like `ebuild manifest`) ---
echo "  Regenerating Manifest"

_checksum_file() {
  local file="$1" type="$2" name="$3"
  local size blake2b sha512
  size=$(stat -c%s "$file")
  blake2b=$(b2sum "$file" | awk '{print $1}')
  sha512=$(sha512sum "$file" | awk '{print $1}')
  echo "${type} ${name} ${size} BLAKE2B ${blake2b} SHA512 ${sha512}"
}

{
  # AUX: files in files/ directory
  if [ -d files ]; then
    for f in files/*; do
      [ -f "$f" ] && _checksum_file "$f" "AUX" "$(basename "$f")"
    done
  fi

  # DIST: new downloads + existing + gentoo extras
  cat /tmp/new_dist_lines.txt 2>/dev/null || true
  grep "^DIST" Manifest 2>/dev/null || true

  # EBUILD: all .ebuild files in current directory
  for f in *.ebuild; do
    [ -f "$f" ] && _checksum_file "$f" "EBUILD" "$f"
  done

  # MISC: metadata.xml and other non-ebuild, non-Manifest files
  for f in *.xml *.conf; do
    [ -f "$f" ] && [ "$f" != "Manifest" ] && _checksum_file "$f" "MISC" "$f"
  done
} | sort -t' ' -k1,1 -k2,2V -u > Manifest.new

mv Manifest.new Manifest
rm -f /tmp/new_dist_lines.txt

echo "=== Done: ${PKG_DIR}-${VERSION} ==="
