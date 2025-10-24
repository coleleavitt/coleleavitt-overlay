# Copyright 2025 Gentoo Authors  
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="The Swift Programming Language (binary distribution)"
HOMEPAGE="https://swift.org"
SRC_URI="https://download.swift.org/swift-6.2-release/ubuntu2204/swift-6.2-RELEASE/swift-6.2-RELEASE-ubuntu22.04.tar.gz"

LICENSE="Apache-2.0"
SLOT="6"  # Major version slot
KEYWORDS="~amd64"

RDEPEND="
	>=app-eselect/eselect-swift-1.0
	dev-db/sqlite:3
	dev-libs/libxml2:2
	net-misc/curl
	sys-devel/binutils:*
	sys-devel/gcc:*
	sys-libs/glibc
	sys-libs/readline:0=
	sys-libs/zlib:0=
"

DEPEND="${RDEPEND}"

# QA variables for binary package
QA_PREBUILT="
	usr/lib*/${P}/usr/bin/*
	usr/lib*/${P}/usr/lib/*
	usr/lib*/${P}/usr/libexec/*
"

QA_MULTILIB_PATHS="
	usr/lib*/${P}/usr/lib/.*
"

QA_TEXTRELS="
	usr/lib*/${P}/usr/lib/swift/linux/.*
	usr/lib*/${P}/usr/lib/clang/.*/lib/linux/.*
"

QA_EXECSTACK="
	usr/lib*/${P}/usr/lib/swift/linux/.*
	usr/lib*/${P}/usr/libexec/swift/linux/.*
"

QA_SONAME="
	usr/lib*/${P}/usr/lib/libSwiftSourceKit.*
"

S="${WORKDIR}/swift-6.2-RELEASE-ubuntu22.04"

src_install() {
	# Install to versioned directory (like source ebuild)
	local dest_dir="/usr/$(get_libdir)/${P}"
	mkdir -p "${ED}/${dest_dir}" || die
	
	# Copy entire Swift installation preserving structure
	cp -pPR usr "${ED}/${dest_dir}/" || die
	
	# Remove /usr/local if present (ebuilds must not install there)
	if [[ -d "${ED}/${dest_dir}/usr/local" ]]; then
		rm -rf "${ED}/${dest_dir}/usr/local" || die
	fi
	
	# Fix permissions for executables and libraries
	find "${ED}/${dest_dir}" -type f -executable -exec chmod 755 {} \; || die
	find "${ED}/${dest_dir}" -name "*.so*" -exec chmod 755 {} \; || die
	
	# Only expose Swift-specific tools (not bundled clang/llvm)
	local swift_tools=( swift swiftc sourcekit-lsp )
	local bin
	for bin in "${swift_tools[@]}"; do
		if [[ -f "${ED}/${dest_dir}/usr/bin/${bin}" ]]; then
			dosym -r "${dest_dir}/usr/bin/${bin}" "/usr/bin/${bin}-${PV}"
		fi
	done
	
	# Also expose Swift package manager tools
	local swift_pm_tools=( swift-build swift-package swift-run swift-test )
	for bin in "${swift_pm_tools[@]}"; do
		if [[ -f "${ED}/${dest_dir}/usr/bin/${bin}" ]]; then
			dosym -r "${dest_dir}/usr/bin/${bin}" "/usr/bin/${bin}-${PV}"
		fi
	done
	
	# Create slot symlink for stable path
	local major_ver="$(ver_cut 1)"
	if [[ "${PV}" != "${major_ver}" ]]; then
		dosym -r "${dest_dir}" "/usr/$(get_libdir)/${PN}-${major_ver}"
	fi
	
	# Handle documentation properly
	if [[ -d "${ED}/${dest_dir}/usr/share/doc/swift" ]]; then
		mkdir -p "${ED}/usr/share/doc/${PF}" || die
		mv "${ED}/${dest_dir}"/usr/share/doc/swift/* "${ED}/usr/share/doc/${PF}/" 2>/dev/null || true
		rmdir "${ED}/${dest_dir}/usr/share/doc/swift" 2>/dev/null || true
	fi
}

pkg_postinst() {
	elog "Swift ${PV} has been installed to ${EROOT}/usr/$(get_libdir)/${P}"
	elog ""
	elog "Versioned binaries available:"
	elog "  swift-${PV}, swiftc-${PV}, sourcekit-lsp-${PV}"
	elog "  swift-build-${PV}, swift-package-${PV}, etc."
	elog ""  
	elog "To set as default Swift version:"
	elog "  eselect swift set ${P}"
	elog ""
	elog "The bundled clang/llvm tools are available within Swift's"
	elog "toolchain but not exposed globally to avoid conflicts."
	elog ""
	elog "For more information: https://swift.org/documentation/"
}

pkg_postrm() {
	elog "Swift ${PV} has been uninstalled."
	elog "Run 'eselect swift update' to select a new default version."
}
