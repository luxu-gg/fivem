# arm64 patches for vendored submodules

Small source patches needed to build the Linux FXServer for aarch64. Each file is
named after the submodule it applies to, with `__` standing in for `/`
(`vendor__lua.patch` applies to `vendor/lua`, `ext__native-doc-tooling.patch` to
`ext/native-doc-tooling`). `code/tools/ci/build_server_proot_alpine.sh` applies them
before the natives step when the target architecture is arm64; they are no-ops for
x86-64 and should be upstreamed to the matching `citizenfx/*` forks, after which they
can be deleted.

| Patch | Submodule | Why |
|---|---|---|
| `vendor__lua.patch` | `vendor/lua` (`loslib.c`) | `__has_include(<x86intrin.h>)` is true on every clang target, so the x86 header was included on aarch64; require an x86 target too. |
| `vendor__lmprof.patch` | `vendor/lmprof` (`src/lmprof.c`) | Same `x86intrin.h` guard. |
| `vendor__xenium.patch` | `vendor/xenium` (`xenium/utils.hpp`, `xenium/backoff.hpp`) | `getticks()` only had rdtsc/SPARC implementations and `#error`ed otherwise: add one reading `cntvct_el0`. The spin backoff only knew `_mm_pause()`: add `yield`. |
| `ext__native-doc-tooling.patch` | `ext/native-doc-tooling` (`package.json`) | The pinned `ffi-napi` 2.x bundles a libffi that does not link on aarch64; pin `ffi-napi` 4.0.3 / `ref-napi` 3.0.3 through yarn resolutions. Used together with the system node (see `ext/native-doc-gen/build.sh`). |
