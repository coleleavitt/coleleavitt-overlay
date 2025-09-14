# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="Zen Browser - A fast, privacy-focused Firefox fork"
HOMEPAGE="https://zen-browser.app/"
SRC_URI="https://github.com/zen-browser/desktop/releases/download/${PV/_beta/b}/zen.linux-x86_64.tar.xz -> ${P}.tar.xz"

LICENSE="MPL-2.0"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="bindist mirror strip"

RDEPEND="
	app-accessibility/at-spi2-core:2
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	media-libs/mesa
	net-print/cups
	sys-apps/dbus
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXcursor
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXi
	x11-libs/libXrandr
	x11-libs/libXrender
	x11-libs/libXtst
	x11-libs/pango
"

QA_PREBUILT="*"
S="${WORKDIR}"

src_install() {
	# Install to /opt/zen to match your existing installation
	local destdir="/opt/zen"

	insinto "${destdir}"
	doins -r zen/*

	# Set executable permissions
	fperms 0755 "${destdir}"/{zen-bin,zen,updater,glxtest,vaapitest}
	fperms 0750 "${destdir}"/pingsender

	# Create symlinks that match your existing setup
	dosym "${destdir}/zen" "/usr/local/bin/zen"
	dosym "${destdir}/zen" "/usr/bin/zen-browser"

	# Install icons
	local size
	for size in 16 32 48 64 128; do
		newicon -s ${size} "zen/browser/chrome/icons/default/default${size}.png" zen.png
	done

	# Create desktop entry
	make_desktop_entry "zen %U" "Zen Browser" zen "Network;WebBrowser" \
		"StartupWMClass=zen-alpha\nMimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;"

	# Disable auto-updates
	insinto "${destdir}/distribution"
	newins - policies.json <<-EOF
	{
		"policies": {
			"DisableAppUpdate": true
		}
	}
	EOF
}

pkg_postinst() {
	xdg_desktop_database_update
	xdg_icon_cache_update

	elog "Zen Browser updated to ${PV}"
	elog "Your existing profiles in ~/.cache/zen/ will be preserved"
	elog "Launch with: zen or zen-browser"
}

pkg_postrm() {
	xdg_desktop_database_update
	xdg_icon_cache_update
}

