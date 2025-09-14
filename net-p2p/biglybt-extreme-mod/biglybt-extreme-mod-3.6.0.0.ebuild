# Copyright 2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop java-pkg-2

MY_PV="3.6.0.0"
MY_DATE="20240425"
DESCRIPTION="BiglyBT Extreme Mod by SB-Innovation"
HOMEPAGE="https://www.sb-innovation.de/showthread.php?t=13781"
SRC_URI="https://www.sb-innovation.de/attachment.php?attachmentid=21721 -> BiglyBT_${MY_PV}_${MY_DATE}.zip
         https://files.biglybt.com/installer/BiglyBT_Installer.sh -> BiglyBT_Installer_${MY_PV}.sh"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~x86"

RDEPEND=">=virtual/jre-1.8:*"
DEPEND="${RDEPEND}
	app-arch/unzip"

S="${WORKDIR}"

src_unpack() {
	unpack BiglyBT_${MY_PV}_${MY_DATE}.zip
	cp "${DISTDIR}/BiglyBT_Installer_${MY_PV}.sh" "${S}"
}

src_prepare() {
	default
	chmod +x BiglyBT_Installer_${MY_PV}.sh
}

src_install() {
	# Install BiglyBT
	"${S}/BiglyBT_Installer_${MY_PV}.sh" -q -dir "${ED}/opt/${PN}" || die "BiglyBT installation failed"

	# Install Java
	einfo "Downloading and installing Java..."
	wget -O "${T}/jre.tar.gz" "https://github.com/adoptium/temurin22-binaries/releases/download/jdk-22%2B36/OpenJDK22U-jdk_x64_linux_hotspot_22.0.0_36.tar.gz" || die "Failed to download Java"
	mkdir -p "${ED}/opt/${PN}/jre"
	tar -xzf "${T}/jre.tar.gz" --strip-components 1 -C "${ED}/opt/${PN}/jre" || die "Failed to extract Java"

	# Modify BiglyBT startup script
	sed -i -e '/^AUTOUPDATE_SCRIPT/ s/^.*/AUTOUPDATE_SCRIPT=0/' \
		-e '/^JAVA_PROGRAM_DIR/ s/^.*/JAVA_PROGRAM_DIR="${HOME}\/biglybt\/jre\/bin\/"/' \
		"${ED}/opt/${PN}/biglybt" || die "Failed to modify BiglyBT startup script"

	# Create java.vmoptions file
	cat <<EOF > "${ED}/opt/${PN}/java.vmoptions"
--patch-module=java.base=ghostfucker_utils.jar
--add-exports=java.base/sun.net.www.protocol=ALL-UNNAMED
--add-exports=java.base/sun.net.www.protocol.http=ALL-UNNAMED
--add-exports=java.base/sun.net.www.protocol.https=ALL-UNNAMED
--add-opens=java.base/java.net=ALL-UNNAMED
-Dorg.glassfish.jaxb.runtime.v2.bytecode.ClassTailor.noOptimize=true
EOF

	# Create launcher script
	cat <<EOF > "${T}/${PN}"
#!/bin/sh
cd /opt/${PN}
exec ./biglybt "\$@"
EOF
	dobin "${T}/${PN}"

	# Desktop integration
	make_desktop_entry "${PN}" "BiglyBT Extreme Mod" "${PN}" "Network;P2P"
}

pkg_postinst() {
	elog "BiglyBT Extreme Mod has been installed to /opt/${PN}"
	elog "You can run it by typing '${PN}' in the terminal"
	elog "or by clicking the desktop icon."
	elog ""
	elog "Please note that this is a modified version of BiglyBT"
	elog "and may not be suitable for all users. Use at your own risk."
}

