#!/bin/sh
# Builds the Mono 5.16.1.0 runtime for aarch64-alpine-linux-musl and assembles a tarball that
# installs into the same paths as the cfx x86_64 apk packages (mono-dev=5.16.1.0-r9991 and
# friends, see ../proot_prepare.sh). Run inside an Alpine 3.16 aarch64 chroot/container as root.
#
# Stages (default: all):
#   fetch    download the mono source tarball, the two APKBUILD patches and the cfx x86_64 apks
#   build    configure + make + make install (DESTDIR) of the native runtime
#   package  overlay the native build on the architecture-independent payload of the cfx apks
#            (IL assemblies, csc/mcs, machine.config, ...) and write the final tarball
#
# Environment:
#   MONO_WORK   working directory (default /build-mono)
#   MONO_JOBS   parallel make jobs (default: nproc)
#   MONO_OUT    where the final tarball + SHA256SUMS go (default $MONO_WORK/out)
set -eu

MONO_VER=5.16.1.0
APK_REL=r9991
CHOST=aarch64-alpine-linux-musl
MONO_WORK=${MONO_WORK:-/build-mono}
MONO_JOBS=${MONO_JOBS:-$(nproc)}
MONO_OUT=${MONO_OUT:-$MONO_WORK/out}
CFX_APK_BASE=https://content.cfx.re/mirrors/build/linux/packages/cfx/x86_64

# cfx x86_64 packages whose architecture-independent payload (IL assemblies, scripts, config) is
# reused; every ELF object, header and static library in them is replaced by the native build.
CFX_APKS="mono mono-runtime libmono mono-corlib mono-csc mono-dev mono-reference-assemblies \
	mono-reference-assemblies-4.x mono-reference-assemblies-facades"


SRC_DIR=$MONO_WORK/mono-$MONO_VER
DEST_DIR=$MONO_WORK/dest
STAGE_DIR=$MONO_WORK/stage

fetch() {
	mkdir -p "$MONO_WORK/apk"
	cd "$MONO_WORK"
	[ -f mono-$MONO_VER.tar.bz2 ] || curl -fL --retry 5 -o mono-$MONO_VER.tar.bz2 \
		https://download.mono-project.com/sources/mono/mono-$MONO_VER.tar.bz2
	# patches carried by the APKBUILD the cfx packages are built from (spritsail/mono-apk):
	#  - revert of mono/mono#6222 (threadpool parked_threads semaphore), speeds up the threadpool
	#  - AC_FUNC_STRERROR_R for Mono.Posix (musl's strerror_r is the XSI variant)
	[ -f 928eb4219f6527c23b5924d6e81fa5ba8660f0c4.patch ] || curl -fL --retry 5 \
		-o 928eb4219f6527c23b5924d6e81fa5ba8660f0c4.patch \
		https://github.com/jaykrell/mono/commit/928eb4219f6527c23b5924d6e81fa5ba8660f0c4.patch
	[ -f 6462ec09a11119e36ea98925993f230b1c4eaa75.patch ] || curl -fL --retry 5 \
		-o 6462ec09a11119e36ea98925993f230b1c4eaa75.patch \
		https://github.com/mono/mono/commit/6462ec09a11119e36ea98925993f230b1c4eaa75.patch
	for p in $CFX_APKS; do
		[ -f apk/$p-$MONO_VER-$APK_REL.apk ] || curl -fL --retry 5 -o apk/$p-$MONO_VER-$APK_REL.apk \
			$CFX_APK_BASE/$p-$MONO_VER-$APK_REL.apk
	done
	sha256sum -c "$(dirname "$0")/mono-sources.sha256" 2>/dev/null || {
		echo "NOTE: no/outdated mono-sources.sha256 next to this script; sums of what was fetched:"
		sha256sum mono-$MONO_VER.tar.bz2 *.patch apk/*.apk
	}
}

build() {
	cd "$MONO_WORK"
	rm -rf "$SRC_DIR" "$DEST_DIR"
	tar xjf mono-$MONO_VER.tar.bz2
	cd "$SRC_DIR"
	# the 5.16.1.0 release tarball ships stale x86_64 objects of System.Native under external/corefx;
	# without this the libmono-system-native link fails with "Relocations in generic ELF (EM: 62)"
	find external \( -name '*.o' -o -name '*.lo' -o -name '*.la' -o -name '.libs' \) -prune -exec rm -rf {} +
	for p in 928eb4219f6527c23b5924d6e81fa5ba8660f0c4 6462ec09a11119e36ea98925993f230b1c4eaa75; do
		if patch -p1 -N --dry-run -s -f < "$MONO_WORK/$p.patch" >/dev/null 2>&1; then
			patch -p1 -N < "$MONO_WORK/$p.patch"
		else
			echo "patch $p does not apply cleanly (already in $MONO_VER?), skipping"
		fi
	done
	for p in "$(dirname "$0")"/mono-*.patch; do
		[ -f "$p" ] || continue
		echo "applying $(basename "$p")"
		patch -p1 -N < "$p"
	done

	# same as the APKBUILD: no hardcoded lib directory in the dllmap config
	sed -i 's|$mono_libdir/||g' data/config.in

	# mono/mini/Makefile runs `python genmdesc.py` (python 2 in the APKBUILD's day); the script also
	# runs under python 3, so provide a `python` shim without touching the system
	mkdir -p "$MONO_WORK/bin"
	ln -sf "$(command -v python3)" "$MONO_WORK/bin/python"
	export PATH="$MONO_WORK/bin:$PATH"

	export CFLAGS="${CFLAGS:--O2} -fno-strict-aliasing"
	export CXXFLAGS="${CXXFLAGS:--O2}"

	# The class libraries (mscorlib, System.*, csc, mcs, ...) are architecture-independent IL and
	# are taken verbatim from the cfx x86_64 packages in the package stage, so only the native
	# runtime is built here (--disable-mcs-build).
	./autogen.sh \
		--build=$CHOST \
		--host=$CHOST \
		--prefix=/usr \
		--sysconfdir=/etc \
		--mandir=/usr/share/man \
		--infodir=/usr/share/info \
		--localstatedir=/var \
		--disable-dependency-tracking \
		--disable-system-aot \
		--disable-rpath \
		--disable-boehm \
		--with-sgen=yes \
		--with-static-mono=yes \
		--enable-parallel-mark \
		--with-x=no \
		--with-libgc=none \
		--with-mcs-docs=no \
		--with-ikvm-native=no \
		--disable-mcs-build

	make -j"$MONO_JOBS"
	make -j1 DESTDIR="$DEST_DIR" install

	rm -f "$DEST_DIR"/usr/lib/*.la
	rm -rf "$DEST_DIR"/usr/lib/mono/*/Mono.Security.Win32*
}

is_elf() {
	[ "$(head -c 4 "$1" 2>/dev/null | tr -d '\0' | od -An -c | tr -d ' \n')" = "177ELF" ]
}

package() {
	rm -rf "$STAGE_DIR"
	mkdir -p "$STAGE_DIR" "$MONO_OUT"
	for p in $CFX_APKS; do
		tar -xzf "$MONO_WORK/apk/$p-$MONO_VER-$APK_REL.apk" -C "$STAGE_DIR" --exclude='.PKGINFO' --exclude='.SIGN.*' 2>/dev/null || true
	done
	# drop everything architecture-specific from the x86_64 payload
	rm -rf "$STAGE_DIR/usr/include" "$STAGE_DIR/usr/lib/pkgconfig"
	find "$STAGE_DIR" -type f \( -name '*.a' -o -name '*.so' -o -name '*.so.*' \) -delete
	find "$STAGE_DIR" -type f | while read -r f; do
		if is_elf "$f"; then
			echo "dropping x86_64 ELF file ${f#$STAGE_DIR}"
			rm -f "$f"
		fi
	done
	# overlay the native aarch64 build (runtime, static + shared libmonosgen, headers, .pc files,
	# libMonoPosixHelper, libmono-btls-shared, libmono-native, etc/mono/*)
	cp -a "$DEST_DIR"/. "$STAGE_DIR"/
	# the shared runtime library is also what the x86_64 libmono package ships as
	# libmonosgen-2.0.so.1; keep the libtool symlink layout
	rm -rf "$STAGE_DIR"/usr/share/man "$STAGE_DIR"/usr/share/info

	# sanity checks: the things the FXServer build and the proot packaging script consume
	for f in usr/lib/libmonosgen-2.0.a usr/include/mono-2.0/mono/jit/jit.h usr/bin/mono \
		usr/bin/csc usr/bin/mcs usr/lib/mono/4.5/mscorlib.dll usr/lib/mono/4.5/csc.exe \
		usr/lib/mono/4.5/Facades/System.Runtime.dll usr/lib/mono/4.5/Facades/System.IO.dll \
		usr/lib/libMonoPosixHelper.so usr/lib/libmono-btls-shared.so etc/mono/4.5/machine.config \
		etc/mono/config; do
		[ -e "$STAGE_DIR/$f" ] || { echo "missing $f in staged tree"; exit 1; }
	done

	out=mono-$MONO_VER-$APK_REL-aarch64-musl.tar.xz
	# busybox tar (no --owner/--group); everything in the stage is root-owned already
	tar -C "$STAGE_DIR" --numeric-owner -cf - etc usr | xz -T0 -6 > "$MONO_OUT/$out"
	(cd "$MONO_OUT" && sha256sum "$out" | tee "$out.sha256")
	echo "wrote $MONO_OUT/$out"
}

case "${1:-all}" in
	fetch) fetch ;;
	build) build ;;
	package) package ;;
	all) fetch; build; package ;;
	*) echo "usage: $0 [fetch|build|package|all]"; exit 2 ;;
esac
