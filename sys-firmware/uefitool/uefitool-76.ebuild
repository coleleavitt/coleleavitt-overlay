# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

DESCRIPTION="UEFI firmware image viewer and editor"
HOMEPAGE="https://github.com/LongSoft/UEFITool"
SRC_URI="https://github.com/LongSoft/UEFITool/archive/refs/tags/A${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="BSD-2"
SLOT="0"
KEYWORDS="~amd64"
IUSE="gui"

DEPEND="
	sys-libs/zlib
	gui? ( dev-qt/qtbase:6[widgets] )
"
RDEPEND="${DEPEND}"

S="${WORKDIR}/UEFITool-A${PV}"

src_install() {
	newbin "${BUILD_DIR}/UEFIExtract/uefiextract" UEFIExtract
	newbin "${BUILD_DIR}/UEFIFind/uefifind" UEFIFind

	if use gui; then
		newbin "${BUILD_DIR}/UEFITool/uefitool" UEFITool
	fi

	dodoc "${S}/README.md"
}
