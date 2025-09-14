# Copyright 2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg-utils

DESCRIPTION="A privacy-first, open-source platform for knowledge management and collaboration"
HOMEPAGE="https://logseq.com/"
SRC_URI="https://github.com/logseq/logseq/releases/download/${PV}/Logseq-linux-x64-${PV}.zip"

LICENSE="AGPL-3.0"
SLOT="0"
KEYWORDS="~amd64"

DEPEND=""
RDEPEND="${DEPEND}"
BDEPEND="app-arch/unzip"

S="${WORKDIR}/Logseq-linux-x64"

QA_PREBUILT="opt/${PN}/*"

src_install() {
    insinto /opt/${PN}
    doins -r .

    # Make binaries and libraries executable
    fperms +x /opt/${PN}/Logseq
    fperms +x /opt/${PN}/chrome-sandbox
    fperms +x /opt/${PN}/chrome_crashpad_handler
    fperms +x /opt/${PN}/libEGL.so
    fperms +x /opt/${PN}/libGLESv2.so
    fperms +x /opt/${PN}/libffmpeg.so
    fperms +x /opt/${PN}/libvk_swiftshader.so
    fperms +x /opt/${PN}/libvulkan.so.1

    # Create symlink in /usr/bin
    dosym ../opt/${PN}/Logseq /usr/bin/logseq

    # Install icon
    newicon "resources/app/icons/logseq.png" "${PN}.png"

    # Create desktop entry
    make_desktop_entry ${PN} "Logseq" ${PN} "Office;ProjectManagement"
}

pkg_postinst() {
    xdg_icon_cache_update
    xdg_desktop_database_update
}

pkg_postrm() {
    xdg_icon_cache_update
    xdg_desktop_database_update
}

