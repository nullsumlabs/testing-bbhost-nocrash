# FIXES-LOG

Stability and crash fixes adapted from **BloodBorneButPc** (a Windows fork of the
shadPS4/bbport engine) into **bbhost** (this native translation layer).

The two projects do not share source, so each fix is re-expressed in bbhost's own
architecture under the same switch name that gates it in BloodBorneButPc. Where
bbhost already solved the same problem another way, that is noted rather than
duplicated. Long-session VRAM accumulation and the launch-time heap overflow are
the crashes these target.

## GPU hang guard - textures freed while still in use

- **Source:** `BB_GC_RECENT_FRAMES` (default 48), `BB_IMAGE_FREE_DELAY_FRAMES`
  (default 32) in BloodBorneButPc's texture cache.
- **Files:** `src/host/textures.cpp`.
- **Change:** each surface records the video flip of its last use
  (`Surface::used_flip`, stamped wherever `used_ms` is). The cold-texture sweep
  (`evict_cold_surfaces_locked`) and the reused-memory retire
  (`textures_retire_reused_locked`) now skip any surface used or deleted within
  `max(BB_GC_RECENT_FRAMES, BB_IMAGE_FREE_DELAY_FRAMES)` flips. Frames are the
  GPU's own timeline, so a long frame (a hitch, a load) can no longer age a
  texture out from under a submission still reading it - the
  stalled-then-device-lost class of crash.
- **Rationale:** bbhost already defers a deleted image's Vulkan objects to
  submission retirement (`defer_destroy_image`), so the "outlive unregistration"
  half is already covered; the frame floor adds the part it lacked - a texture
  the just-recorded frame used is never a candidate for freeing.

## VRAM cleanup - accumulation over a long session

- **Source:** `BB_VRAM_PRESSURE_PERCENT` (default 85), `BB_VRAM_IDLE_SECONDS`
  (default 30; 10 s above 90% of the driver's budget) in BloodBorneButPc.
- **Files:** `src/host/textures.cpp`, `src/host/gpu.cpp`,
  `src/host/gpu_internal.h`.
- **Change:** `evict_cold_surfaces_locked` now measures pressure as a share of
  the driver's budget (new accessor `vram_budget_bytes()`) and:
  - triggers once usage reaches `BB_VRAM_PRESSURE_PERCENT` of that budget, in
    addition to bbhost's existing reserve-and-full-heap trigger;
  - frees only textures idle for `BB_VRAM_IDLE_SECONDS`, dropping that to 10 s
    once the budget is 90% used.
  - surfaces a shader or copy wrote are still never evicted (bbhost holds state
    the guest memory underneath does not), matching BloodBorneButPc keeping
    GPU-written blocks resident.
- **Rationale:** the original default idle of 20 s (via `BBHOST_VRAM_EVICT_S`,
  still honored, `=0` off) is kept as a fallback; the percentage line lets the
  sweep start before the reserve is hit and sweep harder as the card fills.

## Direct memory pool - launch crash on a large scene

- **Source:** `BB_DMEM_MB` (BloodBorneButPc gives a scene above 1080p the
  9152 MiB pool instead of 5056 MiB).
- **Files:** `src/hle/kernel.cpp`.
- **Change:** `BB_DMEM_MB` names the direct memory the game is told it has (the
  stock 6 GiB otherwise), clamped to the window reserved for it (7.75 GiB).
- **Rationale:** bbhost already grows the game's GFX heap and its direct memory
  for a scene above 1080p (`grow_gfx_heap` / `hle_kernel_set_dmem_size`,
  `engine/live_resolution.cpp`), so the >1080p policy is present; the switch
  exposes the pool size itself, and its 7.75 GiB window is the ceiling that
  BloodBorneButPc's 9152 MiB meets only as far as the window allows.

## Already present in bbhost (not re-ported)

- Crash reports for host faults on a game thread (Linux `SIGSEGV` handler,
  `main.cpp`; `host/win_crash.cpp` on Windows).
- Write faults at the end of a GPU mapping handled, unclaimed faults on guest
  pages handed access back (`core/write_watch.cpp`).
- Unknown texture formats read as `VK_FORMAT_UNDEFINED` and are skipped instead
  of aborting; a lost/out-of-date swapchain is recreated
  (`host/window.cpp`).
- Audio output follows the device's real rate (`host/audio.cpp`).
- Patch write sites are checked against the expected bytes before any is
  written (`engine/patch_manifest.cpp`).
- VM/launcher-only items (Windows error 1450 memory check, 10 GB pool, region
  patch prompt) do not apply to bbhost's Linux path.
