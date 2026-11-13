# CLAUDE.md - LibreELEC Hades

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
Without my explicit request, always use Context7 whenever I need library or API documentation, generate code, or setup or configuration steps.
Whenever I mention "检查log", "查log", "查下log", "看下日志", "看log", "还是卡", "依旧卡顿", "执行播放测试", or ask to diagnose playback issues, ALWAYS invoke the `kodi-diagnose` skill first.
Do not run build or compile commands unless I explicitly ask you to do so.
All code comments must be written in rigorous, professional English (no Chinese in comments).

---

## Repository Overview

- **Target**: LibreELEC Hades (Generic / x86_64, Native Dolby Vision & HDR10+)
- **Remotes**:
  - `origin`: `https://github.com/flhs0606/LibreELEC-Hades.git`
  - `upstream`: `https://github.com/hadesdevls/LibreELEC-Hades.git`
- **Key Directories**:
  - `projects/Generic/`: Target hardware configurations, system options, and Kodi patches
  - `packages/`: Package definitions and package-specific patches
  - `sources/`: Local cache for downloaded upstream source archives

---

## Build Commands

All build commands must be executed from the repository root:

```bash
# Build a single package (e.g. kodi)
PROJECT=Generic ARCH=x86_64 ./scripts/build_mt <package>:target

# Clean a package
PROJECT=Generic ARCH=x86_64 ./scripts/clean <package>

# Full image build (only when explicitly requested)
PROJECT=Generic ARCH=x86_64 make image
```

---

## Core Guidelines

1. **No Autonomous Builds**: Never execute build, make, compile, or packaging commands unless explicitly requested by the user.
2. **Explain First**: After modifying code or patches, stop and explain the technical rationale, root cause, and conclusions in text. Wait for explicit user confirmation before proceeding with further steps.
3. **No Direct Edits in `build/` Directory**: Do not modify files inside `build.LibreELEC-Generic.x86_64-13.0-devel/build/`. All code changes must be authored as formal Git patches under `projects/Generic/patches/` or `packages/*/patches/`.
4. **Protect Build Directory**: Never delete the entire `build.LibreELEC-Generic.x86_64-13.0-devel` directory. Clean only specific package stamps or build subdirectories when needed.
5. **English-Only Comments**: All code comments in source and patch files MUST be written in rigorous, professional English (no Chinese in comments).
6. **Code References**: Always use markdown link syntax with clickable paths: `[filename.cpp:42](path/filename.cpp#L42)`.
