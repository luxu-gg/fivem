# arm64 patches for vendored submodules

Small source patches needed to compile the Linux FXServer for aarch64. Each file is
named after the submodule it applies to, with `/` replaced by `-` (`vendor-lua.patch`
applies to `vendor/lua`), and is applied by `code/tools/ci/build_server_proot_alpine.sh`
when the target architecture is arm64. They are no-ops for x86-64 and should be
upstreamed to the matching `citizenfx/*` forks, after which they can be deleted.

| Patch | Submodule | Why |
|---|---|---|
| `vendor-lua.patch` | `vendor/lua` (`loslib.c`) | `__has_include(<x86intrin.h>)` is true on every clang target, so the x86 header was included on aarch64; require an x86 target too. |
| `vendor-lmprof.patch` | `vendor/lmprof` (`src/lmprof.c`) | Same `x86intrin.h` guard. |
| `vendor-xenium.patch` | `vendor/xenium` (`xenium/utils.hpp`) | `getticks()` only had rdtsc/sparc implementations; add an aarch64 one reading `cntvct_el0`. |
