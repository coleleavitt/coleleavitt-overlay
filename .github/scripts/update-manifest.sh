#!/bin/bash
# Helper script to update Manifest files for new ebuilds
# Usage: ./update-manifest.sh <category/package> <version>
# Example: ./update-manifest.sh www-client/zen-browser-bin 1.17.1b

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <category/package> <version>"
    echo "Example: $0 www-client/zen-browser-bin 1.17.1b"
    exit 1
fi

PACKAGE_PATH="$1"
VERSION="$2"
PACKAGE_NAME=$(basename "$PACKAGE_PATH")
EBUILD_FILE="${PACKAGE_PATH}/${PACKAGE_NAME}-${VERSION}.ebuild"

# Check if ebuild exists
if [ ! -f "$EBUILD_FILE" ]; then
    echo "ERROR: Ebuild not found: $EBUILD_FILE"
    exit 1
fi

echo "Updating Manifest for ${PACKAGE_NAME}-${VERSION}..."
cd "$PACKAGE_PATH"

# Generate Manifest with proper checksums
echo "Running: ebuild ${PACKAGE_NAME}-${VERSION}.ebuild manifest"
ebuild "${PACKAGE_NAME}-${VERSION}.ebuild" manifest

# Show the result
echo ""
echo "Manifest updated successfully!"
echo ""
echo "New Manifest entries:"
grep "DIST.*${VERSION}" Manifest || echo "(No new DIST entries found)"

echo ""
echo "Next steps:"
echo "1. Review the Manifest changes: git diff Manifest"
echo "2. Test the ebuild: emerge -av =${PACKAGE_NAME}-${VERSION}"
echo "3. Commit the changes: git add Manifest && git commit --amend --no-edit"
