# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit qmake-utils desktop xdg

DESCRIPTION="Graphical wireless scanner for Linux"
HOMEPAGE="https://sourceforge.net/projects/linssid/"
SRC_URI="mirror://sourceforge/${PN}/${PN}_${PV}.orig.tar.gz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE=""

DEPEND="
	dev-qt/qtcore:5
	dev-qt/qtgui:5
	dev-qt/qtsvg:5
	x11-libs/qwt:6[qt5]
	x11-base/xorg-server
	net-wireless/iw
	net-wireless/wireless-tools
	dev-libs/boost
"
RDEPEND="${DEPEND}
	x11-misc/xdg-utils
"

PATCHES=(
	"${FILESDIR}/${PN}-qwt-6.2.patch"
)

src_prepare() {
	default
	sed -r 's|libqwt-qt5.so|libqwt6-qt5.so|g' -i linssid-app/linssid-app.pro || die
	sed -r 's|/usr/sbin|/usr/bin|g' -i linssid-app/linssid-app.pro || die

	# Fix QWT header include paths - point to qwt6 instead of qwt
	find . -name "*.h" -o -name "*.cpp" | xargs sed -i 's|#include <qwt.h>|#include <qwt6/qwt.h>|g' || die
	find . -name "*.h" -o -name "*.cpp" | xargs sed -i 's|#include <qwt/qwt|#include <qwt6/qwt|g' || die
	find . -name "*.h" -o -name "*.cpp" | xargs sed -i 's|#include <qwt_|#include <qwt6/qwt_|g' || die

	# Fix library path in project file to use pkg-config
	echo 'CONFIG += link_pkgconfig' >> linssid-app/linssid-app.pro
	echo 'PKGCONFIG += Qt5Svg Qt5Widgets Qt5Gui Qt5Core' >> linssid-app/linssid-app.pro

	# Replace existing QWT library references and directly specify the correct path
	sed -i '/LIBS.*libqwt/d' linssid-app/linssid-app.pro || die
	echo 'LIBS += -L/usr/lib64 -lqwt6-qt5' >> linssid-app/linssid-app.pro || die
	echo 'QMAKE_LFLAGS += -Wl,-rpath,/usr/lib64' >> linssid-app/linssid-app.pro || die
}

src_configure() {
	eqmake5 \
		"INCLUDEPATH+=/usr/include/qwt6" \
		"LIBS+=-L/usr/lib64 -lqwt6-qt5"
}

src_compile() {
	emake
}

src_install() {
	emake INSTALL_ROOT="${D}" install
}

