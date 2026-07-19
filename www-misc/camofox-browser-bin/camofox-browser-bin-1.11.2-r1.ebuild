# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..15} )

inherit optfeature python-any-r1

# Upstream is published to npm under the @askjo scope; the runtime browser
# (Camoufox, a Firefox fork) is a separate GitHub release resolved by the
# bundled camoufox-js. We pin the exact Camoufox release that camoufox-js
# (>=0.10.0, shipped in this version) selects, and fetch it as a real,
# hash-verified distfile instead of downloading it unverified at build time.
MY_PN="camofox-browser"
MY_SCOPE="@askjo"

# Camoufox browser release selected by camoufox-js for this package version.
# camoufox-js parses the asset name "camoufox-<CVER>-<CREL>-lin.<arch>.zip"
# as version=<CVER>, release=<CREL> and writes them into version.json.
CAMOUFOX_CVER="152.0.4"
CAMOUFOX_CREL="beta.28"
CAMOUFOX_TAG="v${CAMOUFOX_CVER}-${CAMOUFOX_CREL}"

DESCRIPTION="Anti-detection browser automation server over the Camoufox stealth engine"
HOMEPAGE="https://github.com/jo-inc/camofox-browser"

SRC_URI="
	https://registry.npmjs.org/${MY_SCOPE}/${MY_PN}/-/${MY_PN}-${PV}.tgz -> ${P}.tgz
	amd64? (
		https://github.com/daijro/camoufox/releases/download/${CAMOUFOX_TAG}/camoufox-${CAMOUFOX_CVER}-${CAMOUFOX_CREL}-lin.x86_64.zip
	)
	arm64? (
		https://github.com/daijro/camoufox/releases/download/${CAMOUFOX_TAG}/camoufox-${CAMOUFOX_CVER}-${CAMOUFOX_CREL}-lin.arm64.zip
	)
"
S="${WORKDIR}/package"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

# network-sandbox: `npm install` fetches the production dependency tree from
#   the npm registry at build time (upstream ships no lockfile and no vendored
#   node_modules, so per-arch resolution at build time is the honest option).
# mirror: large third-party blobs, not for Gentoo mirrors.
# strip/QA_PREBUILT: the Camoufox bundle and one prebuilt N-API addon (impit)
#   are shipped as-is; do not strip them.
RESTRICT="network-sandbox mirror strip"
QA_PREBUILT="opt/${PN}/.*"

# Runtime is Node.js (>=22 per package.json engines). npm installs the
# dependency tree; unzip unpacks the Camoufox browser zip; Python backs
# node-gyp for the better-sqlite3 native build.
BDEPEND="
	>=net-libs/nodejs-22[npm]
	app-arch/unzip
	${PYTHON_DEPS}
"

# The Camoufox binary is a Firefox fork and needs the usual Firefox runtime
# libraries. Mirrors the set used by our other Firefox-fork -bin packages.
RDEPEND="
	>=net-libs/nodejs-22
	app-accessibility/at-spi2-core:2
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	media-libs/mesa
	sys-apps/dbus
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libxkbcommon
	x11-libs/pango
"

# Where the packaged Camoufox browser bundle lives. camoufox-js honours the
# CAMOUFOX_INSTALL_DIR environment variable for both fetching and launching,
# so the launcher points it here — no ~/.cache symlink dance required.
CAMOFOX_HOME="/opt/${PN}"
CAMOUFOX_DIR="${CAMOFOX_HOME}/camoufox"
NODE_APP_DIR="/usr/lib/node_modules/${MY_SCOPE}/${MY_PN}"

pkg_setup() {
	python-any-r1_pkg_setup
}

src_unpack() {
	# Application tarball -> ${WORKDIR}/package
	unpack "${P}.tgz"

	# Camoufox browser zip -> ${WORKDIR}/camoufox (flat bundle)
	local zip
	if use amd64; then
		zip="camoufox-${CAMOUFOX_CVER}-${CAMOUFOX_CREL}-lin.x86_64.zip"
	else
		zip="camoufox-${CAMOUFOX_CVER}-${CAMOUFOX_CREL}-lin.arm64.zip"
	fi
	mkdir -p "${WORKDIR}/camoufox" || die
	pushd "${WORKDIR}/camoufox" >/dev/null || die
	unpack "${zip}"
	popd >/dev/null || die
}

src_prepare() {
	default

	# Upstream bugfix (server.js:950): VirtualDisplay.get() is async in
	# camoufox-js, so the missing `await` serialises a Promise into the Xvfb
	# display value ("cannot open display: [object Promise]"). Patch it.
	sed -i \
		-e 's/vdDisplay = localVirtualDisplay.get();/vdDisplay = await localVirtualDisplay.get();/' \
		server.js || die "await bugfix sed failed"
	grep -q 'vdDisplay = await localVirtualDisplay.get();' server.js \
		|| die "await bugfix did not apply"
}

src_compile() {
	# Keep npm entirely inside the build tree; never touch the real HOME.
	export HOME="${WORKDIR}/.home"
	export npm_config_cache="${WORKDIR}/.npm"
	export npm_config_update_notifier=false
	export npm_config_fund=false
	export npm_config_audit=false
	mkdir -p "${HOME}" "${npm_config_cache}" || die

	# Install production deps only. --ignore-scripts is deliberate:
	#   * skips upstream's postinstall Camoufox fetch (we ship it as a distfile)
	#   * skips playwright-core's browser download (unused; camoufox is the engine)
	# The impit N-API addon ships as a prebuilt platform package (no build).
	npm install --omit=dev --ignore-scripts --no-audit --no-fund --no-save \
		|| die "npm install failed"

	# better-sqlite3 (a camoufox-js dependency) is the one package that needs a
	# real native build; --ignore-scripts skipped its install hook above.
	#
	# Build it *from source* so the binding matches the exact Node.js ABI on
	# this system. prebuild-install would otherwise fetch a prebuilt binary
	# built against whatever Node.js the upstream CI used, which then fails at
	# runtime with "NODE_MODULE_VERSION NNN ... requires NODE_MODULE_VERSION
	# MMM". node-gyp (bundled with npm) does the compile; python + a C++
	# toolchain back it.
	npm_config_build_from_source=true npm rebuild better-sqlite3 \
		|| die "better-sqlite3 native build failed"

	# Fail loudly if the produced binding does not load against the running
	# Node.js (guards against a stray prebuilt binary with the wrong ABI).
	node -e 'require("better-sqlite3")(":memory:").close()' \
		|| die "better-sqlite3 binding does not load against this Node.js (ABI mismatch)"

	# Trim node-gyp build scaffolding: keep only the final loadable binding,
	# drop intermediate objects and the test addon that gyp leaves behind.
	rm -rf node_modules/better-sqlite3/build/Release/obj.target \
		node_modules/better-sqlite3/build/Release/.deps \
		node_modules/better-sqlite3/build/Release/test_extension.node \
		node_modules/better-sqlite3/build/Release/obj \
		|| die
}

src_install() {
	# --- Node application (JS + bundled node_modules) ---
	# Use -dR --preserve=mode,timestamps (not -a): keep symlinks and exec bits
	# but let portage own the files. Preserving source ownership is both
	# unnecessary (portage normalises it) and fragile under fakeroot.
	dodir "$(dirname "${NODE_APP_DIR}")"
	cp -dR --preserve=mode,timestamps "${S}" "${ED}${NODE_APP_DIR}" \
		|| die "failed to install node app"

	# --- Camoufox browser bundle ---
	dodir "${CAMOUFOX_DIR}"
	cp -dR --preserve=mode,timestamps "${WORKDIR}/camoufox/." "${ED}${CAMOUFOX_DIR}/" \
		|| die "failed to install camoufox"

	# camoufox-js validates a version.json that its own fetcher would have
	# written (it is NOT part of the release zip). Synthesise it with the
	# exact fields parsed from the asset name so the runtime accepts the
	# bundle instead of trying to re-download it.
	cat > "${ED}${CAMOUFOX_DIR}/version.json" <<-EOF || die
		{"version":"${CAMOUFOX_CVER}","release":"${CAMOUFOX_CREL}"}
	EOF

	# Make sure the browser launcher bits are executable (zip usually keeps
	# them, but be defensive).
	local b
	for b in camoufox-bin camoufox; do
		[[ -f "${ED}${CAMOUFOX_DIR}/${b}" ]] && fperms 0755 "${CAMOUFOX_DIR}/${b}"
	done

	# --- Launcher ---
	# Points camoufox-js at the packaged browser via CAMOUFOX_INSTALL_DIR
	# (respecting any user override) and runs the ESM entrypoint under Node.
	#
	# Invoke the system Node by absolute path, NOT bare `node`: the
	# better-sqlite3 binding is compiled against this exact Node.js ABI at
	# build time, and a version manager (nvm/fnm/volta) earlier in the user's
	# PATH would otherwise shadow it and trigger an ABI mismatch
	# ("undefined symbol" / "NODE_MODULE_VERSION") at browser launch.
	cat > "${T}/${PN}" <<-EOF || die
		#!/usr/bin/env bash
		set -euo pipefail
		: "\${CAMOUFOX_INSTALL_DIR:=${CAMOUFOX_DIR}}"
		export CAMOUFOX_INSTALL_DIR
		exec /usr/bin/node "${NODE_APP_DIR}/bin/camofox-browser.js" "\$@"
	EOF
	dobin "${T}/${PN}"

	# --- Docs ---
	dodoc "${S}/README.md"
}

pkg_postinst() {
	elog "camofox-browser is a REST API server. Start it with:"
	elog ""
	elog "    ${PN}"
	elog ""
	elog "It listens on port 9377 by default (override with CAMOFOX_PORT or PORT)."
	elog ""
	elog "The Camoufox browser bundle is installed read-only at:"
	elog "    ${CAMOUFOX_DIR}"
	elog "To use a different/updatable browser cache, export CAMOUFOX_INSTALL_DIR"
	elog "to a writable path before launching."
	elog ""
	optfeature "hardware-free headed mode (recommended for stealth)" "x11-base/xorg-server[xvfb]"
	optfeature "YouTube transcript extraction plugin" net-misc/yt-dlp
}
