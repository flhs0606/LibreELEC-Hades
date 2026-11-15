# LibreELEC Hades — Agent Guide

Operational rules for AI coding agents working in this repository.
Follow [STANDARDS.md](STANDARDS.md) for shell, `package.mk`, and device-side
script conventions. Device scripts run under busybox `sh`, not bash.

## Hard Rules
1. **Never run build, compile, or packaging commands unless the user explicitly
   asks.** Includes `make`, `make image`, `./scripts/build*`,
   `./scripts/create_addon`. Full image builds are strictly opt-in.
2. **Never build as root** (EUID check aborts); no spaces in workspace paths.
3. **No autonomous git operations**: never create/comment on issues or PRs,
   never push. Keep work local.
4. **Never edit files inside `build.<DISTRO>-<DEVICE>-<ARCH>-<VERSION>/`.** That
   tree is wiped on clean; all changes must be formal patches under
   `projects/<PROJECT>/patches/` or `packages/<pkg>/patches/`. Never delete the
   entire build directory; clean specific package stamps/subdirs only.
5. **Explain first**: after modifying code or patches, stop and explain the
   rationale, root cause, and conclusions in text. Wait for explicit
   confirmation before proceeding.
6. All code comments in rigorous, professional English. Reference code with
   markdown links: `[file.cpp:42](path/file.cpp#L42)`.
7. Always use Context7 for library/API documentation, code generation, and
   setup/configuration steps involving libraries.
8. When the user mentions "检查log", "查log", "查下log", "看log", "看下日志",
   "还是卡", "依旧卡顿", "执行播放测试", "对比仓库", "参考原版", or reports
   playback issues, invoke the `kodi-diagnose` skill first. The `kodi-diag`
   CLI lives inside WSL (`~/.local/bin/kodi-diag`); run it via
   `wsl -e bash -lc 'kodi-diag ...'`, not directly from PowerShell.

## Target Configuration
Defaults: `PROJECT=Generic ARCH=x86_64 DISTRO=LibreELEC` (this fork targets
Generic/x86_64 with native Dolby Vision & HDR10+). Example alternate target:
`PROJECT=RPi DEVICE=RPi5 ARCH=aarch64`.

## Execution Environment
This repository lives inside WSL (Ubuntu) at
`/home/mephis/Project/LibreELEC-Hades`, while the agent's shell is Windows
PowerShell. Wrap every repo command in WSL — never run bash scripts directly
from PowerShell:

```
wsl -d Ubuntu --cd /home/mephis/Project/LibreELEC-Hades -- bash -c "<command>"
```

File tools (read/write/edit) may operate on the UNC path
`\\wsl.localhost\Ubuntu\home\mephis\Project\LibreELEC-Hades` directly; only
shell execution needs the WSL wrapper.

## Commands (only when explicitly requested)
| Task | Command |
| :--- | :--- |
| Build one package | `PROJECT=... ARCH=... ./scripts/build_mt <pkg>[:target\|host]` |
| Clean a package | `PROJECT=... ARCH=... ./scripts/clean <pkg>` |
| Unpack & apply patches | `PROJECT=... ARCH=... ./scripts/unpack <pkg>` |
| Validate metadata | `./tools/pkgcheck <pkg>` |
| Build addon zip | `PROJECT=... ARCH=... ./scripts/create_addon <addon>` |

- `build_mt` writes per-package logs to `${BUILD}/.threads/logs/` — read the
  failing package's log there instead of re-running serially.
- Addon zips in `target/addons/` are never overwritten; pass
  `ADDON_OVERWRITE=yes` (or delete the zip) to rebuild. Never bump `PKG_REV`
  just to force a rebuild.

## Build-System Pitfalls
- **Stamps silently skip work**: if `.stamps/<pkg>/build_*` exists with a
  matching hash, compilation is skipped — "already built" does not mean your
  change took effect. `./scripts/clean <pkg>` forces a rebuild.
- **Target vs host sysroot**: `#include <foo.h> not found` in a target build
  means `PKG_DEPENDS_TARGET` is missing. Never fix target builds with host
  `-dev` packages.
- **Git-based packages** require full 40-character commit hashes in
  `PKG_VERSION`.
- **Patch workflow**: unpack, `git init` + commit pristine tree in
  `build.../<pkg>-<ver>/`, edit, then export via `git format-patch` into
  `packages/.../patches/####-subject.patch` (4-digit, no package-name prefix);
  verify clean application with `./scripts/clean` + `./scripts/unpack`.

## Reference
- Package recipes and hooks: `packages/<category>/<pkg>/package.mk`
- Version bumping (`tools/update-pkg`), patch refresh
  (`tools/refresh-patches`), contribution standards: [STANDARDS.md](STANDARDS.md)
