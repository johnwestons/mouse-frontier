# September 11 game audit and Android update

This follow-up audits the recent shared game changes and completes mobile weapon-grip aiming and Last Stand cover. Android version is `0.7.0-mobile.8`, version code 8.

## Completed fixes

- Both shooting minigames share calibrated grip placement for all 46 first-person weapons: 117 view anchors across 103 source images. The first touch holds the weapon handle; the reticle remains above it. A second field touch or FIRE shoots at the established aim. Aiming down sights preserves the calibrated sight position. Desktop mouse aiming retains its existing behavior.
- Touch ownership survives firing and control-button taps, and is cleared on release, session changes, cancellation, and Last Stand focus loss. An idle controller no longer overwrites touch aiming.
- The range FIRE button is in the bottom toolbar. It no longer intercepts a valid right-side grip position on 4:3 tablets.
- C or COVER visibly lowers the house-defense view behind the window sill and lowers the weapon. Both incoming damage and outgoing fire are blocked until the player has fully returned to the window. The hold timer pauses while crouched; enemies continue their attack cycles.
- Exposed enemy shots have a 12–19.5% hit chance by phase at the wide window, reduced by the tall window's existing protection factor. Regular hits cost 1 HP and heavy hits 2 HP, with 0.9 seconds between damaging hits. The HUD shows actual health and hits immediately save that health. Critical wounds pull the player back at 1 HP; retry preserves the injury.
- Updated regression checks for the current HUD and mobile controls. The full-defense test now takes cover against telegraphed enemy fire instead of remaining exposed after the minimum kills.

## Audit coverage

The independent review also checked removed stop-activity wiring and save migration, inventory and trading hit areas, typography, mobile HUD coordinates, train track scaling, and the three recently updated character animation sets. No additional actionable runtime defects were found in those changes. All recent source, licensed font, animation, documentation, and verification changes are included in the requested Git checkpoint.

Validation records are written to ignored `.stabilization` files:

- Full regression suite: 180 tests passed with no skips (`september11-regression-final.log`).
- Desktop playthrough: `desktop-smoke.rpt` (88 checkpoints).
- Full route: `final-parity-route.rpt` (journey to stop 50).
- Mobile playthrough: `mobile-package-smoke.rpt`; the build runs this against the actual packaged game.
- Last Stand: 158 source checks, including complete 180-second defense, actual saving/loading, hit and miss rolls, both window types, cover animation, mobile buttons, withdrawal, and rewards. The Android build repeats the same harness against staged assets and converted audio.
- Mobile and desktop UI audits: 32 rendered screens each, including phone, 16:9, 4:3, and zoomed HUDs. Source captures include held mobile weapon placement and both covered house windows.
- `final-parity-audit.json` verifies matching desktop/mobile checkpoints, clean source commit, archive hashes, Android identity/version, native architectures, and APK signature after the build.

## Delivery and remaining acceptance

The build output is `output/mobile/MouseFrontier-0.7.0-mobile.8-debug.apk`. The Android package is rebuilt after the complete Git checkpoint; generated packages and reports remain outside source control. The previously installed version 7 is historical evidence, not a device acceptance result for version 8.

Physical-device touch comfort, performance, and update/save retention still need a test of this APK. This audit finishes the implemented shooting changes and checks current game integration. It does not claim completion of the separately tracked whole-roster art overhaul: `character-motion/progress.json` records remaining review and animation work, and `GAMEPLAY_ROADMAP.md` retains future content plans.
