# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..13} )

inherit git-r3 python-any-r1 toolchain-funcs

DESCRIPTION="Custom TianoCore EDK II UEFI firmware for virtual machines"
HOMEPAGE="https://github.com/coleleavitt/edk2"

# Download submodule dependencies as tarballs to avoid network issues
SRC_URI="
	https://github.com/google/brotli/archive/f4153a09f87cbb9c826d8fc12c74642bb2d879ea.tar.gz -> brotli-f4153a09f87cbb9c826d8fc12c74642bb2d879ea.tar.gz
	https://github.com/openssl/openssl/releases/download/openssl-3.4.1/openssl-3.4.1.tar.gz
	https://github.com/MIPI-Alliance/public-mipi-sys-t/archive/370b5944c046bab043dd8b133727b2135af7747a.tar.gz -> mipi-sys-t-370b5944c046bab043dd8b133727b2135af7747a.tar.gz
	https://github.com/Mbed-TLS/mbedtls/archive/8c89224991adff88d53cd380f42a2baa36f91454.tar.gz -> mbedtls-8c89224991adff88d53cd380f42a2baa36f91454.tar.gz
	https://github.com/DMTF/libspdm/archive/98ef964e1e9a0c39c7efb67143d3a13a819432e0.tar.gz -> libspdm-98ef964e1e9a0c39c7efb67143d3a13a819432e0.tar.gz
"

# Your GitHub fork with stealth modifications
EGIT_REPO_URI="https://github.com/coleleavitt/edk2.git"
#EGIT_COMMIT="42d28dbabb01d57d7906900a16b58c9227d27f91"
EGIT_BRANCH="stealth-smbios-acpi"
EGIT_SUBMODULES=( )  # Disable git-r3 submodules, handle manually

S="${WORKDIR}/${P}"
LICENSE="BSD-2 MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+secureboot"

BDEPEND="
	${PYTHON_DEPS}
	>=sys-power/iasl-20160729
	>=dev-lang/nasm-2.0.7
	app-emulation/qemu
	dev-vcs/git
"

RDEPEND="
	!sys-firmware/edk2-bin
	!sys-firmware/edk2-stealth
"

pkg_setup() {
	python-any-r1_pkg_setup
}

src_unpack() {
	# Unpack git repository
	git-r3_src_unpack

	# Manually unpack submodule dependencies
	cd "${WORKDIR}" || die

	local archives=(
		"brotli-f4153a09f87cbb9c826d8fc12c74642bb2d879ea.tar.gz"
		"openssl-3.4.1.tar.gz"
		"mipi-sys-t-370b5944c046bab043dd8b133727b2135af7747a.tar.gz"
		"mbedtls-8c89224991adff88d53cd380f42a2baa36f91454.tar.gz"
		"libspdm-98ef964e1e9a0c39c7efb67143d3a13a819432e0.tar.gz"
	)

	for archive in "${archives[@]}"; do
		if [[ -f "${DISTDIR}/${archive}" ]]; then
			einfo "Unpacking ${archive}..."
			unpack "${archive}"
		fi
	done
}

src_prepare() {
	einfo "=== LINKING SUBMODULE DEPENDENCIES ==="

	# Link Brotli (critical for BaseTools compilation)
	local brotli_src="${WORKDIR}/brotli-f4153a09f87cbb9c826d8fc12c74642bb2d879ea"
	if [[ -d "${brotli_src}" ]]; then
		einfo "Linking Brotli compression library..."

		# Remove existing directories/symlinks
		rm -rf BaseTools/Source/C/BrotliCompress/brotli
		rm -rf MdeModulePkg/Library/BrotliCustomDecompressLib/brotli

		# Create symbolic links
		ln -sfT "${brotli_src}" BaseTools/Source/C/BrotliCompress/brotli || die "Failed to link BaseTools Brotli"
		ln -sfT "${brotli_src}" MdeModulePkg/Library/BrotliCustomDecompressLib/brotli || die "Failed to link MdeModulePkg Brotli"
	else
		die "Brotli source directory not found: ${brotli_src}"
	fi

	# Link other dependencies
	local deps=(
		"${WORKDIR}/openssl-3.4.1:CryptoPkg/Library/OpensslLib/openssl"
		"${WORKDIR}/mbedtls-8c89224991adff88d53cd380f42a2baa36f91454:CryptoPkg/Library/MbedTlsLib/mbedtls"
		"${WORKDIR}/libspdm-98ef964e1e9a0c39c7efb67143d3a13a819432e0:SecurityPkg/DeviceSecurity/SpdmLib/libspdm"
		"${WORKDIR}/public-mipi-sys-t-370b5944c046bab043dd8b133727b2135af7747a:MdePkg/Library/MipiSysTLib/mipisyst"
	)

	for dep in "${deps[@]}"; do
		local src_dir="${dep%:*}"
		local dst_dir="${dep#*:}"

		if [[ -d "${src_dir}" ]]; then
			einfo "Linking $(basename "${dst_dir}")..."
			rm -rf "${dst_dir}"
			ln -sfT "${src_dir}" "${dst_dir}" || die "Failed to link ${dst_dir}"
		fi
	done

	# Verify critical Brotli dependency
	if [[ -f "BaseTools/Source/C/BrotliCompress/brotli/c/common/constants.h" ]]; then
		einfo "✓ Brotli dependency successfully linked"
	else
		die "✗ Critical Brotli header file missing after linking"
	fi

	einfo "=== DEPENDENCY LINKING COMPLETE ==="
	default
}

src_compile() {
	export WORKSPACE="${S}"
	export PYTHON_COMMAND="${PYTHON}"
	export EDK_TOOLS_PATH="${S}/BaseTools"

	# Build BaseTools
	einfo "Building EDK II BaseTools..."
	tc-export_build_env
	emake -C BaseTools \
		CC="$(tc-getBUILD_CC)" \
		CXX="$(tc-getBUILD_CXX)" || die "BaseTools build failed"

	# Setup EDK2 environment
	einfo "Setting up EDK II build environment..."
	source "${S}/edksetup.sh" || die "edksetup.sh failed"

	# Configure build parameters with SMBIOS spoofing PCDs
	local myconf=(
		-a X64
		-p OvmfPkg/OvmfPkgX64.dsc
		-t GCC5
		-b RELEASE
		-n "$(nproc)"
		-D FD_SIZE_2MB
		-D BUILD_SHELL=FALSE
		-D NETWORK_HTTP_BOOT_ENABLE
		-D NETWORK_IP6_ENABLE
		-D TPM1_ENABLE
		-D TPM2_ENABLE
		# SMBIOS spoofing to bypass VM detection
		--pcd "gEfiMdeModulePkgTokenSpaceGuid.PcdFirmwareVendor=L'American Megatrends Inc.'"
		--pcd "gEfiMdeModulePkgTokenSpaceGuid.PcdFirmwareVersionString=L'F.43'"
		--pcd "gEfiMdeModulePkgTokenSpaceGuid.PcdFirmwareReleaseDateString=L'04/01/2023'"
	)

	if use secureboot; then
		einfo "Enabling Secure Boot support..."
		myconf+=(
			-D SECURE_BOOT_ENABLE
			-D SMM_REQUIRE
		)
	fi

	# Build OVMF firmware with custom SMBIOS values
	einfo "Building OVMF firmware with stealth SMBIOS configuration..."
	build "${myconf[@]}" || die "OVMF build failed"
}

src_install() {
	local target="/usr/share/edk2/x64"

	dodir "${target}"

	# Install firmware files
	insinto "${target}"
	doins Build/OvmfX64/*/FV/OVMF_CODE.fd
	doins Build/OvmfX64/*/FV/OVMF_VARS.fd

	if use secureboot; then
		newins Build/OvmfX64/*/FV/OVMF_CODE.fd OVMF_CODE.secboot.fd
	fi

	# Create compatibility symlinks
	dosym ../edk2 /usr/share/qemu/edk2-x86_64
	dosym edk2 /usr/share/edk2-ovmf
}

pkg_postinst() {
	elog ""
	elog "Custom TianoCore EDK II UEFI firmware installed with stealth modifications!"
	elog ""
	elog "SMBIOS Configuration:"
	elog "  • Vendor: American Megatrends Inc."
	elog "  • Version: F.43"
	elog "  • Release Date: 04/01/2023"
	elog ""
	elog "Installation directory: /usr/share/edk2/x64/"
	elog ""
	elog "Available firmware files:"
	elog "  • OVMF_CODE.fd - Custom OVMF firmware"
	elog "  • OVMF_VARS.fd - Standard OVMF variables"

	if use secureboot; then
		elog "  • OVMF_CODE.secboot.fd - Custom Secure Boot firmware"
	fi

	elog ""
	elog "Usage with QEMU:"
	elog "  qemu-system-x86_64 \\"
	elog "    -drive file=/usr/share/edk2/x64/OVMF_CODE.fd,if=pflash,format=raw,unit=0,readonly=on \\"
	elog "    -drive file=/path/to/OVMF_VARS.fd,if=pflash,format=raw,unit=1 \\"
	elog "    [additional QEMU arguments]"
	elog ""
}

