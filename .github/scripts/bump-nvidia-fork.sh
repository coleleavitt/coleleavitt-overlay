#!/bin/bash
# Bump x11-drivers/nvidia-drivers to a new commit of the kernel module fork.
# VERSION is <NVIDIA_VERSION at COMMIT>_p<commit timestamp>; the userspace
# version follows it, so a fork rebase onto a new NVIDIA release also moves
# the .run and tool tarballs. Unchanged distfiles keep their Manifest lines.
set -euo pipefail

: "${PKG_CATEGORY:?}" "${PKG_NAME:?}" "${VERSION:?}" "${CURRENT:?}" "${COMMIT:?}"

cd "${PKG_CATEGORY}/${PKG_NAME}"
old="${PKG_NAME}-${CURRENT}.ebuild"
new="${PKG_NAME}-${VERSION}.ebuild"
userspace=${VERSION%_p*}
repo=$(sed -n 's/^NV_KMOD_REPO="\(.*\)"$/\1/p' "$old")
nv_uri="https://download.nvidia.com/XFree86"

sed "s/^NV_KMOD_COMMIT=.*/NV_KMOD_COMMIT=\"${COMMIT}\"/" "$old" > "$new"
git rm -q "$old"

declare -A urls=(
    ["NVIDIA-Linux-x86_64-${userspace}.run"]="${nv_uri}/Linux-x86_64/${userspace}/NVIDIA-Linux-x86_64-${userspace}.run"
    ["NVIDIA-Linux-aarch64-${userspace}.run"]="${nv_uri}/Linux-aarch64/${userspace}/NVIDIA-Linux-aarch64-${userspace}.run"
    ["nvidia-open-gpu-kernel-modules-${COMMIT}.tar.gz"]="https://github.com/${repo}/archive/${COMMIT}.tar.gz"
)
for tool in installer modprobe persistenced settings xconfig; do
    urls["nvidia-${tool}-${userspace}.tar.bz2"]="${nv_uri}/nvidia-${tool}/nvidia-${tool}-${userspace}.tar.bz2"
done

manifest_line() {
    local kind=$1 name=$2 file=$3
    echo "${kind} ${name} $(stat -c%s "$file") BLAKE2B $(b2sum "$file" | awk '{print $1}') SHA512 $(sha512sum "$file" | awk '{print $1}')"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dist_lines=()
for dist in "${!urls[@]}"; do
    existing=$(grep "^DIST ${dist} " Manifest || true)
    if [ -n "$existing" ]; then
        dist_lines+=("$existing")
    else
        echo "Fetching ${urls[$dist]}"
        curl -fsSL -o "${tmp}/${dist}" "${urls[$dist]}"
        dist_lines+=("$(manifest_line DIST "$dist" "${tmp}/${dist}")")
        rm -f "${tmp}/${dist}"
    fi
done

{
    grep '^AUX ' Manifest || true
    printf '%s\n' "${dist_lines[@]}" | LC_ALL=C sort -k2,2
    manifest_line EBUILD "$new" "$new"
    grep '^MISC ' Manifest || true
} > Manifest.new
mv Manifest.new Manifest
