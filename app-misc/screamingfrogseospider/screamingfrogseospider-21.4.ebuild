# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg unpacker

DESCRIPTION="Spiders websites' links, images, CSS, script and apps from an SEO perspective"
HOMEPAGE="https://www.screamingfrog.co.uk/seo-spider/"
SRC_URI="https://download.screamingfrog.co.uk/products/seo-spider/screamingfrogseospider_${PV}_all.deb"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="~amd64"
IUSE=""
RESTRICT="bindist mirror"

RDEPEND=">=virtual/jre-17
         media-fonts/liberation-fonts"

S="${WORKDIR}"

QA_PREBUILT="opt/${PN}/*"

src_unpack() {
    # The unpacker eclass will handle .deb extraction
    unpacker
}

src_prepare() {
    default
    # Remove bundled JRE as we'll use system Java
    if [[ -d usr/share/screamingfrogseospider/jre ]]; then
        rm -rf usr/share/screamingfrogseospider/jre || die
    fi
}

src_install() {
    # Install the application
    insinto /opt/${PN}
    doins -r usr/share/screamingfrogseospider/*

    # Make launcher script executable
    if [[ -f usr/share/screamingfrogseospider/bin/ScreamingFrogSEOSpiderLauncher ]]; then
        chmod +x "${ED}"/opt/${PN}/bin/ScreamingFrogSEOSpiderLauncher || die
    fi

    # Create wrapper script
    make_wrapper "${PN}" /opt/${PN}/bin/ScreamingFrogSEOSpiderLauncher

    # Install desktop file and icons
    domenu usr/share/applications/screamingfrogseospider.desktop
    for size in 16 32 48 64 128 256 512; do
        if [[ -f usr/share/icons/hicolor/${size}x${size}/apps/screamingfrogseospider.png ]]; then
            newicon -s ${size} usr/share/icons/hicolor/${size}x${size}/apps/screamingfrogseospider.png ${PN}.png
        fi
    done
}

