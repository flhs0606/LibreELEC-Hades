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

## Repository Structure & Remotes

| Remote / Path | Target Repository | Branch | Purpose |
|---|---|---|---|
| `origin` | `https://github.com/flhs0606/LibreELEC-Hades.git` | `main` | User active fork (`Hades-F1.0-RC8`) |
| `upstream` | `https://github.com/hadesdevls/LibreELEC-Hades.git` | `main` | Upstream LibreELEC Hades baseline (1.0 RC8, Nov 2026) |
| `sources/` | Symlinked to `../libreelec-x86-DV/sources` | - | Shared upstream tarball download cache |
| `packages/mediacenter/kodi/` | Build recipe | - | Kodi package definition (`package.mk`) |
| `packages/devel/onnxruntime/` | Build recipe & patches | - | ONNX Runtime for offline PGS subtitle OCR |
| `packages/devel/pgs-ocr-model/` | Model & checksum recipe | - | Pinned PP-OCRv5 mobile INT8 model (`ppocrv5-mobile-rec-int8.onnx`) |
| `projects/Generic/` | Project options & patches | - | x86_64 hardware options, `advancedsettings.xml`, and target patches |

---

## Build Architecture & Sharing Guidelines

- **Shared `sources/` cache**: `sources/` is symlinked to `../libreelec-x86-DV/sources` (3.0+ GB) to share downloaded tarballs.
- **Independent `build` & `toolchain`**: Hades is based on a newer upstream LibreELEC commit (LLVM 23.1.5, CMake 4.4.5, Linux 7.3, glibc 2.44 + 30 patches). **NEVER symlink `toolchain/` or `.stamps/` to `libreelec-x86-DV`**, as rebuilds will overwrite and corrupt `libreelec-x86-DV`'s active toolchain.
- **Build directory protection**: STRICTLY PROHIBITED from deleting the entire `build.LibreELEC-Generic.x86_64-13.0-devel` directory (the base toolchain and dependencies take hours to rebuild). Only remove specific package stamps/build dirs when a clean rebuild is required.
- **Guardrails**: Never run full image builds (`make`, `make image`, `make release`) autonomously. Only build specific packages when explicitly requested. Never commit `build.log` or transient build artifacts (exceeds GitHub's 100 MB file limit).

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
- **Output binary**: `build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-*/.x86_64-libreelec-linux-gnu/kodi.bin`

### 2. Fast Incremental Build (Ninja inside extracted build tree)
Only for recompilation after verifying build state or iterating on temporary patch tests:
```bash
cd build.LibreELEC-Generic.x86_64-13.0-devel/build/kodi-*/.x86_64-libreelec-linux-gnu
ninja -j$(nproc) kodi.bin
```

### 3. Clean Package & Stamps
```bash
PROJECT=Generic ARCH=x86_64 ./scripts/clean kodi
```
- Build stamps live at `build.LibreELEC-Generic.x86_64-13.0-devel/.stamps/<package-name>/`. If `./scripts/clean kodi` is not used, remove only `.stamps/kodi`, `build/kodi-[0-9a-f]*`, and `install_pkg/kodi-[0-9a-f]*`.

### 4. Full Image Release Build (Explicitly Authorized Only)
```bash
PROJECT=Generic ARCH=x86_64 make image
# Output: target/LibreELEC-Generic.x86_64-13.0-devel-*.img.gz (.tar / .ova)
```

---

## Custom Patches & Feature Map (F1.0 RC8)

All custom modifications on top of upstream Hades 1.0 RC8 live as formal patches and package definitions:

| Area | Path | Purpose |
|---|---|---|
| HDR Vivid → DV P8.1 | `projects/Generic/patches/kodi/x86/kodi-9970-videoplayer-hdr-vivid-sent-as-dolby-vision-as-an-option.patch` | Real-time HDR Vivid to Dolby Vision Profile 8.1 conversion, UI choices, `hades.dv.origin`, and fallback guards |
| Dolby STB 2.6 Engine | `projects/Generic/patches/kodi/x86/kodi-9998-dvbridge-integrate-dolby-stb26-native-engine.patch` | Integrate Dolby Vision STB 2.6 native engine into `dvbridge` and consolidate active area metadata |
| Cloud Blu-ray Direct Play | `projects/Generic/patches/kodi/x86/kodi-9999-zzz-cloud-bluray-direct-play.patch` | Direct-play main title selection for cloud/HTTP Blu-ray ISOs (paired with `openjdk`, `hades-bdj`, `libbluray-bdj`) |
| Chinese Subtitles Priority | `projects/Generic/patches/kodi/x86/kodi-9999-zzz1-subtitles-chinese-preferences-and-priority.patch` | Chinese subtitle preferences and track priority selection |
| PGS OCR & Seamless Switch | `projects/Generic/patches/kodi/x86/kodi-9999-zzz2-subtitles-identify-chinese-pgs-and-switch-without-seeking.patch` | Offline PP-OCRv5 Chinese PGS identification (`onnxruntime` + `pgs-ocr-model`) and seamless stream switching without seeking |
| Reshaping Pivot Fix | `packages/addons/addon-depends/multimedia-tools-depends/libplacebo/patches/libplacebo-9930-dovi-ccm-composer.patch` | Allow non-decreasing reshaping pivots (`curve->pivots[p] < curve->pivots[p - 1]`) per ETSI GS CCM 001 |
| Generic Defaults | `projects/Generic/kodi/advancedsettings.xml` | Custom Kodi `advancedsettings.xml` defaults for Generic x86_64 |

---

## Core Development Guidelines

1. **No Autonomous Builds**: Never execute build, make, compile, or packaging commands unless explicitly requested by the user.
2. **Explain First**: After modifying code or patches, stop and explain the technical rationale, root cause, and conclusions in text. Wait for explicit user confirmation before proceeding with further steps.
3. **English-Only Comments**: All code comments in source and patch files MUST be written in rigorous, professional English (no Chinese in comments).
4. **Code References**: Always use markdown link syntax with clickable paths: `[filename.cpp:42](path/filename.cpp#L42)`.
5. **No Direct Edits in `build/` Directory (Iron Rule)**: STRICTLY PROHIBITED from modifying source files directly inside `build.LibreELEC-Generic.x86_64-13.0-devel/build/`. That directory is an ephemeral extraction artifact not tracked by Git. All modifications must be authored as formal patch files under `projects/Generic/patches/` or `packages/*/patches/` so every change is tracked and reproducible via Git.
