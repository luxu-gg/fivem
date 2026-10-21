#!/bin/sh

# fail on error
set -xe

# set the number of job slots
JOB_SLOTS=${JOB_SLOTS:-24}

. /root/py-venv/bin/activate

# map the target architecture (x86_64 or aarch64) to a premake --arch value
ARCH=${ARCH:-$(uname -m)}

case "$ARCH" in
	x86_64) PREMAKE_ARCH=x64 ;;
	aarch64|arm64) PREMAKE_ARCH=arm64 ;;
	*) echo "unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

# a few vendored submodules have no aarch64 support upstream yet; apply the small
# patches from code/tools/ci/arm64-patches/ before anything uses them (idempotent:
# a patch is skipped when it is already applied). File names map to the submodule
# path with '__' standing in for '/': ext__native-doc-tooling.patch -> ext/native-doc-tooling
if [ "$PREMAKE_ARCH" = "arm64" ]; then
	for patch in /src/code/tools/ci/arm64-patches/*.patch; do
		target=/src/$(basename "$patch" .patch | sed 's#__#/#g')

		if git -C "$target" apply --check --reverse "$patch" >/dev/null 2>&1; then
			echo "arm64 patch already applied: $patch"
		else
			echo "applying arm64 patch: $patch"
			git -C "$target" apply "$patch"
		fi
	done
fi

# build natives
if [ "$SKIP_NATIVES" == "" ]; then
	cd /src/ext/natives
	gcc -O2 -shared -fpic -o cfx.so -I/usr/include/lua5.3/ lua_cfx.c

	mkdir -p inp out
	curl --http1.1 -sLo inp/natives_global.lua https://static.cfx.re/natives/natives.lua

	cd /src/ext/native-doc-gen
	sh build.sh

	cd /src/ext/natives

	mkdir -p /opt/cfx-server/citizen/scripting/lua/
	mkdir -p /opt/cfx-server/citizen/scripting/v8/

	lua5.3 codegen.lua inp/natives_global.lua native_lua server >/src/code/components/citizen-scripting-lua/include/NativesServer.h
	lua5.3 codegen.lua inp/natives_global.lua lua server >/opt/cfx-server/citizen/scripting/lua/natives_server.lua
	lua5.3 codegen.lua inp/natives_global.lua js server >/opt/cfx-server/citizen/scripting/v8/natives_server.js
	lua5.3 codegen.lua inp/natives_global.lua dts server >/opt/cfx-server/citizen/scripting/v8/natives_server.d.ts

	cat >/src/code/client/clrcore/NativesServer.cs <<EOF
#if IS_FXSERVER
using ContextType = CitizenFX.Core.fxScriptContext;

namespace CitizenFX.Core.Native
{
EOF

	lua5.3 codegen.lua inp/natives_global.lua enum server >>/src/code/client/clrcore/NativesServer.cs
	lua5.3 codegen.lua inp/natives_global.lua cs server >>/src/code/client/clrcore/NativesServer.cs

	cat >>/src/code/client/clrcore/NativesServer.cs <<EOF
}
#endif
EOF

	lua5.3 codegen.lua inp/natives_global.lua cs_v2 server >/src/code/client/clrcore-v2/Native/NativesServer.cs

	lua5.3 codegen.lua inp/natives_global.lua rpc server >/opt/cfx-server/citizen/scripting/rpc_natives.json

	lua5.3 codegen.lua inp/natives_global.lua pointer_args server >/src/code/components/citizen-scripting-core/src/NativeTypesServer.h
fi

## SETUP-CUTOFF

# WITHOUT_MONO=1 builds the server without the Mono runtime (no C# resource support): the cfx mono
# package only exists for x86_64, so it defaults to on for arm64. Set WITHOUT_MONO=0 to force a
# mono build once an aarch64 package is available.
if [ -z "$WITHOUT_MONO" ]; then
	if [ "$PREMAKE_ARCH" = "arm64" ]; then
		WITHOUT_MONO=1
	else
		WITHOUT_MONO=0
	fi
fi

PREMAKE_MONO_ARGS=""

if [ "$WITHOUT_MONO" = "1" ]; then
	PREMAKE_MONO_ARGS="--without-mono"
fi

# build CitizenFX
cd /src/code

premake5 gmake2 --game=server --cc=clang --dotnet=msnet --arch=$PREMAKE_ARCH $PREMAKE_MONO_ARGS
cd build/server/linux

export CFLAGS="-fno-plt"
export CXXFLAGS="-D_LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR -Wno-deprecated-declarations -Wno-invalid-offsetof -fno-plt"
export LDFLAGS="-Wl,--build-id -fuse-ld=lld"

if [ ! -z "$CI_BRANCH" ] && [ ! -z "$CI_BUILD_NUMBER" ]; then
	echo '#pragma once' >/src/code/shared/cfx_version.h

	if [[ "$CI_BRANCH" == feature/* ]]; then
		dateVersion=$(date +%Y%m%d)
		gitDescription="$CI_BRANCH SERVER v1.0.0.$dateVersion linux"
	else
		gitDescription="$CI_BRANCH $CI_BUILD_NUMBER linux"
	fi

	echo '#define GIT_DESCRIPTION "'$gitDescription'"' >>/src/code/shared/cfx_version.h
	echo '#define GIT_TAG "'$CI_BUILD_NUMBER'"' >>/src/code/shared/cfx_version.h
	echo '#define BUILD_ID "cfx-'$CI_PIPELINE_ID'"' >>/src/code/shared/cfx_version.h
fi

make clean
make clean config=release
make -j${JOB_SLOTS} config=release

cd ../../../

# build an output tree
mkdir -p /opt/cfx-server

cp -a ../data/shared/* /opt/cfx-server
cp -a ../data/server/* /opt/cfx-server
cp -a bin/server/linux/release/FXServer /opt/cfx-server
cp -a bin/server/linux/release/*.so /opt/cfx-server
cp -a bin/server/linux/release/*.json /opt/cfx-server
cp tools/ci/run.sh /opt/cfx-server
chmod +x /opt/cfx-server/run.sh

# only the C# projects put anything in here, so it may not exist without mono
if [ -d bin/server/linux/release/citizen/ ]; then
	cp -a bin/server/linux/release/citizen/ /opt/cfx-server
fi

if [ "$WITHOUT_MONO" != "1" ]; then

mkdir -p /opt/cfx-server/citizen/clr2/cfg/mono/4.5/
mkdir -p /opt/cfx-server/citizen/clr2/lib/mono/4.5/

cp -a /etc/mono/4.5/machine.config /opt/cfx-server/citizen/clr2/cfg/mono/4.5/machine.config

cp -a ../data/client/citizen/clr2/lib/mono/4.5/MsgPack.dll /opt/cfx-server/citizen/clr2/lib/mono/4.5/

cp -a /usr/lib/mono/4.5/Facades/ /opt/cfx-server/citizen/clr2/lib/mono/4.5/Facades/

cp -a /usr/lib/libMonoPosixHelper.so /tmp/libMonoPosixHelper.so
cp -a /usr/lib/libmono-btls-shared.so /tmp/libmono-btls-shared.so

for dll in I18N.CJK.dll I18N.MidEast.dll I18N.Other.dll I18N.Rare.dll I18N.West.dll I18N.dll Microsoft.CSharp.dll Mono.CSharp.dll Mono.Posix.dll Mono.Security.dll System.Collections.Immutable.dll System.ComponentModel.DataAnnotations.dll System.Configuration.dll System.Core.dll System.Data.dll System.Drawing.dll System.EnterpriseServices.dll System.IO.Compression.FileSystem.dll System.IO.Compression.dll System.Management.dll System.Net.Http.WebRequest.dll System.Net.Http.dll System.Net.dll System.Numerics.Vectors.dll System.Numerics.dll System.Reflection.Metadata.dll System.Runtime.InteropServices.RuntimeInformation.dll System.Runtime.Serialization.dll System.ServiceModel.Internals.dll System.ServiceModel.dll System.Transactions.dll System.Web.dll System.Xml.Linq.dll System.Xml.dll System.dll mscorlib.dll; do
	cp /usr/lib/mono/4.5/$dll /opt/cfx-server/citizen/clr2/lib/mono/4.5/ || true
done

fi # WITHOUT_MONO

# drop components that were not built from components.json (svadhesive without the private repo,
# mono/node on architectures without a runtime): the loader aborts on startup when an entry has
# no lib<name>.so next to it
prune_components_json() {
	local list="$1"
	local dir=$(dirname "$list")
	local kept=""
	local name lib first

	for name in $(grep -o '"[^"]*"' "$list" | tr -d '"'); do
		lib="lib$(echo "$name" | tr ':' '-').so"

		if [ -f "$dir/$lib" ]; then
			kept="$kept $name"
		else
			echo "components.json: dropping $name ($lib was not built)"
		fi
	done

	first=1

	{
		echo '['

		for name in $kept; do
			if [ $first = 1 ]; then
				first=0
			else
				printf ',\n'
			fi

			printf '  "%s"' "$name"
		done

		printf '\n]\n'
	} >"$list.tmp"

	mv "$list.tmp" "$list"
}

prune_components_json /opt/cfx-server/components.json

## BUILD-CUTOFF

# copy debug info
for i in /opt/cfx-server/*.so /opt/cfx-server/FXServer; do
	objcopy --only-keep-debug --compress-debug-sections=zlib $i $i.dbg
	objcopy --strip-unneeded $i
	objcopy --add-gnu-debuglink=$i.dbg $i
done

cd /opt/cfx-server

# clean up
rm -rf /tmp/boost

apk del .dev-deps

# contains Yarn cache and premake5
rm -rf /usr/local
rm -rf /usr/lib/python*

if [ "$WITHOUT_MONO" != "1" ]; then
	mv /tmp/libMonoPosixHelper.so /usr/lib/libMonoPosixHelper.so
	mv /tmp/libmono-btls-shared.so /usr/lib/libmono-btls-shared.so
fi
