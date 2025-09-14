# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
LLVM_COMPAT=( {18..20} )

inherit git-r3 llvm-r2 systemd

DESCRIPTION="Scrollable-tiling Wayland compositor (local fork)"
HOMEPAGE="https://github.com/YaLTeR/niri"
EGIT_REPO_URI="file:///home/cole/RustProjects/forks/niri"

LICENSE="GPL-3+"
# Dependent crate licenses
LICENSE+="
	Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD-2 BSD ISC MIT MPL-2.0
	Unicode-3.0 ZLIB
"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+dbus screencast systemd debug"

REQUIRED_USE="
	screencast? ( dbus )
	systemd? ( dbus )
"

DEPEND="
	dev-libs/glib:2
	dev-libs/libinput:=
	dev-libs/wayland
	<media-libs/libdisplay-info-0.3.0:=
	media-libs/mesa
	sys-auth/seatd:=
	virtual/libudev:=
	x11-libs/cairo
	x11-libs/libxkbcommon
	x11-libs/pango
	x11-libs/pixman
	screencast? ( media-video/pipewire:= )
"

RDEPEND="
	${DEPEND}
	screencast? ( sys-apps/xdg-desktop-portal-gnome )
"

# libclang is required for bindgen when screencast is enabled
BDEPEND="
	virtual/pkgconfig
	dev-util/wayland-scanner
	screencast? ( $(llvm_gen_dep 'llvm-core/clang:${LLVM_SLOT}') )
"

QA_FLAGS_IGNORED="usr/bin/niri"

pkg_setup() {
	if use screencast; then
		llvm-r2_pkg_setup
	fi

	# Check that Rust is available (from rustup or elsewhere)
	if ! command -v rustc >/dev/null 2>&1; then
		die "Rust compiler not found. Please install Rust via rustup or emerge dev-lang/rust-bin"
	fi

	local rust_version=$(rustc --version | cut -d' ' -f2)
	einfo "Using Rust compiler version: ${rust_version}"
}

src_unpack() {
	git-r3_src_unpack
	# Create symlinks to local dependencies since they're path dependencies
	einfo "Setting up local dependencies..."
	# Ensure the parent directory exists
	mkdir -p "${S}/../" || die "Failed to create parent directory"
	# Create symlinks for smithay and pipewire-rs if they don't exist
	if [[ ! -e "${S}/../smithay" ]]; then
		ln -sf "/home/cole/RustProjects/forks/smithay" "${S}/../smithay" || die "Failed to symlink smithay"
	fi
	if [[ ! -e "${S}/../pipewire-rs" ]]; then
		ln -sf "/home/cole/RustProjects/forks/pipewire-rs" "${S}/../pipewire-rs" || die "Failed to symlink pipewire-rs"
	fi
}

src_prepare() {
	# niri-session doesn't work on OpenRC
	if ! use systemd; then
		sed -i 's/niri-session/niri --session/' resources/niri.desktop || die
	fi
	default
}

src_compile() {
	# Build features based on USE flags
	local myfeatures=(
		$(usev dbus)
		$(usev screencast xdp-gnome-screencast)
		$(usev systemd)
	)

	# Convert array to comma-separated string
	local features_str=""
	if [[ ${#myfeatures[@]} -gt 0 ]]; then
		printf -v features_str '%s,' "${myfeatures[@]}"
		features_str="--features=${features_str%,}"
	fi

	# Build command
	local cargo_args=(
		build
		--bin niri
		${features_str}
		--no-default-features
	)

	if ! use debug; then
		cargo_args+=(--release)
	fi

	einfo "Building with: cargo ${cargo_args[*]}"
	cargo "${cargo_args[@]}" || die "cargo build failed"
}

src_install() {
	# Install the binary
	local target_dir="target"
	if use debug; then
		target_dir+="/debug"
	else
		target_dir+="/release"
	fi

	dobin "${target_dir}/niri"

	# Install niri-session script
	dobin resources/niri-session

	# Install systemd units
	if use systemd; then
		systemd_douserunit resources/niri.service
		systemd_douserunit resources/niri-shutdown.target
	fi

	# Install wayland session
	insinto /usr/share/wayland-sessions
	doins resources/niri.desktop

	# Install portal configuration
	insinto /usr/share/xdg-desktop-portal
	doins resources/niri-portals.conf

	# Documentation
	dodoc README.md
	dodoc -r wiki/ || true
}

pkg_postinst() {
	elog ""
	elog "Niri compositor has been installed from your local fork."
	elog ""
	elog "To start niri:"
	if use systemd; then
		elog "  systemctl --user enable niri.service"
		elog "  or from TTY: niri-session"
	else
		elog "  From TTY: niri --session"
	fi
	elog ""
	elog "Portal configuration installed to:"
	elog "  /usr/share/xdg-desktop-portal/niri-portals.conf"
	elog ""
	elog "This configures portals to use:"
	elog "  • GNOME backend for most features"
	elog "  • GTK backend for file chooser and notifications"
	elog "  • gnome-keyring for secrets"
	elog ""
	elog "Local dependencies used:"
	elog "  • smithay: /home/cole/RustProjects/forks/smithay"
	elog "  • pipewire-rs: /home/cole/RustProjects/forks/pipewire-rs"
	elog ""
}

