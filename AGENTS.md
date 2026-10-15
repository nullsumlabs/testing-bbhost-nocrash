# Notes for agents

What the `awakechan-fixes` branch adds on top of `master`, and how to check it.
`FIXES-LOG.md` is the detail for the first part, `docs/building.md` for the
second.

## Stability fixes ported from BloodBorneButPc

- `src/host/textures.cpp` - the GPU hang guard (`BB_GC_RECENT_FRAMES` 48,
  `BB_IMAGE_FREE_DELAY_FRAMES` 32, which share one floor) and the pressure-based
  cold sweep (`BB_VRAM_PRESSURE_PERCENT` 85, `BB_VRAM_IDLE_SECONDS` 30; `0` off).
- `src/hle/kernel.cpp` - `BB_DMEM_MB` names the direct memory pool, clamped to
  the 6 GiB-7.75 GiB window `hle_kernel_set_dmem_size()` uses.
- The switches default on, and the whole sweep still needs a VRAM reserve
  (`vram_reserve_bytes()`, `textures.cpp`), so on an integrated GPU only the
  hang guard is active. `FIXES-LOG.md` has the defaults and the `0` semantics.

## AppImage packaging

- `tools/package_appimage.sh [INPUT] [OUTDIR]` packs `tools/package_linux.sh`'s
  tarball, or a bbhost binary (which it packs into that tarball first), into an
  AppImage. `BB_APPIMAGE_BUILD=1` builds before packing - `CI_PORTABLE=1
  tools/ci_build.sh`, so the binary inside runs on other machines - and
  `BB_MARCH` says what to compile for. Output defaults to `build/appimage`.
- `tools/package_appimage_steamdeck.sh` is the same with the Deck's settings
  (`tools/steamdeck/bbhost-steamdeck.toml`, `STEAMDECK.md`) and `-march=znver2`,
  which is what both Deck revisions are (Van Gogh and Sephiroth are Zen 2).
- A mounted AppImage is read-only, so AppRun keeps the session's log and the F12
  frame dumps under `~/.local/share/bbhost` instead of beside the binary.
  Running one needs FUSE: `--appimage-extract-and-run` is the way out where
  libfuse.so.2 is missing, which the Deck and Steam's runtime are known for.
- Neither script has been run against real `appimagetool` (mksquashfs), and
  `BB_APPIMAGE_BUILD=1` has not been run at all: both need Linux. The AppDir
  contents, the icon and AppRun's behaviour were checked by hand instead.

## Checking a change

- `cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo`, `cmake --build build -j`,
  then `cd build && ctest --output-on-failure`. Tests that read game files skip
  unless `BBHOST_APP0` names a game folder.
- `tools/ci_build.sh` is the from-scratch Linux build CI runs, and needs no game
  files; `tools/win_syntax_check.sh <file>` checks one file for the Windows
  target without a full cross build.
- bbhost builds only on x86-64 Linux (and Windows from Linux), so a Darwin or
  ARM host cannot compile it: a change here is unverified until it has been
  built on Linux.

## Known, left alone

- `tools/linux_portable_build.sh:136` builds `bb_plugin_hello`, `randomizer`,
  `boss_rush` and `mutators`, but not `bb_plugin_debug_menu`, while
  `tools/package_plugins.sh` fails unless all four official plugins are present.
  That packaging route fails its own check; `tools/ci_build.sh`, which builds
  every target, is unaffected.
