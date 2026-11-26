# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker xdg

# Upstream's Ubuntu 26.04 build matches ::gentoo's glibc and Qt 6.10+.
DEB_SUFFIX="1~ubuntu26.04"

DESCRIPTION="Ladybird - a truly independent web browser (official prebuilt)"
HOMEPAGE="https://ladybird.org/"
SRC_URI="
	amd64? (
		https://apt.ladybird.org/pool/main/l/ladybird/ladybird_${PV}-${DEB_SUFFIX}_amd64.deb
		-> ${P}-amd64.deb
	)
	arm64? (
		https://apt.ladybird.org/pool/main/l/ladybird/ladybird_${PV}-${DEB_SUFFIX}_arm64.deb
		-> ${P}-arm64.deb
	)
"
S="${WORKDIR}"

# Bundled: ffmpeg (LGPL-2.1+), ICU (Unicode-3.0), libidn2 and libunistring
# (GPL-2+ LGPL-3+), libdwarf (LGPL-2.1), dbus (AFL-2.1 GPL-2+)
LICENSE="BSD-2 AFL-2.1 GPL-2+ LGPL-2.1 LGPL-2.1+ LGPL-3+ Unicode-3.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
RESTRICT="bindist mirror strip"

# ffmpeg, ICU, libidn2, libunistring, libdwarf and dbus are bundled in
# /opt/ladybird/lib and found through the binaries' $ORIGIN RUNPATH.
RDEPEND="
	>=dev-libs/glib-2.80:2
	dev-libs/wayland
	>=dev-qt/qtbase-6.10.2:6[gui,widgets]
	dev-qt/qtpositioning:6
	media-fonts/liberation-fonts
	media-libs/libglvnd
	media-libs/libpulse
	media-libs/vulkan-loader
	>=sys-libs/glibc-2.43
	x11-libs/libdrm
	x11-libs/libxcb
	x11-libs/xcb-util-wm
"

BDEPEND="dev-util/patchelf"

QA_PREBUILT="opt/ladybird/*"

src_prepare() {
	default

	# The bundled Ubuntu ICU exports versioned symbols (ucnv_*_78), while
	# ::gentoo builds ICU with --disable-renaming under the same sonames. The
	# $ORIGIN RUNPATH would load the bundled copy into the system Qt, which then
	# fails on unversioned symbols. Rename the bundled sonames so the system Qt
	# keeps the system ICU and Ladybird keeps its own.
	local lib=opt/ladybird/lib real soname new f
	local renames=()
	for real in "${lib}"/libicu*.so.*.*; do
		soname=${real##*/}
		soname=${soname%.*}
		new=${soname/.so/-ladybird.so}
		mv "${real}" "${lib}/${new}" || die
		rm "${lib}/${soname}" || die
		patchelf --set-soname "${new}" "${lib}/${new}" || die
		renames+=( --replace-needed "${soname}" "${new}" )
	done
	for f in opt/ladybird/{bin,libexec}/* "${lib}"/libicu*-ladybird.so.*; do
		patchelf "${renames[@]}" "${f}" || die
	done
}

src_install() {
	# The .deb's tree is already FHS-shaped: /opt/ladybird plus the
	# /usr/bin/ladybird symlink, desktop entry, icon, metainfo and D-Bus service.
	cp -a opt usr "${ED}"/ || die
}
