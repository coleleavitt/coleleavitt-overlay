# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="WebKitGTK 2.48.7 binary package (webkit2gtk-4.1) from Ubuntu 22.04"
HOMEPAGE="https://webkitgtk.org"
SRC_URI=""

LICENSE="LGPL-2+ BSD"
SLOT="4.1"
KEYWORDS="amd64"
IUSE="gir +introspection"
RESTRICT="strip"

RDEPEND="
	>=dev-libs/glib-2.56.0:2
	>=x11-libs/gtk+-3.22.0:3[introspection?]
	>=net-libs/libsoup-3.0.0:3.0
	>=dev-libs/libxml2-2.8.0:2
	>=media-libs/harfbuzz-0.9.18:=
	>=x11-libs/cairo-1.16.0
	>=media-libs/fontconfig-2.13.0:1.0
	>=media-libs/freetype-2.9.0:2
	>=x11-libs/libXcomposite-0.4
	>=x11-libs/libXdamage-1.1
	>=x11-libs/libXrender-0.9.8
	>=x11-libs/libXt-1.1.4
	>=dev-libs/libxslt-1.1.7
	>=gui-libs/wpebackend-fdo-1.10.0:1.0
	>=sys-libs/zlib-1.2.8
	introspection? ( >=dev-libs/gobject-introspection-1.32.0:= )
"

DEPEND="${RDEPEND}"
PROVIDES="net-libs/webkit-gtk:4.1"

S="${WORKDIR}/webkit2gtk-extracted"

src_unpack() {
	mkdir -p "${S}"
	cd "${S}"
	tar -xJf "${FILESDIR}/webkit2gtk-${PV}-ubuntu-binaries.tar.xz" || die "Failed to extract tarball"
}

src_install() {
	# Install all extracted files
	cp -R "${S}"/* "${D}/" || die "Failed to install files"
	
	# Fix Ubuntu paths to Gentoo standard locations
	if [[ -d "${D}/usr/lib/x86_64-linux-gnu" ]]; then
		mkdir -p "${D}/usr/lib64"
		mv "${D}/usr/lib/x86_64-linux-gnu"/* "${D}/usr/lib64/" || die "Failed to move libraries"
		rmdir "${D}/usr/lib/x86_64-linux-gnu" || true
	fi
	
	# Fix permissions
	find "${D}" -type f -exec chmod 644 {} \; || die "Failed to set file permissions"
	find "${D}" -name "*.so*" -exec chmod 755 {} \; || die "Failed to set library permissions"
	find "${D}/usr/lib64/webkit2gtk-4.1" -type f -exec chmod 755 {} \; 2>/dev/null || true
	
	# Create compatibility symlinks
	dosym libwebkit2gtk-4.1.so.0 /usr/lib64/libwebkit2gtk-4.1.so
	dosym libjavascriptcoregtk-4.1.so.0 /usr/lib64/libjavascriptcoregtk-4.1.so
}

pkg_postinst() {
	einfo "WebKitGTK 2.48.7 (webkit2gtk-4.1) binary package installed successfully!"
	einfo ""
	einfo "This provides the webkit2gtk-4.1 API for Tauri and other applications."
	einfo ""
	einfo "To verify installation:"
	einfo "  pkg-config --modversion webkit2gtk-4.1"
	einfo "  pkg-config --cflags webkit2gtk-4.1"
}
