# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN="vesktop"

CHROMIUM_LANGS="
	af am ar bg bn ca cs da de el en-GB en-US es es-419 et fa fi fil fr gu he hi
	hr hu id it ja kn ko lt lv ml mr ms nb nl pl pt-BR pt-PT ro ru sk sl sr sv
	sw ta te th tr uk ur vi zh-CN zh-TW
"

PYTHON_COMPAT=( python3_{11..14} )

inherit chromium-2 desktop linux-info optfeature python-any-r1 unpacker xdg

DESCRIPTION="All-in-one voice and text chat for gamers with Vencord Preinstalled"
HOMEPAGE="https://github.com/Vencord/Vesktop/"
SRC_URI="
	amd64? ( https://github.com/Vencord/Vesktop/releases/download/v${PV}/${MY_PN}-${PV}.tar.gz )
	arm64? ( https://github.com/Vencord/Vesktop/releases/download/v${PV}/${MY_PN}-${PV}-arm64.tar.gz )
"
S="${WORKDIR}/${MY_PN}-${PV}"

BDEPEND="${PYTHON_DEPS}"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip test"

DEPEND="
	app-accessibility/at-spi2-core
	dev-libs/expat
	dev-libs/glib
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	sys-libs/glibc
	x11-libs/cairo
	x11-libs/libdrm
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libdrm
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/pango
	x11-misc/xdg-utils
"

DESTDIR="/opt/${PN}"

QA_PREBUILT="*"

CONFIG_CHECK="~USER_NS"

src_unpack() {
	default
	use arm64 && S="${WORKDIR}/${MY_PN}-${PV}-arm64"
}

src_prepare() {
	default
	# Vencord/Vesktop fix/sync-ipc-hang (34a4c2a): a throwing sync IPC handler left
	# returnValue unset, so non-Discord pages (chrome://gpu, any external URL) hung white.
	"${EPYTHON}" "${FILESDIR}/asar-replace.py" resources/app.asar dist/js/main.js \
		'function nt(e,t){Du.ipcMain.on(e,(r,...n)=>{GE(r.senderFrame,e),r.returnValue=t(r,...n)})}' \
		'function nt(e,t){Du.ipcMain.on(e,(r,...n)=>{try{GE(r.senderFrame,e),r.returnValue=t(r,...n)}catch(o){throw r.returnValue=null,o}})}' \
		|| die "patching app.asar failed"
}

src_configure() {
	default
	chromium_suid_sandbox_check_kernel_config
}

src_install() {

	doicon -s 256 "${FILESDIR}/vesktop-bin.svg"
	domenu "${FILESDIR}/vesktop.desktop"

	exeinto "${DESTDIR}"

	doexe vesktop chrome-sandbox libffmpeg.so libvk_swiftshader.so libvulkan.so.1

	insinto "${DESTDIR}"
	doins chrome_100_percent.pak chrome_200_percent.pak icudtl.dat resources.pak snapshot_blob.bin v8_context_snapshot.bin
	insopts -m0755
	doins -r locales resources

	fowners root "${DESTDIR}/chrome-sandbox"
	fperms 4711 "${DESTDIR}/chrome-sandbox"

	[[ -x chrome_crashpad_handler ]] && doins chrome_crashpad_handler

	dosym "${DESTDIR}/vesktop" "/usr/bin/vesktop-bin"

}

pkg_postinst() {
	optfeature "Desktop notifications support" x11-libs/libnotify
	xdg_pkg_postinst
}
