#!/bin/sh

# fail on error
set -xe

# set the number of job slots
JOB_SLOTS=${JOB_SLOTS:-24}

# upgrade to edge (keep v3.12 for downgrades)
echo http://dl-cdn.alpinelinux.org/alpine/v3.12/main >/etc/apk/repositories
echo http://dl-cdn.alpinelinux.org/alpine/v3.14/main >>/etc/apk/repositories
echo http://dl-cdn.alpinelinux.org/alpine/v3.16/main >>/etc/apk/repositories      # for LLVM 13
echo http://dl-cdn.alpinelinux.org/alpine/v3.16/community >>/etc/apk/repositories # for LLVM 13 ('lld')
echo http://dl-cdn.alpinelinux.org/alpine/edge/main >>/etc/apk/repositories
echo http://dl-cdn.alpinelinux.org/alpine/edge/community >>/etc/apk/repositories
echo http://dl-cdn.alpinelinux.org/alpine/edge/testing >>/etc/apk/repositories

# some dance to upgrade alpine-keys
apk --no-cache upgrade alpine-keys
apk --no-cache add -X https://dl-cdn.alpinelinux.org/alpine/v3.16/main -u alpine-keys

# update apk packages
apk --no-cache update
apk --no-cache upgrade

# add curl so we can curl the key
# also add ca-certificates so we don't lose it when removing curl
apk add --no-cache curl ca-certificates

# add fivem repositories
curl --http1.1 -sLo /etc/apk/keys/peachypies@protonmail.ch-5adb3818.rsa.pub https://runtime.fivem.net/client/alpine/peachypies@protonmail.ch-5adb3818.rsa.pub
curl -sLo /etc/apk/keys/hydrogen@fivem.net-614370b9.rsa.pub https://content.cfx.re/mirrors/build/linux/hydrogen@fivem.net-614370b9.rsa.pub

echo https://runtime.fivem.net/client/alpine/builds >>/etc/apk/repositories
echo https://runtime.fivem.net/client/alpine/main >>/etc/apk/repositories
echo https://runtime.fivem.net/client/alpine/testing >>/etc/apk/repositories
echo https://runtime.fivem.net/client/alpine/community >>/etc/apk/repositories
echo https://content.cfx.re/mirrors/build/linux/packages/cfx >>/etc/apk/repositories
apk --no-cache update

# uninstall old curl
apk del curl

# install runtime dependencies
apk add --no-cache curl=7.72.0-r99 libssl1.1 libcrypto1.1 libunwind libstdc++ zlib c-ares v8~=9.3 musl-dbg libatomic

# mono 5.16.1.0-r9991: the cfx apk repository only publishes x86_64 packages. On aarch64 the same
# versions are installed to the same paths from the tarball produced by arm64/build_mono_aarch64.sh
# (see arm64/README.md); MONO_AARCH64_TARBALL may point at a local file or an http(s) URL.
MONO_VERSION=5.16.1.0-r9991
MONO_APKS="mono-reference-assemblies=$MONO_VERSION mono-dev=$MONO_VERSION libmono=$MONO_VERSION mono-corlib=$MONO_VERSION mono=$MONO_VERSION mono-reference-assemblies-4.x=$MONO_VERSION mono-reference-assemblies-facades=$MONO_VERSION mono-csc=$MONO_VERSION mono-runtime=$MONO_VERSION"
MONO_AARCH64_TARBALL=${MONO_AARCH64_TARBALL:-/utils/arm64/mono-$MONO_VERSION-aarch64-musl.tar.xz}

case "$(apk --print-arch)" in
	aarch64) MONO_APKS="" ;;
esac

# install compile-time dependencies
apk add --no-cache --virtual .dev-deps lld~=13 curl-dev=7.72.0-r99 clang-dev~=13 clang~=13 build-base linux-headers openssl1.1-compat-dev openssl-dev~=1.1 python3 py3-pip py3-virtualenv lua5.3 lua5.3-dev $MONO_APKS c-ares-dev v8-dev~=9.3 clang-libs~=13 git dotnet6-sdk

if [ -z "$MONO_APKS" ]; then
	case "$MONO_AARCH64_TARBALL" in
		http://*|https://*)
			curl --http1.1 -fsSLo /tmp/mono-aarch64.tar.xz "$MONO_AARCH64_TARBALL"
			MONO_AARCH64_TARBALL=/tmp/mono-aarch64.tar.xz
			;;
	esac

	if [ ! -f "$MONO_AARCH64_TARBALL" ]; then
		echo "error: $MONO_AARCH64_TARBALL not found; build it with code/tools/ci/docker-builder/arm64/build_mono_aarch64.sh or set MONO_AARCH64_TARBALL" >&2
		exit 1
	fi

	if [ -f "$(dirname "$0")/arm64/mono-$MONO_VERSION-aarch64-musl.tar.xz.sha256" ]; then
		echo "$(cut -d' ' -f1 "$(dirname "$0")/arm64/mono-$MONO_VERSION-aarch64-musl.tar.xz.sha256")  $MONO_AARCH64_TARBALL" | sha256sum -c -
	fi

	# the runtime's dependencies (mono-dev depends on zlib-dev, the runtime on libgcc/zlib); the
	# tarball itself is not an apk, so these are not removed by `apk del .dev-deps` later
	apk add --no-cache zlib-dev libgcc xz
	tar -xJf "$MONO_AARCH64_TARBALL" -C /
fi

# install python deps
python3 -m venv /root/py-venv
. /root/py-venv/bin/activate
pip install ply six Jinja2 MarkupSafe

# predownload premake to exclude any issues with it in the future
curl --http1.1 -sLo /tmp/premake.zip https://github.com/premake/premake-core/releases/download/v5.0.0-beta1/premake-5.0.0-beta1-src.zip
cd /tmp
unzip -q premake.zip
rm premake.zip
cd premake-*

cd build/gmake*.unix/
make CFLAGS="-include unistd.h" -j${JOB_SLOTS}
cd ../../

mv bin/release/premake5 /usr/local/bin
cd ..
rm -rf premake-*

# install specific glibc version to enable running binaries compiled against it instead of alpine's muslc
# See: https://github.com/oven-sh/bun/blob/14c23cc429521bd935b2a0dafa36b0966685b0fe/dockerhub/alpine/Dockerfile
GLIBC_VERSION=2.34-r0
GLIBC_VERSION_AARCH64=2.26-r1

arch="$(apk --print-arch)" \
    && cd /tmp \
    && case "${arch##*-}" in \
      x86_64) curl "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk" \
        -fsSLO \
        --compressed \
        --retry 5 \
        || (echo "error: failed to download: glibc v${GLIBC_VERSION}" && exit 1) \
      && mv "glibc-${GLIBC_VERSION}.apk" glibc.apk \
      && curl "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-bin-${GLIBC_VERSION}.apk" \
        -fsSLO \
        --compressed \
        --retry 5 \
        || (echo "error: failed to download: glibc-bin v${GLIBC_VERSION}" && exit 1) \
      && mv "glibc-bin-${GLIBC_VERSION}.apk" glibc-bin.apk ;; \
      aarch64) curl "https://raw.githubusercontent.com/squishyu/alpine-pkg-glibc-aarch64-bin/master/glibc-${GLIBC_VERSION_AARCH64}.apk" \
        -fsSLO \
        --compressed \
        --retry 5 \
        || (echo "error: failed to download: glibc v${GLIBC_VERSION_AARCH64}" && exit 1) \
      && mv "glibc-${GLIBC_VERSION_AARCH64}.apk" glibc.apk \
      && curl "https://raw.githubusercontent.com/squishyu/alpine-pkg-glibc-aarch64-bin/master/glibc-bin-${GLIBC_VERSION_AARCH64}.apk" \
        -fsSLO \
        --compressed \
        --retry 5 \
        || (echo "error: failed to download: glibc-bin v${GLIBC_VERSION_AARCH64}" && exit 1) \
      && mv "glibc-bin-${GLIBC_VERSION_AARCH64}.apk" glibc-bin.apk ;; \
      *) echo "error: unsupported architecture '$arch'"; exit 1 ;; \
    esac

apk --no-cache --force-overwrite --allow-untrusted add \
      /tmp/glibc.apk \
      /tmp/glibc-bin.apk
