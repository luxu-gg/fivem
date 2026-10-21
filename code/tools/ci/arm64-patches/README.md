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

## Building without Mono (`--without-mono`)

There is no Mono runtime for aarch64 yet: the C# components (`citizen-scripting-mono`,
`citizen-scripting-mono-v2`) link the cfx-built mono 5.16 Alpine package, which is only
published for x86_64. The premake option `--without-mono` (server builds only, off by
default) lets the Linux FXServer build without it:

- `code/premake5.lua` skips the C# projects (CitiMono, CitiMonoRef, CitizenFX.Core,
  CitizenFX.Server) and sets `cfx_without_mono` for the component scripts.
- `code/components/config.lua` leaves out `citizen-scripting-mono` and
  `citizen-scripting-mono-v2`.
- `citizen-server-impl` lists `citizen:scripting:mono` under `optional_dependencies` in its
  `component.json`: when the component is absent, `code/tools/build/components.lua` skips
  the link/include instead of dropping the component and writes a `component.json` without
  that entry to `build/server/components/citizen-server-impl/`, which is what gets copied
  next to `libcitizen-server-impl.so` for the runtime loader. The component is compiled
  with `WITHOUT_MONO`, which removes the `MonoEnsureThreadAttached()` calls.
- `code/tools/ci/build_server_proot_alpine.sh` passes the option when `WITHOUT_MONO=1`
  (the default when the target is arm64; set `WITHOUT_MONO=0` to force a mono build),
  skips the `citizen/clr2` packaging steps, and prunes `components.json` of every
  component whose `lib<name>.so` was not built, so a build without mono, node or
  svadhesive starts instead of aborting in the component loader.

Without the option nothing changes: the generated makefiles for x86-64 are byte-identical.

What is lost with `--without-mono`:

- C# resources (`CitizenFX.Core` v1 and v2 runtimes, `clr2/`, the facade assemblies).
- JavaScript resources as well, until an aarch64 `libnode` exists: `citizen-scripting-node`
  is still generated, but it links the prebuilt x86_64 `libnode22.so`, so it is not built on
  arm64 and is pruned from `components.json` in the same step.
- Lua resources keep working.
