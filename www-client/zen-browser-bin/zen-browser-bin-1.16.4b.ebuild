# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="Zen Browser - A fast, privacy-focused Firefox fork"
HOMEPAGE="https://zen-browser.app/"
SRC_URI="
	amd64? ( https://github.com/zen-browser/desktop/releases/download/${PV/_beta/b}/zen.linux-x86_64.tar.xz -> ${P}-x86_64.tar.xz )
	arm64? ( https://github.com/zen-browser/desktop/releases/download/${PV/_beta/b}/zen.linux-aarch64.tar.xz -> ${P}-aarch64.tar.xz )
"

LICENSE="MPL-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="+X"
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
	media-libs/mesa[X?]
	net-print/cups
	sys-apps/dbus
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3[X?]
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
	x11-misc/xdg-utils
"

BDEPEND="app-arch/unzip"

QA_PREBUILT="*"
S="${WORKDIR}"

src_unpack() {
	default
	# The archive extracts to a 'zen' directory
	if [[ -d zen ]]; then
		S="${WORKDIR}/zen"
	fi
}

src_install() {
	# Install to /opt/zen-browser
	local destdir="/opt/zen-browser"
	insinto "${destdir}"
	doins -r ./*

	# Set executable permissions for binaries that exist
	local binaries=(zen-bin zen updater glxtest vaapitest)
	local bin
	for bin in "${binaries[@]}"; do
		if [[ -f "${D}${destdir}/${bin}" ]]; then
			fperms 0755 "${destdir}/${bin}"
		fi
	done

	# Set permissions for pingsender if it exists
	if [[ -f "${D}${destdir}/pingsender" ]]; then
		fperms 0750 "${destdir}/pingsender"
	fi

	# Create wrapper script for better integration
	cat > zen-wrapper <<-EOF || die
#!/bin/bash
exec /opt/zen-browser/zen "\$@"
EOF

	exeinto /usr/bin
	newexe zen-wrapper zen-browser
	dosym zen-browser /usr/bin/zen

	# Install icons (check for available sizes in the actual directory structure)
	local icon_sizes=(16 32 48 64 128)
	local size
	for size in "${icon_sizes[@]}"; do
		local icon_path="browser/chrome/icons/default/default${size}.png"
		if [[ -f "${D}${destdir}/${icon_path}" ]]; then
			newicon -s ${size} "${D}${destdir}/${icon_path}" zen-browser.png
		fi
	done

	# Fallback icon installation - try common locations
	local fallback_icons=(
		"browser/chrome/icons/default/default48.png"
		"browser/chrome/icons/default/default32.png"
		"browser/chrome/icons/default/default16.png"
	)
	local icon_installed=false
	for icon_path in "${fallback_icons[@]}"; do
		if [[ -f "${D}${destdir}/${icon_path}" && "${icon_installed}" == false ]]; then
			newicon "${D}${destdir}/${icon_path}" zen-browser.png
			icon_installed=true
		fi
	done

	# Create desktop entry
	make_desktop_entry "zen-browser %U" "Zen Browser" zen-browser "Network;WebBrowser" \
		"StartupWMClass=zen-alpha\nMimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;\nStartupNotify=true"

	# Disable auto-updates
	insinto "${destdir}/distribution"
	newins - policies.json <<-EOF
{
	"policies": {
		"DisableAppUpdate": true,
		"DisableSystemAddonUpdate": true,
		"ExtensionUpdate": false
	}
}
EOF

	# Install distribution.ini to prevent update checks
	insinto "${destdir}"
	newins - distribution.ini <<-EOF
[Global]
id=zen-gentoo
version=1.0
about=Zen Browser for Gentoo Linux

[Preferences]
app.update.enabled=false
app.update.auto=false
EOF
}

pkg_postinst() {
	xdg_desktop_database_update
	xdg_icon_cache_update

	elog "Zen Browser ${PV} has been installed successfully."
	elog ""
	elog "Your existing profiles in ~/.cache/zen/ will be preserved."
	elog "Launch with: zen-browser or zen"
	elog ""
	elog "New features in version ${PV}:"
	elog "• Added support for 'unload space' context menu item"
	elog "• New about:config options for essentials management"
	elog "• Fixed compact mode and media controller performance"
	elog "• Various stability improvements"
}

pkg_postrm() {
	xdg_desktop_database_update
	xdg_icon_cache_update
}
