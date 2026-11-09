# CLAUDE.md - LibreELEC Hades

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
Without my explicit request, always use Context7 whenever I need library or API documentation, generate code, or setup or configuration steps.
Whenever I mention "检查log", "查log", "查下log", "看下日志", "看log", "还是卡", "依旧卡顿", "执行播放测试", or ask to diagnose playback issues, ALWAYS invoke the `kodi-diagnose` skill first.
Do not run build or compile commands unless I explicitly ask you to do so.
All code comments must be written in rigorous, professional English (no Chinese in comments).

> **Workspace Isolation Notice**:
> This workspace is dedicated to **LibreELEC Hades (Generic / x86_64, Linux 7.3 / LibreELEC 13, Native Dolby Vision & HDR10+)**.
> For LibreELEC x86-DV (CB1 engine / Linux 7.2), refer to `../libreelec-x86-DV/CLAUDE.md`.
> For CoreELEC 21 (Amlogic-ng / arm, Linux 4.9), refer to `../CoreELEC/CLAUDE.md`.
> For CoreELEC 22 (Amlogic-no / aarch64, Linux 5.15), refer to `../CoreELEC-22/CLAUDE.md`.

---

## Repository Structure & Upstream

| Remote / Path | Target Repository | Branch | Purpose |
|---|---|---|---|
| `origin` | `https://github.com/hadesdevls/LibreELEC-Hades.git` | `main` | LibreELEC Hades baseline (1.0 RC8, Nov 2026) |
| `sources/` | Symlinked to `../libreelec-x86-DV/sources` | - | Shared upstream tarball download cache |
| `packages/mediacenter/kodi/` | Build recipe | - | Kodi package definition (`package.mk`) |
| `projects/Generic/` | Project options & patches | - | x86_64 hardware options & defconfigs |

---

## Build Architecture & Sharing Guidelines

- **Shared `sources/` cache**: `sources/` is symlinked to `../libreelec-x86-DV/sources` (3.0+ GB) to share downloaded tarballs.
- **Independent `build` & `toolchain`**: Hades is based on a newer upstream LibreELEC commit (LLVM 23.1.5, CMake 4.4.5, Linux 7.3, glibc 2.44 + 30 patches). **NEVER symlink `toolchain/` or `.stamps/` to `libreelec-x86-DV`**, as rebuilds will overwrite and corrupt `libreelec-x86-DV`'s active toolchain.
- **Guardrails**: Never run full image builds (`make`, `make image`, `make release`) autonomously. Only build specific packages when requested.

---

## Build Commands

All build commands must be executed from `/home/mephis/Project/LibreELEC-Hades`.

### 1. Single Package Rebuild (e.g. Kodi)
```bash
# Parallel build (recommended)
PROJECT=Generic ARCH=x86_64 ./scripts/build_mt kodi:target

# Sequential build (debug only)
PROJECT=Generic ARCH=x86_64 ./scripts/build kodi:target
```

### 2. Clean Package & Stamps
```bash
PROJECT=Generic ARCH=x86_64 ./scripts/clean kodi
```

### 3. Full Image Release Build (Explicitly Authorized Only)
```bash
PROJECT=Generic ARCH=x86_64 make image
# Output: target/LibreELEC-Generic.x86_64-13.0-devel-*.img.gz
```
