# Mouse Frontier for Android

The Android edition uses the same Lua game and save schema as the Windows edition. There is no copied mobile gameplay tree to synchronize.

## Current build

Build `0.7.0-mobile.9` (`versionCode` 9) adds the September 12, 2026 train fit update. The locomotive, active car, characters, furniture and running gear share one uniform transform that fills the available screen without cropping. Saved positions stay unchanged; world picking and editor dragging use the matching inverse transform. Resized mobile bogie textures retain their original wheel-contact anchors.

It also includes the September 11,
2026 mobile UI and shooting update. It bundles Courier Prime regular and bold typewriter
fonts at a shared 20-pixel base size, measured text wrapping, and a larger
journey HUD spanning the physical screen width while staying fixed during world
zoom. Menus, settings, inventory, battles, dialogue, trading, and activity
interfaces also receive readability and fit improvements. Mobile shooting uses
calibrated weapon grips: the first finger holds and aims the weapon, while a
second touch or the footer FIRE button shoots without moving the reticle.
Last Stand now visibly crouches below the sill, shields the player while covered,
and applies enemy hits to persistent player health while exposed.

Build 9 artifact:
`output/mobile/MouseFrontier-0.7.0-mobile.9-debug.apk`.

Last installed build:

- Application ID: `com.mousefrontier.game`
- Version: `0.7.0-mobile.8` (`versionCode` 8)
- Engine: LÖVE 11.5
- Orientation: landscape fullscreen
- Architectures: ARM64 and ARMv7; debug builds also contain x86-64 for emulator testing
- Saves: private Android application storage under the shared `mouse-frontier` LÖVE identity

The last installed file was:

`output/mobile/MouseFrontier-0.7.0-mobile.8-debug.apk`

Build 8 was installed and visually checked on the connected Galaxy S25 Ultra. All three save slots and their backups were byte-for-byte unchanged; evidence is in `output/mobile/ui-audit/root-device-verification.json`. Build 9 device validation is pending reconnection of the phone.

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
- Build 8 uses Courier Prime throughout the shared text interface and expands the journey HUD across the physical screen; the HUD stays fixed when the world camera moves or zooms.
- Shooting range and Last Stand: hold a finger on the weapon's grip and drag to aim. The reticle stays above the finger. A second field touch or FIRE shoots; AIM switches between hip and sight views. Releasing the firing finger never transfers aim ownership.
- Last Stand: C or COVER lowers the view below the window. Incoming fire cannot hurt the player while crouched or rising. Firing resumes once the view returns to the window. Enemy hits while exposed reduce saved health; critical wounds force a retreat with 1 HP and do not heal on retry.
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

Build `0.7.0-mobile.7` was installed in place over build 6 on September 11, 2026
on the same Galaxy S25 Ultra (`SM-S938U`, Android 16). Floating ballast rocks and
a wide gap between track tiles were reproduced on build 6. A build 7 device
capture confirms continuous rails and ballast correctly positioned beneath
them. The renderer now accounts independently for the resized rail image and
ballast frames; the mobile textures retain their existing sizes.

Build 7 passed all 95 packaged mobile smoke checkpoints, 131 staged Last Stand
checks, and eight train-specific regression tests. The new rendering tests fail
against the previous renderer. All three phone save slots were backed up before
installation to
`output/mobile/train-render-device/saves-pre-install-20260911-100847.tar`.

Build `0.7.0-mobile.6` was installed in place over build 4 on September 10, 2026
on the connected Galaxy S25 Ultra (`SM-S938U`, Android 16). All three save slots
were backed up before installation and migrated from save schema 30 to 33 on
first launch. Cold startup, landscape rendering, touch selection of Continue,
loading the existing Stop 14 game, and background/cold-relaunch persistence were
verified on the phone. The game was left on its save-selection screen.

This build also passed 144 regression tests with zero skips, all 96 packaged
mobile smoke checkpoints, and 131 staged Last Stand checks. The package contains
all 126 current Lua files, six expedition images and 700 mobile locomotion strips.
It intentionally includes the latest working-tree changes; it is a debug-signed
development update, not a clean-commit store release. Extended combat, multi-touch
and performance acceptance on physical hardware remain separate checklist items.

The original phone saves are retained in
`output/mobile/device-backup-20260910-111939/mouse-frontier-pre-mobile-6.tar`.
Installation identity, signature, archive checksums and startup confirmation are
recorded in `output/mobile/apk-report.json`; launch and gameplay captures are
saved as `output/mobile/device-mobile-6-*.png`.

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
