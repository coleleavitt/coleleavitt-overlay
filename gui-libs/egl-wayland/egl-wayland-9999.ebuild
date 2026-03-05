# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit meson-multilib git-r3

DESCRIPTION="NVIDIA wayland EGL external platform library (patched: explicit sync deadlock fix)"
HOMEPAGE="https://github.com/coleleavitt/egl-wayland/"

EGIT_REPO_URI="https://github.com/coleleavitt/egl-wayland.git"
EGIT_BRANCH="coleleavitt/dev"

LICENSE="MIT"
SLOT="0"
KEYWORDS=""

RDEPEND="
	dev-libs/wayland[${MULTILIB_USEDEP}]
	x11-libs/libdrm[${MULTILIB_USEDEP}]
"
DEPEND="
	${RDEPEND}
	>=dev-libs/wayland-protocols-1.34
	>=gui-libs/eglexternalplatform-1.1-r1
	media-libs/libglvnd
"
BDEPEND="
	dev-util/wayland-scanner
"

PATCHES=(
	"${FILESDIR}"/${PN}-1.1.6-remove-werror.patch
)
