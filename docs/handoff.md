# UniFrog Session Handoff

## Branch & Repository State
- **Branch:** `dev` (ahead of `origin/dev` at `f039084` by local commits).
- **Recent commits before this handoff:**
  - `ebbeb11` — Fix `gambatte-prosty` FakeRTC load hang (time-domain underflow / truncated `gambatte_rtc.dat`), external core `fopen()`/`fileno()`/`_fwrite_r`/`_fflush_r` support in `foundation/src/modules/unifrog_core_module_support.c`, and loader teardown/watchdog fixes.
  - `0b3b32f` — Add reproducible Ubuntu 24.04 Dockerfile (`unifrog-dev:latest`).
  - `d329518` — Fix libretro audio upsampler loop in `components/libretro/src/unifrog_libretro_runtime.c` and RACE native 44.1 kHz audio + in-memory ROM loading.

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

## Build & Verification
- Verified inside `unifrog-dev:latest`:
  - `make dep-patches-check DEP=gambatte-prosty` (OK)
  - `make core-manifest-check` (OK)
  - `make clean && make verify JOBS=12` (exit 0; includes `quick-check`, `host-full-check`, `check`, and `fastboot-check`; generates `bisrv.asd`, `fastboot.asd`, and `output/sdcard/`).

## SD Card Deployment Notes (Observed at `/media/two/C2B3-81CF`)
- The mounted SD card still had the older `0b3b32fe4325` build and `/unifrog_data/unifrog.ini` containing `extension.md.default=reader` and `gambatte_audio_resampler=cc`. It was **not** modified automatically.
- To deploy the new build to the SD card, copy from `output/sdcard/` (and root `bisrv.asd` / `fastboot.asd` if updating bootloader/firmware):
  - `output/sdcard/unifrog/firmware/unifrog.bin` -> `<SD>/unifrog/firmware/unifrog.bin`
  - `output/sdcard/unifrog/cores/gambatte-prosty.bin` -> `<SD>/unifrog/cores/gambatte-prosty.bin`
  - `output/sdcard/unifrog/unifrog.ini` -> `<SD>/unifrog/unifrog.ini` (or update `extension.md.handlers=picodrive,reader` and `extension.md.default=picodrive` in `<SD>/unifrog_data/unifrog.ini` as well, since `/unifrog_data/unifrog.ini` overrides defaults).

## Remaining Hardware Checks
- Test on GB300/SF2000 hardware:
  1. Launch a `.md` ROM from `/ROMS/sega/` (and confirm Markdown files in other folders can still open with `reader` via `X` -> Open With).
  2. Navigate menus up/down rapidly on GB300 to confirm no spurious Enter/launch events occur.
  3. Run a GB/GBC game in `gambatte-prosty` (`gambatte_audio_resampler=cc`) and check `unifrog perf` / audio rate in `/unifrog_data/logs/` to confirm 60 fps full speed and clean ~65536->32000 Hz resampling.
