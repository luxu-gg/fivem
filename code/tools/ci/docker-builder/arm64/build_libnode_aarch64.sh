#!/bin/sh
# Builds cfx's libnode 22 (https://github.com/citizenfx/libnode, tag v22.22.0: upstream Node.js
# v22.22.0 plus the patches in that repository) as a shared library for aarch64 musl, producing
# libnode22.so and libuv.so, the same artifacts the x86_64 build downloads from
# https://content.cfx.re/mirrors/vendor/libnode/legacy22/bin/.
#
# This mirrors the Linux job in that repository's .github/workflows/build.yml (Alpine 3.16,
# clang 13, lld, ./configure --shared) minus the x86-only -mssse3/-m64 flags. Run inside an
# Alpine 3.16 aarch64 chroot/container as root with:
#   apk add git bash curl libgcc linux-headers make python3 xz libatomic clang clang-dev clang-libs
#           llvm13-dev lld libc-dev musl-dev gcc g++ perl
#
# Stages (default: all): fetch (clone + patch), build (configure + make), package (copy + sums)
#
# Environment:
#   LIBNODE_WORK  working directory (default /build-libnode)
#   LIBNODE_TAG   citizenfx/libnode tag (default v22.22.0)
#   LIBNODE_JOBS  parallel make jobs (default: nproc)
#   LIBNODE_OUT   output directory (default $LIBNODE_WORK/out)
set -eu

LIBNODE_WORK=${LIBNODE_WORK:-/build-libnode}
LIBNODE_TAG=${LIBNODE_TAG:-v22.22.0}
LIBNODE_JOBS=${LIBNODE_JOBS:-$(nproc)}
LIBNODE_OUT=${LIBNODE_OUT:-$LIBNODE_WORK/out}
SRC_DIR=$LIBNODE_WORK/libnode

fetch() {
	mkdir -p "$LIBNODE_WORK"
	if [ ! -d "$SRC_DIR/.git" ]; then
		git clone --depth 1 --branch "$LIBNODE_TAG" https://github.com/citizenfx/libnode.git "$SRC_DIR"
	fi
	cd "$SRC_DIR"
	git submodule update --init --depth 1 node
	cd node
	if [ ! -f .cfx-patches-applied ]; then
		for f in ../patches/*.patch; do
			echo "Applying $f..."
			git apply --reject --whitespace=fix "$f"
		done
		# arm64 + clang: node's zlib.gyp only passes -march=armv8-a+aes+crc to gcc, so clang 13 fails
		# on the CRC32 intrinsics in deps/zlib/crc32_simd.c ("Cannot select: intrinsic
		# %llvm.aarch64.crc32b"); the object is only used after a runtime CPU-feature check
		git apply --whitespace=fix "$(dirname "$0")/libnode-zlib-arm64-clang.patch"
		touch .cfx-patches-applied
	fi
	git -C "$SRC_DIR" rev-parse HEAD > "$LIBNODE_WORK/libnode.commit"
	git rev-parse HEAD >> "$LIBNODE_WORK/libnode.commit"
}

build() {
	cd "$SRC_DIR/node"
	export CC=clang
	export CXX=clang++
	export CXXFLAGS="-g -std=c++20"
	export LDFLAGS="-lstdc++ -Wl,--build-id -fuse-ld=lld"
	./configure --shared --dest-cpu=arm64
	make -j"$LIBNODE_JOBS"
}

package() {
	mkdir -p "$LIBNODE_OUT"
	cp -a "$SRC_DIR/node/out/Release/libnode22.so" "$SRC_DIR/node/out/Release/libuv.so" "$LIBNODE_OUT/"
	cp "$LIBNODE_WORK/libnode.commit" "$LIBNODE_OUT/"
	(cd "$LIBNODE_OUT" && sha256sum libnode22.so libuv.so | tee SHA256SUMS)
}

case "${1:-all}" in
	fetch) fetch ;;
	build) build ;;
	package) package ;;
	all) fetch; build; package ;;
	*) echo "usage: $0 [fetch|build|package|all]"; exit 2 ;;
esac
