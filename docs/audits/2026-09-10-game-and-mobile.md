# Game and mobile audit — September 10, 2026

This checkpoint includes the accumulated gameplay, animation, art, tools and documentation changes, plus the audit fixes below. Android version is `0.7.0-mobile.5` (`versionCode` 5); the save schema remains version 33 and retains legacy migration and backup recovery.

## Fixed during the audit

- Battle inspection no longer substitutes another unit's equipment or exposes controls that skip enemy turns. Keyboard actions also respect active turns, health and the battle introduction.
- Health potions apply their maximum-health effect through backpack use and quick healing, with save/reload coverage.
- Mobile battle messages, active-unit health and the persistent ability explanation remain visible above and between the controls.
- Borrowing the Last Stand rifle preserves personal weapon sessions and cannot repeatedly grant ammunition while house supplies remain.
- First-aid treatment respects pause, supports controller advancement, and retains completed progress. Mouse, touch and gamepad aiming no longer cancel one another merely because a controller is connected.
- Last Stand uses the converted Android audio files, honors reduced-flash effects, avoids repopulating enemies after victory, and releases its private scene/weapon resources after returning.
- The surviving water pump has a visible prop, runoff warning, repair label and completion feedback. Its hazard was previously active while its draw function was empty.
- Failed scheduled saves remain queued for retry. Invalid non-finite values and keys are rejected before they can silently disappear during serialization or replace a valid save.
- Mobile packaging preserves the fixed-cell Last Stand animation sheets, excludes unused candidate art, and checks source inventory, archive hashes, APK identity/version, signatures and architectures.
- Smoke runners are now tracked, use watchdogs, reject capture-only/incomplete reports, and support the packaged game. The full Python test runner rejects missing dependencies and skipped behavior tests.
- Controls, current activity status, character mirroring and release instructions were brought into agreement with the game.

## Verification

| Check | Result |
| --- | --- |
| Full Python regression suite | 125 passed; no skipped tests |
| Desktop smoke | 88 checkpoints passed |
| Packaged mobile smoke | 96 checkpoints passed, including all 88 desktop checkpoints and 8 touch checks |
| Full journey | Stop 50 reached; both route checkpoints passed |
| Last Stand source and staged mobile content | 131 checks each, actual save/reload, full 180-second defense, rewards and return |
| Expedition integration | 14 stages each on desktop and mobile; battle layout visually inspected |
| Crow caravan | Trading/stock and campsite navigation/persistence harnesses passed |
| Character motion | Runtime controller checks passed; representative 5-view and 8-view strict audits have zero errors or warnings |
| Packaged directional animation inventory | All 680 locomotion strips across 44 upgraded characters have their expected 256-pixel cells |
| Water-pump rendering | Unrepaired and repaired states rendered and visually inspected |
| Smoke watchdog negative case | Capture-only run correctly rejected with exit code 2 |

The mobile package is rebuilt after the complete Git commit so `output/mobile/build-report.json` identifies clean `HEAD`. `output/mobile/apk-report.json` records the signature, version, architectures and embedded archive hash. `.stabilization/final-parity-audit.json` records the final comparison against that commit. Generated reports and installable files stay outside Git.

## Delivery and remaining acceptance

The installable development build is `output/mobile/MouseFrontier-0.7.0-mobile.5-debug.apk`. It is debug-signed for sideloading. No Android device was connected during this audit, so fresh on-device launch, touch usability, update/save retention and hardware performance acceptance remain unverified. The repository's August device result is historical, not evidence for this APK.

This audit completed defects and incomplete integration in the implemented game. Deliberately retired community minigames, a future authored pump minigame and expanded regional dialogue remain content plans in `GAMEPLAY_ROADMAP.md`; they were not silently reinstated or marked complete. The existing local-audio exclusion policy is preserved; the mobile package includes the available runtime audio.

See [the repeatable release checks](../../FINAL_PARITY_AUDIT.md) for the exact commands, including physical-device acceptance when a phone is available.
