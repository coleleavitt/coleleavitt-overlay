#!/bin/bash
# Check that every pinned nvidia-drivers ebuild installs userspace of the same
# version as the kernel module at its pinned fork commit. nvidia.ko loads GSP
# firmware from /lib/firmware/nvidia/<its version> and rejects other userspace,
# so a mismatch leaves the GPU unusable.
set -euo pipefail

status=0
for ebuild in x11-drivers/nvidia-drivers/nvidia-drivers-*.ebuild; do
    name=$(basename "$ebuild" .ebuild)
    pv=${name#nvidia-drivers-}
    pv=${pv%-r[0-9]*}
    repo=$(sed -n 's/^NV_KMOD_REPO="\(.*\)"$/\1/p' "$ebuild")
    commit=$(sed -n 's/^NV_KMOD_COMMIT="\(.*\)"$/\1/p' "$ebuild")
    if [ -z "$repo" ] || [ -z "$commit" ]; then
        echo "::error file=${ebuild}::NV_KMOD_REPO/NV_KMOD_COMMIT not set; the kernel module source must be pinned"
        status=1
        continue
    fi

    userspace=${pv%_p*}
    kmod=$(curl -fsSL "https://raw.githubusercontent.com/${repo}/${commit}/version.mk" |
        sed -n 's/^NVIDIA_VERSION = //p')
    if [ "$kmod" != "$userspace" ]; then
        echo "::error file=${ebuild}::${repo}@${commit} is NVIDIA ${kmod:-<unknown>} but the ebuild installs userspace ${userspace}"
        status=1
    else
        echo "${name}: kernel module and userspace are both ${userspace}"
    fi

    for dist in "nvidia-open-gpu-kernel-modules-${commit}.tar.gz" "NVIDIA-Linux-x86_64-${userspace}.run"; do
        if ! grep -q "^DIST ${dist} " x11-drivers/nvidia-drivers/Manifest; then
            echo "::error file=x11-drivers/nvidia-drivers/Manifest::missing DIST ${dist}"
            status=1
        fi
    done
done
exit "$status"
