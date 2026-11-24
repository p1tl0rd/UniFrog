# UniFrog Session Handoff

## Branch & Repository State
- **Branch:** `dev` (ahead of `origin/dev` at `f039084` by local commits).
- **Recent commits before this handoff:**
  - `ebbeb11` — Fix `gambatte-prosty` FakeRTC load hang (time-domain underflow / truncated `gambatte_rtc.dat`), external core `fopen()`/`fileno()`/`_fwrite_r`/`_fflush_r` support in `foundation/src/modules/unifrog_core_module_support.c`, and loader teardown/watchdog fixes.
  - `0b3b32f` — Add reproducible Ubuntu 24.04 Dockerfile (`unifrog-dev:latest`).
  - `d329518` — Fix libretro audio upsampler loop in `components/libretro/src/unifrog_libretro_runtime.c` and RACE native 44.1 kHz audio + in-memory ROM loading.
  - `aa59b17` — Speed up `Collection`/`History` browser opening (`frontend_browser.c`), tighten `SELECT+L/R` backlight chords, and mask GB300 bit-15 jitter.

## Fixes Completed in This Session
1. **Sega `.md` ROMs misclassified as Markdown reader (`reader`):**
   - `components/frontend/assets/defaults/associations.ini`: moved `extension.md` out of the reader-only section to the Sega/PicoDrive section (`extension.md.handlers=picodrive,reader`, `extension.md.default=picodrive`).
   - `components/frontend/src/app/frontend_content.c`: updated `default_handler_for_path()` with `core_accepts_path_in_system_dir()` so a ROM system folder mapping (`rom_system=sega:picodrive`, `/ROMS/sega/*.md`, etc.) takes precedence over a builtin `"reader"` association when that core supports the file's extension. Kept `".md"` in `foundation/src/content/unifrog_reader_content.c` so Markdown files remain openable via Open With -> `reader`.
   - `tests/host/associations_test.c`: added regression coverage for `.md` -> `picodrive,reader`.
2. **Menu Up/Down occasionally triggering Enter (`activate`):**
   - `foundation/src/platform/sf2000/input/unifrog_input.c`: wrapped `scan_gb300_local_raw_once()` and `scan_sf2000_local_raw_once()` shift-register GPIO bit-banging in `arch_local_irq_save()` / `arch_local_irq_restore()` (matching the wireless RF driver) and added `scan_local_raw_stable()`, which performs a fast 20 us re-read / 3-sample majority filter whenever a non-zero raw mask is sampled so single-scan shift-register bit slips (e.g. `START` adjacent to `UP`/`DOWN` on GB300) cannot reach `menu_buttons` without dropping quick taps.
   - `components/frontend/src/app/frontend_app.c`: captured `nav_handled = frontend_input_handle_menu_navigation(...)` and guarded `activate(fe)` against firing on the same poll as navigation or on `UNIFROG_UI_START` while `UP`/`DOWN` is held.
3. **`gambatte-prosty` audio sample rate & slowdown fix:**
   - Root cause: on MIPS (`__mips__`), `gambatte-prosty` defaults `gambatte_audio_resampler` to `"cc"` (Cosine), whose `CC_renderaudio()` (`CC_DECIMATION_RATE = 32`) produces ~65,536 Hz audio (`SOUND_SAMPLE_RATE_NATIVE / 32`), while `#if !defined(SF2000)` / `#else` overrides in `libretro.cpp` forced `retro_get_system_av_info()` to report `32000` Hz. UniFrog saw `input_rate == output_rate == 32000`, skipped downsampling, and pushed 2.048x audio samples into the 32 kHz hardware audio sink, throttling emulation speed to ~50%.
   - `cores/patches/gambatte-prosty/0002-Report-actual-audio-sample-rate-on-SF2000-and-avoid-.patch`: removed the fake `32000` sample rate override in `libgambatte/libretro/libretro.cpp` so `SOUND_SAMPLE_RATE_CC` (~65,536 Hz) and `SOUND_SAMPLE_RATE_BLIPPER` (~32,768 Hz) match what the core actually outputs and UniFrog resamples cleanly; also replaced `fake_rtc_get_time()` + `mktime()` in `libgambatte/src/mem/rtc.cpp` (`get_current_time()`) with `fake_rtc_get_base_time()`.
4. **Fast `Collection` (`Favorites`) & `History` opening:**
   - `components/frontend/src/app/frontend_browser.c` (`frontend_show_file_list()`): removed the per-entry `stat(game, &st)` SD lookup so opening 59+ favorites does not trigger dozens of synchronous FAT32 long-filename directory scans.
5. **Responsive `SELECT + L/R` backlight hotkeys in menu & in-game:**
   - `components/frontend/src/app/frontend_app.c` & `frontend_internal.h` & `frontend_preferences.c`: replaced edge-sensitive `unifrog_ui_repeated()` with a dedicated chord state machine (`backlight_repeat_button`, `backlight_next_repeat_ms`, 220 ms initial / 110 ms repeat) independent of `SELECT` vs `L`/`R` press order, suppressed SD `unifrog.ini` flush while `SELECT` is held, and increased save debounce to `1500 ms`.
   - `components/libretro/src/unifrog_libretro_host.c`: tightened in-game `SELECT+L/R` repeat timing to 240 ms / 110 ms.
   - `foundation/src/platform/sf2000/input/unifrog_input.c`: masked raw equality checks in `scan_local_raw_stable()` with `GB300_VALID_RAW_MASK` (`0x7cfb`) so unused-bit jitter (e.g. bit 15 on GB300 `R`) does not trigger spurious mismatches, and cleared `local_menu_guard` when wireless RF polling is not active so quick taps do not linger for an extra poll.
6. **FrogUI ("Alternate Game Browser") 10s Watchdog Crash Fix & PICO-8 Support:**
   - Root cause: `scan_directory()` in `FrogUI/frogui_libretro.c` called synchronous `stat()` on every file inside `retro_run()`. On HCRTOS FAT32, opening ROM folders with 100–220 files stalled `retro_run()` past 10 s (`10102 ms` observed in `crashlogs_d3295180b532.txt`), tripping `LIBRETRO_WATCHDOG_PHASE_RUN` (`UNIFROG CORE HANG`).
   - `cores/patches/frogui/0002-Avoid-per-entry-stat-stalls-and-support-PICO-8-carts.patch`: switched `scan_directory()` to `entry->d_type` (`DT_DIR`/`DT_REG`, falling back to `stat()` only when unknown), added `.p8`/`.p8.png` and `{"pico8", "fake08-prosty"}` mappings, and exempted `.p8.png` carts from `.png` filtering.
7. **SNES Prosty (`snes9x2005-prosty` & `snes9x2002-prosty`) Slowdown, Audio Rate, & Frameskip Fix:**
   - Root causes: `snes9x2005-prosty/Makefile` (`platform=sf2000`) omitted `-DSF2000_ARITHMETIC_OPTS` globally (only `libretro.c` defined it, leaving `apu.c`/`soundux.c`/`cpuexec.c`/`getset.c`/`gfx.c`/`ppu.c` unoptimized), compiled with `-O2` instead of `-O3`, and set `LOAD_FROM_MEMORY = 0` (16.5 s ROM load stalls). Furthermore, `components/libretro/src/unifrog_libretro_runtime.c` `host_get_variable()` only translated UniFrog `frameskip` for `gpsp*`, leaving `[core.snes9x2005-prosty] frameskip=1` ignored (`snes9x_2005_frameskip=disabled`, zero frames skipped). `snes9x2002-prosty` also hardcoded `AUDIO_SAMPLE_RATE=11025` (forcing host resampling to 32 kHz), and both prosty cores bound `SEL+L`/`SEL+R` hotkeys conflicting with UniFrog brightness.
   - `cores/patches/snes9x2005-prosty/0002-Enable-SF2000-arithmetic-opts-O3-RAM-ROM-load-and-di.patch`: enabled `-DSF2000_ARITHMETIC_OPTS`, `-O3`, `LOAD_FROM_MEMORY = 1`, and disabled conflicting `SEL+L`/`SEL+R` core hotkeys.
   - `cores/patches/snes9x2002-prosty/0002-Use-22050-Hz-native-audio-rate-and-disable-conflicti.patch`: raised `AUDIO_SAMPLE_RATE` to `22050` Hz (supported natively without resampling by `host_audio_output_rate()`) and disabled conflicting `SEL+L`/`SEL+R` hotkeys.
   - `components/libretro/src/unifrog_libretro_runtime.c` (`host_get_variable()`): wired UniFrog's `frameskip` (`OFF` / `AUTO` / `FIXED_1` / `FIXED_2` and fast-forward) to `snes9x_2005_frameskip` / `snes9x_2005_frameskip_threshold` and `snes9x2002_frameskip` / `snes9x2002_frameskip_threshold` / `snes9x2002_frameskip_interval`.
8. **Added Native Cores: `prboom` (Doom 1/2), `nxengine` (Cave Story), & `ecwolf` (Wolfenstein 3D):**
   - `cores/manifest.mk`: pinned `madcock/libretro-prboom`, `madcock/libretro-nxengine`, and `madcock/ecwolf` with SF2000 platform ports (`CORE_PACKAGE_SPECS`, `CORE_LICENSE_SPECS`, `DEFAULT_CORE_IDS`), and updated `THIRD_PARTY.md`.
   - `cores/Makefile`: registered `SF2000_PORT_SPECS`, added `$(BUILD)/libretro-common/file/retro_dirent.o` to `LIBRETRO_COMMON_OBJECTS` (needed for `ecwolf` VFS/dirent directory listing under `STATIC_LINKING=1`), and restricted `ecwolf` `submodule update --init` to `src/libretro/libretro-common` (skipping unused Bitbucket SDL submodules).
   - `cores/patches/prboom/0001-Use-std-gnu89-and-allow-legacy-pointer-conversions-f.patch`: added `-std=gnu89 -Wno-error=incompatible-pointer-types` for SF2000 GCC compatibility in `d_deh.c` / `m_cheat.c`.
   - `components/frontend/assets/defaults/associations.ini`, `components/libretro/src/unifrog_libretro_policy.c`, and `cores/patches/frogui/0003-Map-doom-cavestory-and-wolf3d-cores-in-FrogUI.patch`: mapped `.wad`/`.iwad`/`.pwad`, `.exe`, `.wl6`/`.wl1`/`.sod`/`.sdm`/`.n3d` and system folder names (`DOOM`, `CAVESTORY`, `WOLF3D`).

## Build & Verification
- Verified inside `unifrog-dev:latest`:
  - `make dep-patches-check DEP=frogui`, `DEP=prboom` (and earlier `snes9x2005-prosty`, `snes9x2002-prosty`) (OK)
  - `make core-manifest-check` (OK)
  - `make clean && make verify JOBS=12` (required after core patch/Makefile changes).

## SD Card Deployment Notes (`/media/two/C2B3-81CF`)
- Representative free PICO-8 carts installed to `/ROMS/pico8/` (`rom_system=pico8:fake08-prosty`).
- Official Shareware/Freeware assets installed on SD:
  - Doom Shareware (`/ROMS/doom/Doom/doom1.wad` + `bios/prboom.wad`)
  - Cave Story Freeware (`/ROMS/cavestory/Cave Story (en)/Doukutsu.exe`)
  - Wolfenstein 3D v1.4 Shareware (`/ROMS/wolf3d/Wolfenstein 3D v1.4 (Shareware)/VSWAP.WL1` + `bios/ecwolf.pk3`)
- Updated `bisrv.asd`, `unifrog.bin`, `manifest.ini`, and rebuilt `{frogui,snes9x2005-prosty,snes9x2002-prosty,prboom,nxengine,ecwolf}.bin` deployed to `/media/two/C2B3-81CF` without touching slow cores or user saves.

9. **Performance & Load Fixes (`fake08-prosty`, `prboom`, `nxengine`) + Core Whole-Archive Support:**
   - **`fake08-prosty` (`cores/patches/fake08-prosty/0003-...`, `cores/patches/fake08-prosty-z8lua/0002-...`):**
     - Replaced `FastFmod1`/`FastFabs` soft-float audio synthesis on `SF2000` with pure-integer Q16/fixed-point mixing (`mixSfxFixed`, `evalChildSfxSampleFixed`, `evalWaveformFixed`) at consistent `22050` Hz (removing the `11025` Hz mismatch that caused 50% speed and buffer overflows).
     - Replaced software `sin`/`cos`/`sqrt` in `libs/z8lua/lpico8lib.c` with a 257-entry Q16.16 LUT + integer 64-bit `isqrt`.
     - Disabled the forced 90-frame splash screen on `SF2000`, synced 60fps (`367`/`368` samples) vs 30fps (`735` samples every other frame) audio batching, skipped redundant pixel conversion on odd dupe frames of 30fps carts, added a `pal16[16]` 1x render fast loop, and switched `platform=sf2000` non-DEBUG to `-O3`.
   - **`prboom` (`cores/patches/prboom/0002-...`):**
     - Removed `HAVE_LOW_MEMORY = 1` (`-DMEMORY_LOW`) so `w_wad.c` enables WAD RAM caching inside external RAM, switched `platform=sf2000` to `-O3 -DNDEBUG -ffunction-sections -fdata-sections`, defaulted `level_precache=1` and `mus_load_external=0` (eliminating multi-second FAT32 `.mp3` directory scans on track changes and changing miss logs to `RETRO_LOG_DEBUG`), and switched `libretro_sound.c`/`libretro.c` on `SF2000` to integer `22050` Hz resampling + `while (leftout < leftend)` + active-channel pre-collection.
   - **`nxengine` (`Makefile`, `cores/manifest.mk`, `cores/patches/nxengine/0001-...`):**
     - Enabled `FRONTEND_SUPPORTS_RGB565 = 1`, `SINGLE_PRECISION_FLOATS = 1`, `-O3 -DNDEBUG`, and `-fno-rtti -fno-exceptions -fno-use-cxa-atexit` for C++ `.cpp` objects in `platform=sf2000`.
     - Added in-RAM `Doukutsu.exe` caching (`exe_mem_load`/`exe_mem_read`/`exe_mem_getl`/`exe_mem_getfloat` skipping the 4-byte padding in `rfgetfloat`, matching `common/misc.c`) plus lazy on-demand `copen()` asset loading so startup does not open 399 individual FAT32 files; widened `hash_struct.filename` to `128`; replaced unaligned `*(double *)` casts in `common/misc.c` with `memcpy`.
     - Added `NXENGINE_CORE_WHOLE_ARCHIVE := 1` in `Makefile` (`CORE_MODULE_RULES`) so all 69 `INITFUNC(AIRoutines)` static constructors inside `nxengine_libretro_sf2000.a` are preserved in `__CTOR_LIST__`.
10. **O(1) External Core Module Heap (`module_heap`) & Further `fake08-prosty` Audio/Graphics Fixes:**
   - `foundation/src/modules/unifrog_core_module_support.c`: replaced the O(N) linear free-block scan (`module_heap_alloc_aligned`) and full-heap coalescing walk (`module_heap_coalesce`) with a 24-bin segregated free list (`module_heap_bins` + `module_heap_bin_bitmap`) and O(1) bidirectional physical boundary-tag coalescing (`prev_phys`/`next_phys`) in `module_heap_free()`, eliminating O(N²) Lua GC/room-load multi-second stalls and the >10s `Celeste Classic 2` load watchdog reset.
   - `cores/patches/fake08-prosty/0004-Fix-Audio.cpp-stack-bloat-divisions-pattern-1-bounds.patch`: guarded `set_music_pattern(pattern < 0 || pattern > 63)` against out-of-bounds reads, moved `FillAudioBuffer`'s 8.5 KB `mixBuf`/`chanBuf` stack arrays into static storage (shrinking frame from 8496 to 344 bytes), replaced per-sample 64-bit divisions (`s_c2_freq_q16`, `fade_dur_q24`) with precomputed reciprocals, refreshed `childCh`/`prevChildCh` after `rotateChannels()`, and added `copySpriteToScreen()` (`hwState.colorBitmask == 0xff`) and `Graphics::map()` loop-hoisting/clip-culling fast paths in `graphics.cpp`.

## Standing Workflow Rule
- After every fix: verify clean build, deploy updated binaries/configs to `/media/two/C2B3-81CF`, commit & push changes to `origin/dev`, and create an SD backup snapshot (excluding `ROMS` and `System Volume Information`) in `/home/two/Code/backups/`.
