# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake desktop xdg git-r3

DESCRIPTION="A low latency KVM FrameRelay implementation for guests with VGA PCI Passthrough"
HOMEPAGE="https://looking-glass.io https://github.com/gnif/LookingGlass"

# Use git with specific B7 tag and submodules
EGIT_REPO_URI="https://github.com/gnif/LookingGlass.git"
EGIT_COMMIT="27fe47cbe2a3a8da986d310ab866f0b646ed68f5"  # B7 stable tag
EGIT_SUBMODULES=( '*' )  # Include all submodules

KEYWORDS="~amd64"
LICENSE="GPL-2"
SLOT="0"
IUSE="binutils gnome pipewire pulseaudio wayland +X"
REQUIRED_USE="|| ( wayland X )"

RDEPEND="
	dev-libs/libconfig
	dev-libs/nettle
	media-libs/freetype
	media-libs/fontconfig
	media-libs/libsdl2
	media-libs/sdl2-ttf
	virtual/glu
	media-libs/libsamplerate
	binutils? ( sys-devel/binutils )
	X? (
		x11-libs/libX11
		x11-libs/libXfixes
		x11-libs/libXi
		x11-libs/libXinerama
		x11-libs/libXScrnSaver
		x11-libs/libXpresent
	)
	wayland? ( dev-libs/wayland )
	media-libs/libpulse
	pipewire? ( media-video/pipewire )
	gnome? ( gui-libs/libdecor )
"

DEPEND="
	${RDEPEND}
	app-emulation/spice-protocol
	wayland? ( dev-libs/wayland-protocols )
"
BDEPEND="
	virtual/pkgconfig
	wayland? ( dev-util/wayland-scanner )
"

CMAKE_USE_DIR="${S}"/client

src_configure() {
	local mycmakeargs=(
		-DENABLE_BACKTRACE=$(usex binutils)
		-DENABLE_X11=$(usex X)
		-DENABLE_WAYLAND=$(usex wayland)
		-DENABLE_PIPEWIRE=$(usex pipewire)
		-DENABLE_PULSEAUDIO=$(usex pulseaudio)
		-DENABLE_LIBDECOR=$(usex gnome)
	)
	cmake_src_configure
}

src_install() {
	einstalldocs
	dobin "${BUILD_DIR}/looking-glass-client"
	newicon -s 128 "${S}/resources/icon-128x128.png" looking-glass-client.png

	if use X && ! use wayland || ! use X && use wayland; then
		domenu "${FILESDIR}/LookingGlass.desktop"
	fi

	if use X && use wayland; then
		domenu "${FILESDIR}/LookingGlass-X.desktop"
		newmenu "${FILESDIR}/LookingGlass.desktop" LookingGlass-Wayland.desktop
	fi
}

pkg_postinst() {
	xdg_pkg_postinst
	elog "Looking Glass B7 Stable installed from git"
	elog "Official stable release (commit 27fe47cb)"
	elog "Includes all required submodules automatically"
	elog "Use the Right Control (Control_R) as the modifier key"
	elog "More information: https://looking-glass.io/wiki/Client/Keyboard_shortcuts"
}
