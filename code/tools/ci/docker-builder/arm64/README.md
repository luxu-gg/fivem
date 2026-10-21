# aarch64 (arm64) runtimes for the Linux FXServer build

The x86_64 Linux server build gets two scripting runtimes as prebuilt binaries that cfx only
publishes for x86_64:

| runtime | x86_64 source | consumer |
| --- | --- | --- |
| Mono 5.16.1.0 (`mono-dev=5.16.1.0-r9991` and friends) | cfx Alpine apk repository (`proot_prepare.sh`) | `citizen-scripting-mono`, `citizen-scripting-mono-v2`, `CitiMono`, `CitizenFX.Core` |
| libnode 22 (`libnode22.so`, `libuv.so`) | `https://content.cfx.re/mirrors/vendor/libnode/legacy22/bin/` (`vendor/libnode.lua`, `vendor/libuv.lua`) | `citizen-scripting-node` |

The scripts in this directory build the same versions for `aarch64-alpine-linux-musl`. Both run as
root inside an Alpine 3.16 aarch64 chroot/container (the same environment the x86_64 build uses:
musl, clang 13, lld), natively on an arm64 machine (a Raspberry Pi 5 or a `linux/arm64` container on
an Apple Silicon Mac).

## Mono 5.16.1.0 — `build_mono_aarch64.sh`

```sh
apk add autoconf automake libtool cmake gettext gettext-dev python3 perl linux-headers bash patch \
        bzip2 zlib-dev build-base curl xz
MONO_WORK=/build-mono sh build_mono_aarch64.sh        # fetch + build + package
```

Output: `$MONO_WORK/out/mono-5.16.1.0-r9991-aarch64-musl.tar.xz` (+ `.sha256`), a tarball rooted at
`/` that installs the same files to the same paths as the cfx x86_64 packages
`mono mono-runtime libmono mono-corlib mono-csc mono-dev mono-reference-assemblies
mono-reference-assemblies-4.x mono-reference-assemblies-facades`:

- `/usr/lib/libmonosgen-2.0.a` (what the server links statically), `libmonosgen-2.0.so.1`,
  `libmono-2.0.*`, `libMonoPosixHelper.so`, `libmono-btls-shared.so`, `libmono-native.so`,
  `libmono-profiler-*.so`, `/usr/lib/pkgconfig/mono*.pc`
- `/usr/include/mono-2.0/`
- `/usr/bin/mono`, `mono-sgen`, `csc`, `mcs`, the other `mono-dev` tool wrappers
- `/usr/lib/mono/4.5/` (`mscorlib.dll`, the 4.5 reference assemblies, `Facades/`, `csc.exe`,
  `mcs.exe`, ...), `/usr/lib/mono/4.*-api`, `/usr/lib/mono/gac`
- `/etc/mono/config`, `/etc/mono/4.5/machine.config`, ...

### How it is built

Source: `mono-5.16.1.0.tar.bz2` from `download.mono-project.com` plus the two patches carried by
the APKBUILD the cfx packages are built from ([spritsail/mono-apk](https://github.com/spritsail/mono-apk),
maintainer `mono-apk@spritsail.io` as recorded in the cfx apk `.PKGINFO`):

- `928eb4219f6527c23b5924d6e81fa5ba8660f0c4.patch` (jaykrell/mono): revert of mono/mono#6222
  (threadpool `parked_threads` semaphore) to speed up the threadpool
- `6462ec09a11119e36ea98925993f230b1c4eaa75.patch` (mono/mono): `AC_FUNC_STRERROR_R` for Mono.Posix
  (musl only has the XSI `strerror_r`)

Checksums of everything fetched are in `mono-sources.sha256`.

Plus one cfx-specific patch, `mono-cfx-debug.patch`: the cfx runtime exports two functions that
are not in upstream mono and that `citizen-scripting-mono` (`MonoComponentHost.cpp`) links
against, `mono_get_current_context` and `mono_stack_walk_bounded` (bounded managed stack walks
for the script-runtime stack traces). Their source is not published; the x86_64 apk's
`libmonosgen-2.0.a` contains them as `libmonoutils_la-cfx-debug.o` with full DWARF information,
and `mono/utils/cfx-debug.c` in the patch is a reconstruction from that object's disassembly and
debug info (same names, types, control flow and constants; register access through the
`MONO_CONTEXT_*` macros so it is architecture-neutral). The patch adds the file to
`mono/utils/Makefile.am`.

No aarch64/musl source patch is needed otherwise. Build-environment fixes only: the stale x86_64
objects of `System.Native` that the release tarball ships under `external/corefx` are deleted
(the `libmono-system-native` link otherwise fails with `Relocations in generic ELF (EM: 62)`),
and `mono/mini` gets a `python` shim for `genmdesc.py` (python 3 works, Alpine 3.16 has no
python 2).

Configure line (the APKBUILD's, plus the static/sgen options spelled out and `--disable-mcs-build`):

```sh
CFLAGS="-O2 -fno-strict-aliasing" ./autogen.sh \
    --build=aarch64-alpine-linux-musl --host=aarch64-alpine-linux-musl \
    --prefix=/usr --sysconfdir=/etc --mandir=/usr/share/man --infodir=/usr/share/info \
    --localstatedir=/var --disable-dependency-tracking --disable-system-aot --disable-rpath \
    --disable-boehm --with-sgen=yes --with-static-mono=yes --enable-parallel-mark --with-x=no \
    --with-libgc=none --with-mcs-docs=no --with-ikvm-native=no --disable-mcs-build
make -j$(nproc) && make DESTDIR=... install
```

`--disable-mcs-build`: the class libraries (`mscorlib.dll`, `System.*.dll`, the facades,
`csc.exe`/`mcs.exe`, ...) are architecture-independent IL, so the `package` stage takes them
verbatim from the pinned cfx x86_64 apks (identical bytes to what the x86_64 server ships; the
runtime's corlib version check passes because both come from the same 5.16.1.0 source) and
replaces every ELF object, header, static library and `.pc` file in that payload with the native
aarch64 build. Building the class libraries natively as well would take several hours on a Pi and
only reproduce the same IL.

### Using it

`proot_prepare.sh` installs this tarball instead of the cfx apks when `apk --print-arch` is
`aarch64`; it looks for `/utils/arm64/mono-5.16.1.0-r9991-aarch64-musl.tar.xz` or whatever
`MONO_AARCH64_TARBALL` points at (file or URL), verifying it against
`mono-5.16.1.0-r9991-aarch64-musl.tar.xz.sha256` from this directory when present. In a plain
chroot: `tar -xJf mono-5.16.1.0-r9991-aarch64-musl.tar.xz -C /` (plus `apk add zlib-dev libgcc`).

The rest of the C# tool chain is unchanged: `CitiMono` compiles `CitizenFX.Core.dll` with the
tarball's `csc` (Roslyn running on the aarch64 runtime), and its `clrref/genapi.sh` post-build step
needs a .NET 6 SDK (`dotnet6-sdk` from the Alpine 3.16 repositories exists for aarch64; Microsoft's
`dotnet-sdk-6.0.428-linux-musl-arm64.tar.gz` works too) and network access to NuGet.

## libnode 22.22.0 — `build_libnode_aarch64.sh`

cfx's Node build lives in [citizenfx/libnode](https://github.com/citizenfx/libnode): upstream
`nodejs/node` as a submodule (tag `v22.22.0` → `6add85e4c46b8be383c8b637102d6b6fd206adce`, Node.js
v22.22.0 'Jod') plus the patches in `patches/` (shared libuv, output renamed to `libnode22.so`,
RTTI, embedded ICU, handle-scope/permission changes, ...). Its `.github/workflows/build.yml` builds
the Linux x86_64 artifact on Alpine 3.16 with clang 13 and lld:

```sh
CC=clang CXX=clang++ CXXFLAGS="-g -mssse3 -std=c++20" LDFLAGS="-m64 -lstdc++ -Wl,--build-id -fuse-ld=lld" \
    ./configure --shared && make -j4
```

`build_libnode_aarch64.sh` does the same for arm64 (`--dest-cpu=arm64`, without the x86-only
`-mssse3`/`-m64`):

```sh
apk add git bash curl libgcc linux-headers make python3 xz libatomic clang clang-dev clang-libs \
        llvm13-dev lld libc-dev musl-dev gcc g++ perl
LIBNODE_WORK=/build-libnode sh build_libnode_aarch64.sh   # fetch (clone + patches) + build + package
```

Output: `$LIBNODE_WORK/out/libnode22.so`, `libuv.so`, `SHA256SUMS` and `libnode.commit` (the
citizenfx/libnode and nodejs/node commits that were built). Expect several hours on a Raspberry Pi 5
and a large link (`-g` is kept so the server packaging step can split the debug info into `.dbg`
files like it does on x86_64; 8 GB of RAM plus swap is enough).

### Using it

On a non-x86 Linux target `vendor/libnode.lua` and `vendor/libuv.lua` read `libnode22.so` and
`libuv.so` from `CFX_LIBNODE_DIR` (default `vendor/libnode/bin/linux-arm64/` at the repository
root), or download them from `CFX_LIBNODE_URL/<file>` when that is set. Without a cfx-built
`libuv.so` the build falls back to the distro libuv as before (which is only enough for a build
without `citizen-scripting-node`).

## Artifacts

SHA-256 sums of the artifacts built from these scripts are recorded in `SHA256SUMS` next to this
file.
