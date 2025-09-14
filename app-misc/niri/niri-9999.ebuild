EAPI="8"
inherit cargo git-r3

DESCRIPTION="Scrollable tiling Wayland compositor"
HOMEPAGE="https://github.com/YaLTeR/niri"
EGIT_REPO_URI="https://github.com/YaLTeR/niri.git"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"

src_unpack() {
    git-r3_src_unpack
    cargo_live_src_unpack
}

src_compile() {
    cargo build --release
}

src_install() {
    dobin target/release/niri
}
