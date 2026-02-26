# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MODULES_OPTIONAL_IUSE=+modules
inherit desktop dot-a eapi9-pipestatus eapi9-ver flag-o-matic linux-mod-r1
inherit readme.gentoo-r1 systemd toolchain-funcs unpacker user-info git-r3

# Use the 590 driver version for userspace components
NV_DRIVER_VERSION="590.48.01"
MODULES_KERNEL_MAX=6.99
NV_URI="https://download.nvidia.com/XFree86/"

DESCRIPTION="NVIDIA Accelerated Graphics Driver (live git kernel modules)"
HOMEPAGE="https://www.nvidia.com/ https://github.com/coleleavitt/open-gpu-kernel-modules"

# Git repo for kernel modules (your fork with patches)
EGIT_REPO_URI="https://github.com/coleleavitt/open-gpu-kernel-modules.git"
EGIT_BRANCH="main"

SRC_URI="
	amd64? ( ${NV_URI}Linux-x86_64/${NV_DRIVER_VERSION}/NVIDIA-Linux-x86_64-${NV_DRIVER_VERSION}.run )
	arm64? ( ${NV_URI}Linux-aarch64/${NV_DRIVER_VERSION}/NVIDIA-Linux-aarch64-${NV_DRIVER_VERSION}.run )
	$(printf "${NV_URI}%s/%s-${NV_DRIVER_VERSION}.tar.bz2 " \
		nvidia-{installer,modprobe,persistenced,settings,xconfig}{,})
"
S=${WORKDIR}

LICENSE="
	NVIDIA-2025 Apache-2.0 Boost-1.0 BSD BSD-2 GPL-2 MIT ZLIB
	curl openssl public-domain
"
SLOT="0/590"
KEYWORDS=""
IUSE="
	+X abi_x86_32 abi_x86_64 +kernel-open persistenced powerd
	+static-libs +tools wayland
"

COMMON_DEPEND="
	acct-group/video
	X? ( x11-libs/libpciaccess )
	persistenced? (
		acct-user/nvpd
		net-libs/libtirpc:=
	)
	tools? (
		>=app-accessibility/at-spi2-core-2.46:2
		dev-libs/glib:2
		dev-libs/jansson:=
		media-libs/harfbuzz:=
		x11-libs/cairo
		x11-libs/gdk-pixbuf:2
		x11-libs/gtk+:3[X]
		x11-libs/libX11
		x11-libs/libXext
		x11-libs/libXxf86vm
		x11-libs/pango
	)
"
RDEPEND="
	${COMMON_DEPEND}
	dev-libs/openssl:0/3
	sys-libs/glibc
	X? (
		media-libs/libglvnd[X,abi_x86_32(-)?]
		x11-libs/libX11[abi_x86_32(-)?]
		x11-libs/libXext[abi_x86_32(-)?]
	)
	powerd? ( sys-apps/dbus[abi_x86_32(-)?] )
	wayland? (
		>=gui-libs/egl-gbm-1.1.1-r2[abi_x86_32(-)?]
		>=gui-libs/egl-wayland-1.1.13.1[abi_x86_32(-)?]
		gui-libs/egl-wayland2[abi_x86_32(-)?]
		X? ( gui-libs/egl-x11[abi_x86_32(-)?] )
	)
"
DEPEND="
	${COMMON_DEPEND}
	static-libs? (
		x11-base/xorg-proto
		x11-libs/libX11
		x11-libs/libXext
	)
	tools? (
		dev-util/vulkan-headers
		media-libs/libglvnd
		sys-apps/dbus
		x11-base/xorg-proto
		x11-libs/libXrandr
		x11-libs/libXv
		x11-libs/libvdpau
	)
"
BDEPEND="
	app-alternatives/awk
	sys-devel/m4
	virtual/pkgconfig
"

QA_PREBUILT="lib/firmware/* usr/bin/* usr/lib*"

PATCHES=(
	"${FILESDIR}"/nvidia-modprobe-390.141-uvm-perms.patch
	"${FILESDIR}"/nvidia-settings-530.30.02-desktop.patch
)

pkg_setup() {
	use modules && [[ ${MERGE_TYPE} != binary ]] || return

	get_version
	require_configured_kernel

	local CONFIG_CHECK="
		PROC_FS
		~DRM_KMS_HELPER
		~DRM_FBDEV_EMULATION
		~SYSVIPC
		~!LOCKDEP
		~!PREEMPT_RT
		~!RANDSTRUCT_FULL
		~!RANDSTRUCT_PERFORMANCE
		~!SLUB_DEBUG_ON
		!DEBUG_MUTEXES
		$(usev powerd '~CPU_FREQ')
	"

	kernel_is -ge 6 11 && linux_chkconfig_present DRM_FBDEV_EMULATION &&
		CONFIG_CHECK+=" DRM_TTM_HELPER"

	use amd64 && kernel_is -ge 5 8 && CONFIG_CHECK+=" X86_PAT"
	use kernel-open && CONFIG_CHECK+=" MMU_NOTIFIER"

	local drm_helper_msg="Cannot be directly selected in the kernel's config menus, and may need
	selection of a DRM device even if unused, e.g. CONFIG_DRM_QXL=m or
	DRM_AMDGPU=m (among others, consult the kernel config's help), can
	also use DRM_NOUVEAU=m as long as built as module *not* built-in."
	local ERROR_DRM_KMS_HELPER="CONFIG_DRM_KMS_HELPER: is not set but is needed for nvidia-drm.modeset=1"
	local ERROR_DRM_TTM_HELPER="CONFIG_DRM_TTM_HELPER: is not set but is needed for kernel 6.11+"
	local ERROR_DRM_FBDEV_EMULATION="CONFIG_DRM_FBDEV_EMULATION: is not set but is needed for nvidia-drm.fbdev=1"
	local ERROR_MMU_NOTIFIER="CONFIG_MMU_NOTIFIER: is not set but needed for USE=kernel-open"
	local ERROR_PREEMPT_RT="CONFIG_PREEMPT_RT: is set but unsupported by NVIDIA upstream"

	linux-mod-r1_pkg_setup
}

src_unpack() {
	# Unpack the userspace driver components
	unpacker NVIDIA-Linux-x86_64-${NV_DRIVER_VERSION}.run

	# Unpack auxiliary tarballs
	for tarball in nvidia-{modprobe,persistenced,settings,xconfig}-${NV_DRIVER_VERSION}.tar.bz2; do
		unpack ${tarball}
	done

	# Clone kernel module source from git
	git-r3_src_unpack
}

src_prepare() {
	# Rename directories
	rm -f nvidia-modprobe && mv nvidia-modprobe{-${NV_DRIVER_VERSION},} || die
	rm -f nvidia-persistenced && mv nvidia-persistenced{-${NV_DRIVER_VERSION},} || die
	rm -f nvidia-settings && mv nvidia-settings{-${NV_DRIVER_VERSION},} || die
	rm -f nvidia-xconfig && mv nvidia-xconfig{-${NV_DRIVER_VERSION},} || die

	# Link the git-cloned kernel modules as kernel-module-source
	ln -s "${WORKDIR}/${P}" "${WORKDIR}/kernel-module-source" || die

	default

	sed 's/__USER__/nvpd/' \
		nvidia-persistenced/init/systemd/nvidia-persistenced.service.template \
		> "${T}"/nvidia-persistenced.service || die

	use X || sed -i 's/"libGLX/"libEGL/' nvidia_{layers,icd}.json || die
	use wayland || sed -i 's/ WAYLAND_LIB_install$//' \
		nvidia-settings/src/Makefile || die
}

src_compile() {
	tc-export AR CC CXX LD OBJCOPY OBJDUMP PKG_CONFIG

	local xnvflags=-fPIC
	tc-is-lto && xnvflags+=" $(test-flags-CC -ffat-lto-objects)"

	local target_arch
	case ${ARCH} in
		amd64) target_arch=x86_64 ;;
		arm64) target_arch=aarch64 ;;
		*) die "Unrecognised architecture: ${ARCH}" ;;
	esac

	NV_ARGS=(
		PREFIX="${EPREFIX}"/usr
		HOST_CC="$(tc-getBUILD_CC)"
		HOST_LD="$(tc-getBUILD_LD)"
		BUILD_GTK2LIB=
		NV_USE_BUNDLED_LIBJANSSON=0
		NV_VERBOSE=1 DO_STRIP= MANPAGE_GZIP= OUTPUTDIR=out
		TARGET_ARCH="${target_arch}"
		WAYLAND_AVAILABLE=$(usex wayland 1 0)
		XNVCTRL_CFLAGS="${xnvflags}"
	)

	if use modules; then
		local o_cflags=${CFLAGS} o_cxxflags=${CXXFLAGS} o_ldflags=${LDFLAGS}

		local modlistargs=video:kernel
		if use kernel-open; then
			modlistargs+=-module-source:kernel-module-source/kernel-open

			filter-flags -fno-plt
			filter-lto
			CC=${KERNEL_CC} CXX=${KERNEL_CXX} strip-unsupported-flags

			LDFLAGS=$(raw-ldflags)
		fi

		local modlist=( nvidia{,-drm,-modeset,-peermem,-uvm}=${modlistargs} )
		local modargs=(
			IGNORE_CC_MISMATCH=yes NV_VERBOSE=1
			SYSOUT="${KV_OUT_DIR}" SYSSRC="${KV_DIR}"
			TARGET_ARCH="${target_arch}"
			$(usev amd64 ARCH=x86_64)
		)

		addpredict "${KV_OUT_DIR}"

		linux-mod-r1_src_compile
		CFLAGS=${o_cflags} CXXFLAGS=${o_cxxflags} LDFLAGS=${o_ldflags}
	fi

	emake "${NV_ARGS[@]}" -C nvidia-modprobe
	use persistenced && emake "${NV_ARGS[@]}" -C nvidia-persistenced
	use X && emake "${NV_ARGS[@]}" -C nvidia-xconfig

	if use tools; then
		CFLAGS="-Wno-deprecated-declarations ${CFLAGS}" \
			emake "${NV_ARGS[@]}" -C nvidia-settings
	elif use static-libs; then
		emake "${NV_ARGS[@]}" BUILD_GTK3LIB=1 \
			-C nvidia-settings/src out/libXNVCtrl.a
	fi
}

src_install() {
	local libdir=$(get_libdir) libdir32=$(ABI=x86 get_libdir)

	NV_ARGS+=( DESTDIR="${D}" LIBDIR="${ED}"/usr/${libdir} )

	local -A paths=(
		[APPLICATION_PROFILE]=/usr/share/nvidia
		[CUDA_ICD]=/etc/OpenCL/vendors
		[EGL_EXTERNAL_PLATFORM_JSON]=/usr/share/egl/egl_external_platform.d
		[FIRMWARE]=/lib/firmware/nvidia/${NV_DRIVER_VERSION}
		[GBM_BACKEND_LIB_SYMLINK]=/usr/${libdir}/gbm
		[GLVND_EGL_ICD_JSON]=/usr/share/glvnd/egl_vendor.d
		[OPENGL_DATA]=/usr/share/nvidia
		[VULKANSC_ICD_JSON]=/usr/share/vulkansc
		[VULKAN_ICD_JSON]=/usr/share/vulkan
		[WINE_LIB]=/usr/${libdir}/nvidia/wine
		[XORG_OUTPUTCLASS_CONFIG]=/usr/share/X11/xorg.conf.d

		[GLX_MODULE_SHARED_LIB]=/usr/${libdir}/xorg/modules/extensions
		[GLX_MODULE_SYMLINK]=/usr/${libdir}/xorg/modules
		[XMODULE_SHARED_LIB]=/usr/${libdir}/xorg/modules
	)

	local skip_files=(
		$(usev !X "libGLX_nvidia libglxserver_nvidia")
		libGLX_indirect
		libnvidia-{gtk,wayland-client} nvidia-{settings,xconfig}
		libnvidia-egl-gbm 15_nvidia_gbm
		libnvidia-egl-wayland 10_nvidia_wayland
		libnvidia-egl-wayland2 99_nvidia_wayland2
		libnvidia-egl-xcb 20_nvidia_xcb.json
		libnvidia-egl-xlib 20_nvidia_xlib.json
		libnvidia-pkcs11.so
	)
	local skip_modules=(
		$(usev !X "nvfbc vdpau xdriver")
		$(usev !modules gsp)
		$(usev !powerd nvtopps)
		installer nvpd
	)
	local skip_types=(
		GLVND_LIB GLVND_SYMLINK EGL_CLIENT.\* GLX_CLIENT.\*
		OPENCL_WRAPPER.\*
		DOCUMENTATION DOT_DESKTOP .\*_SRC DKMS_CONF SYSTEMD_UNIT
	)

	local DOCS=(
		README.txt NVIDIA_Changelog supported-gpus/supported-gpus.json
		nvidia-settings/doc/{FRAMELOCK,NV-CONTROL-API}.txt
	)
	local HTML_DOCS=( html/. )
	einstalldocs

	local DISABLE_AUTOFORMATTING=yes
	local DOC_CONTENTS="\
Trusted users should be in the 'video' group to use NVIDIA devices.
You can add yourself by using: gpasswd -a my-user video

This is a LIVE ebuild pulling kernel modules from:
https://github.com/coleleavitt/open-gpu-kernel-modules

Userspace components are from version ${NV_DRIVER_VERSION}."
	readme.gentoo_create_doc

	if use modules; then
		linux-mod-r1_src_install

		insinto /etc/modprobe.d
		newins "${FILESDIR}"/nvidia-580.conf nvidia.conf

		insinto /usr/share/nvidia
		doins supported-gpus/supported-gpus.json
	fi

	emake "${NV_ARGS[@]}" -C nvidia-modprobe install
	fowners :video /usr/bin/nvidia-modprobe
	fperms 4710 /usr/bin/nvidia-modprobe

	if use persistenced; then
		emake "${NV_ARGS[@]}" -C nvidia-persistenced install
		newconfd "${FILESDIR}"/nvidia-persistenced.confd nvidia-persistenced
		newinitd "${FILESDIR}"/nvidia-persistenced.initd nvidia-persistenced
		systemd_dounit "${T}"/nvidia-persistenced.service
	fi

	if use tools; then
		emake "${NV_ARGS[@]}" -C nvidia-settings install

		doicon nvidia-settings/doc/nvidia-settings.png
		domenu nvidia-settings/doc/nvidia-settings.desktop

		exeinto /etc/X11/xinit/xinitrc.d
		newexe "${FILESDIR}"/95-nvidia-settings-r1 95-nvidia-settings
	fi

	if use static-libs; then
		dolib.a nvidia-settings/src/out/libXNVCtrl.a
		strip-lto-bytecode

		insinto /usr/include/NVCtrl
		doins nvidia-settings/src/libXNVCtrl/NVCtrl{Lib,}.h
	fi

	use X && emake "${NV_ARGS[@]}" -C nvidia-xconfig install

	local m into
	while IFS=' ' read -ra m; do
		! [[ ${#m[@]} -ge 2 && ${m[-1]} =~ MODULE: ]] ||
			[[ " ${m[0]##*/}" =~ ^(\ ${skip_files[*]/%/.*|\\} )$ ]] ||
			[[ " ${m[2]}" =~ ^(\ ${skip_types[*]/%/|\\} )$ ]] ||
			has ${m[-1]#MODULE:} "${skip_modules[@]}" && continue

		case ${m[2]} in
			MANPAGE)
				gzip -dc ${m[0]} | newman - ${m[0]%.gz}
				pipestatus || die
				continue
			;;
			GBM_BACKEND_LIB_SYMLINK) m[4]=../${m[4]};;
			VDPAU_SYMLINK) m[4]=vdpau/; m[5]=${m[5]#vdpau/};;
		esac

		if [[ -v 'paths[${m[2]}]' ]]; then
			into=${paths[${m[2]}]}
		elif [[ ${m[2]} == EXPLICIT_PATH ]]; then
			into=${m[3]}
		elif [[ ${m[2]} == *_BINARY ]]; then
			into=/usr/bin
		elif [[ ${m[3]} == COMPAT32 ]]; then
			use abi_x86_32 || continue
			into=/usr/${libdir32}
		elif [[ ${m[2]} == *_@(LIB|SYMLINK) ]]; then
			into=/usr/${libdir}
		else
			die "No known installation path for ${m[0]}"
		fi
		[[ ${m[3]: -2} == ?/ ]] && into+=/${m[3]%/}
		[[ ${m[4]: -2} == ?/ ]] && into+=/${m[4]%/}

		if [[ ${m[2]} =~ _SYMLINK$ ]]; then
			[[ ${m[4]: -1} == / ]] && m[4]=${m[5]}
			dosym ${m[4]} ${into}/${m[0]}
			continue
		fi
		[[ ${m[0]} =~ ^libnvidia-ngx.so ]] &&
			dosym ${m[0]} ${into}/${m[0]%.so*}.so.1

		printf -v m[1] %o $((m[1] | 0200))
		insopts -m${m[1]}
		insinto ${into}
		doins ${m[0]}
	done < .manifest || die
	insopts -m0644

	: "$(systemd_get_sleepdir)"
	exeinto "${_#"${EPREFIX}"}"
	doexe systemd/system-sleep/nvidia
	dobin systemd/nvidia-sleep.sh
	systemd_dounit systemd/system/nvidia-{hibernate,resume,suspend,suspend-then-hibernate}.service

	dobin nvidia-bug-report.sh

	insinto /usr/share/nvidia/files.d
	doins sandboxutils-filelist.json

	if use powerd; then
		newinitd "${FILESDIR}"/nvidia-powerd.initd nvidia-powerd
		systemd_dounit systemd/system/nvidia-powerd.service

		insinto /usr/share/dbus-1/system.d
		doins nvidia-dbus.conf
	fi

	: "$(systemd_get_systemunitdir)"
	local unitdir=${_#"${EPREFIX}"}
	dosym {"${unitdir}",/etc/systemd/system/systemd-hibernate.service.wants}/nvidia-hibernate.service
	dosym {"${unitdir}",/etc/systemd/system/systemd-hibernate.service.wants}/nvidia-resume.service
	dosym {"${unitdir}",/etc/systemd/system/systemd-suspend.service.wants}/nvidia-suspend.service
	dosym {"${unitdir}",/etc/systemd/system/systemd-suspend.service.wants}/nvidia-resume.service
	dosym {"${unitdir}",/etc/systemd/system/systemd-suspend-then-hibernate.service.wants}/nvidia-suspend-then-hibernate.service
	dosym {"${unitdir}",/etc/systemd/system/systemd-suspend-then-hibernate.service.wants}/nvidia-resume.service
	exeinto /usr/lib/elogind/system-sleep
	newexe "${FILESDIR}"/system-sleep.elogind nvidia
	dosym {/usr/lib,/"${libdir}"}/elogind/system-sleep/nvidia

	insinto "${unitdir}"/systemd-homed.service.d
	newins - 10-nvidia.conf <<-EOF
		[Service]
		Environment=SYSTEMD_HOME_LOCK_FREEZE_SESSION=false
	EOF
	insinto "${unitdir}"/systemd-suspend.service.d
	newins - 10-nvidia.conf <<-EOF
		[Service]
		Environment=SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false
	EOF
	dosym -r "${unitdir}"/systemd-{suspend,hibernate}.service.d/10-nvidia.conf
	dosym -r "${unitdir}"/systemd-{suspend,hybrid-sleep}.service.d/10-nvidia.conf
	dosym -r "${unitdir}"/systemd-{suspend,suspend-then-hibernate}.service.d/10-nvidia.conf

	dosym nvidia-application-profiles-${NV_DRIVER_VERSION}-key-documentation \
		${paths[APPLICATION_PROFILE]}/nvidia-application-profiles-key-documentation

	dostrip -x ${paths[FIRMWARE]}

	insinto /etc/sandbox.d
	newins - 20nvidia <<<'SANDBOX_PREDICT="/dev/nvidiactl:/dev/nvidia-caps:/dev/char"'

	if use modules; then
		echo "install_items+=\" ${EPREFIX}/etc/modprobe.d/nvidia.conf \"" >> \
			"${ED}"/usr/lib/dracut/dracut.conf.d/10-${PN}.conf || die
	fi
}

pkg_preinst() {
	use modules || return

	local g=$(egetent group video | cut -d: -f3)
	[[ ${g} =~ ^[0-9]+$ ]] || die "Failed to determine video group id (got '${g}')"
	sed -i "s/@VIDEOGID@/${g}/" "${ED}"/etc/modprobe.d/nvidia.conf || die

	rm "${ED}"/usr/share/nvidia/supported-gpus.json 2>/dev/null
}

pkg_postinst() {
	linux-mod-r1_pkg_postinst

	readme.gentoo_print_elog

	elog ""
	elog "This is a LIVE ebuild using kernel modules from your GitHub fork:"
	elog "  https://github.com/coleleavitt/open-gpu-kernel-modules"
	elog ""
	elog "Userspace components are from nvidia-drivers-${NV_DRIVER_VERSION}"
	elog ""

	if [[ -r /proc/driver/nvidia/version &&
		$(</proc/driver/nvidia/version) != *"  ${NV_DRIVER_VERSION}  "* ]]; then
		ewarn "Currently loaded NVIDIA modules do not match the newly installed"
		ewarn "libraries. A reboot is recommended."
	fi
}
