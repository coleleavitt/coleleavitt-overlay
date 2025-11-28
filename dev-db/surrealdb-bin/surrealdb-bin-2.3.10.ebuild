# surrealdb-bin-2.3.10.ebuild
# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="SurrealDB CLI - A scalable, distributed, document-graph database"
HOMEPAGE="https://surrealdb.com https://github.com/surrealdb/surrealdb"

MY_PV="${PV}"

SRC_URI="
	amd64? ( https://github.com/surrealdb/surrealdb/releases/download/v${MY_PV}/surreal-v${MY_PV}.linux-amd64.tgz )
	arm64? ( https://github.com/surrealdb/surrealdb/releases/download/v${MY_PV}/surreal-v${MY_PV}.linux-arm64.tgz )
"

LICENSE="BSL-1.1"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
RESTRICT="strip"

S="${WORKDIR}"

QA_PREBUILT="usr/bin/surreal"

src_install() {
	newbin surreal surreal

	# Create symlink for convenience
	dosym surreal /usr/bin/surrealdb
}

pkg_postinst() {
	elog "SurrealDB CLI has been installed."
	elog ""
	elog "Quick start commands:"
	elog "  surreal start --user root --pass root memory"
	elog "  surreal sql --conn http://localhost:8000 --user root --pass root"
	elog ""
	elog "For your embedded use case with RocksDB:"
	elog "  surreal sql --conn rocksdb://plates_rocksdb --ns azmvd --db plates"
	elog ""
	elog "Documentation: https://surrealdb.com/docs"
}

