# Mouse Frontier for Android

The Android edition uses the same Lua game and save schema as the Windows edition. There is no copied mobile gameplay tree to synchronize.

## Current build

- Application ID: `com.mousefrontier.game`
- Version: `0.7.0-mobile.5` (`versionCode` 5)
- Engine: LÖVE 11.5
- Orientation: landscape fullscreen
- Architectures: ARM64 and ARMv7; debug builds also contain x86-64 for emulator testing
- Saves: private Android application storage under the shared `mouse-frontier` LÖVE identity

The generated installable file is:

`output/mobile/MouseFrontier-0.7.0-mobile.5-debug.apk`

This update packages the current shared gameplay, Last Stand quest, wilderness
expeditions, crow caravans, first-person weapons, and directional character
animations. The mobile package preserves Last Stand's fixed atlas cells and
omits its unused concept and candidate artwork.

## Phone controls

- Drag the lower-left thumb control to walk. It is inset from the phone corner for a comfortable natural thumb reach.
- Push it to the outer edge to run.
- The large lower-right button changes with context: Use, Pick Up, Talk, Enter, Exit, Board, Door, Coal, or Radio.
- A Give button appears beside NPCs and passengers.
- Menus, inventory, the map, travel prompts, events, and battles use direct touch.
- Settings provide shared text sizing, high contrast, reduced motion, optional guidance, tap confirmation, and large thumb controls. Battle ability explanations never require hover.
- Pinch zoom and two-finger pan use the shared camera in gameplay, battles, menus, and overlays; fixed thumb, back, and menu controls remain anchored to the phone edges.
- The complete seven-car navigator fits the shared phone canvas and supports direct touch selection; train condition, projected wear, oil capacity, and servicing use the same rules as Windows.
- Android Back behaves like Escape: close an overlay or request a return to the title screen.
- Losing focus releases held touches and flushes pending save data.

## Build or install

Run from PowerShell at the project root:

```powershell
.\BUILD_ANDROID.ps1
```

The first build downloads verified local copies of FFmpeg, JDK 17, the Android command-line tools, API 34, NDK 25.2, and LÖVE Android 11.5. They are cached under ignored `output/mobile` files. Later builds reuse them.

The packaged smoke run requires a local LÖVE installation and uses the shared
`tools/run_smoke.ps1` watchdog. Missing LÖVE or a failed smoke run stops the build.
The build also runs the Last Stand harness against the staged mobile Lua, resized
artwork and converted audio before producing the APK.
The APK builder rejects stale Lua or version metadata, verifies the embedded
game's full SHA-256, Android identity and version, all three supported native
architectures, and the APK signature. `build-report.json` and `apk-report.json`
record the source commit and matching package checksum.

To build only the testable `.love` archive:

```powershell
.\BUILD_ANDROID.ps1 -PackageOnly
```

To install over the existing app while exactly one USB-debugging-enabled phone is connected:

```powershell
.\BUILD_ANDROID.ps1 -Install
```

The install command preserves existing saves, launches the installed app, and
waits for a Mouse Frontier-specific startup marker. It fails rather than
reporting success if Android shows LÖVE's fallback screen or the game crashes
during startup.

The current APK is debug-signed for sideloading and development. A store/release build requires a protected release keystore and should be produced as an Android App Bundle.

## Bringing across a PC update

1. Make or merge the PC change in this repository.
2. Preserve save compatibility or add the next sequential save migration.
3. Update `versionName` and increment `versionCode` in `mobile/config.json` for a distributable Android update.
4. Run `tools/run_smoke.ps1` for the normal desktop smoke playthrough.
5. Commit the reviewed changes and run `BUILD_ANDROID.ps1`. It takes the current shared Lua directly, incrementally regenerates phone-sized assets, runs the packaged mobile smoke checks, builds the APK, and verifies its contents and signature.
6. Install on a phone and complete the device checklist below.

Only conflicts inside the small mobile boundary described in `MOBILE_ARCHITECTURE_DECISION.md` should require Android-specific adaptation. Ordinary gameplay, content, art, save, and UI updates are inherited by the next build.

After recording the desktop and full-route reports described in
`FINAL_PARITY_AUDIT.md`, `python tools/audit_platform_parity.py` verifies the
offline artifacts. Add `--require-device` to require the recorded on-device
startup check as well. An offline pass does not establish physical-device
readiness; the controls checklist still applies before distribution.

## Physical-device release checklist

Validated on August 22, 2026 with a Galaxy S25 Ultra running Android 16:
installation/update-in-place, cold launch, landscape/fullscreen rendering,
save creation and relaunch persistence, save-slot and character touch menus,
joystick movement, contextual storage opening, and mobile HUD wording.

- Fresh install reaches save-slot and character selection screens.
- Existing app updates in place and retains all three save slots.
- Thumb movement and simultaneous action touches work without duplicate taps.
- Every contextual action is reachable, including held furniture pickup.
- Inventory drag/drop, map scrolling, options, radio, events, and battle controls work by touch.
- Android Back closes overlays and does not accidentally quit.
- Home/app switching preserves progress and stops stuck movement or audio.
- A complete travel transition, stop, home, battle, and save/relaunch cycle succeeds.
- Performance and memory remain acceptable on the oldest supported test phone.

## Size policy

The source repository contains several gigabytes of authored and high-resolution material. The mobile build excludes generation sources, keeps one copy of duplicate music, converts runtime audio to Ogg Vorbis, and derives phone-resolution palette PNGs. Character animation sheets retain every authored direction and use a uniform phone-sized frame so idle and walking scale remain synchronized. Originals remain unchanged for the PC edition and future art work.
