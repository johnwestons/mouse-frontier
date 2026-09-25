# Current-state game audit — September 25, 2026

This is a working audit of the shared Windows and Android game. It tracks verified fixes separately from unfinished content so the playable build and the remaining work can be reviewed independently. The relevant test saves may be wiped if needed; this audit has used isolated identities and the existing smoke slot 99, without resetting normal player slots.

## Problems found and fixed

- **Expedition defeat on mobile:** the train return point placed the player too close to the fixed USE control. The return point now sits farther left on the valid perspective floor. Both desktop and mobile full-application expedition paths pass, including the mobile control-clearance check.
- **Desktop side HUD:** the level/ability and train/car labels exceeded their text boxes during stop interactions. The narrow layout now uses shorter labels and separate train-condition and car-count rows. Normal and extra-large desktop captures fit.
- **Conversation visual audit:** the harness called retired generated dialogue and stopped partway through. It now uses the approved conversation content and checks all 13 questions, 39 responses, and three choices per question at normal and extra-large text. Rendered text overflow now fails the audit.
- **Outdated layout tests:** the train-view and architecture tests still expected the old house coordinates and button positions. They now verify the current fitted house and side-panel controls.
- **Expedition preview cleanup:** the runner now removes its temporary stage and asset junctions after success or failure.

## Verification completed

| Check | Result |
| --- | --- |
| Full Python regression suite | 274 passed, no skips, after all current code and audit changes |
| Desktop gameplay smoke | 88 checkpoints passed |
| Mobile source gameplay smoke | 95 checkpoints passed |
| Full route | Reached stop 50 ending |
| Last Stand rescue and defense | 163 checks passed; 180-second hold, 15 kills, save/resume |
| Expedition full-application path | 14 stages passed on desktop and mobile, including defeat return |
| Desktop and mobile UI | 33 captures each; no text overflow, including extra-large stop HUD |
| Desktop and mobile train presentation | 16 captures each passed |
| Mobile pickup and character-motion runtime | 48 pickup checks and runtime motion test passed |
| Shootout review steps S03, S04 and S08 | Captures and behavior remain documented in `docs/SHOOTOUT_REVIEW.md`; the Last Stand smoke covers their directional character animation, backyard presentation, and incoming-fire effects |
| Android clean-commit build and device startup | Signed APK and embedded game checksum verified; 88 desktop checkpoints are present in the 95-check packaged mobile run; installed APK reached the game startup marker on one connected device |
| Conversation text fit | All 13 approved questions and 39 responses fit at normal, large, and extra-large text on desktop and mobile; 39 question and 117 response layouts per platform |
| Installed character sprites | 54-directory scan found no structural errors. All 12 strictly accepted roster characters had zero warnings when checked against their own build manifests |

Reports and temporary captures are under `.stabilization/`. The expedition runner's normal output in `docs/concepts/expedition-validation/` was restored after inspection; the updated mobile defeat image is retained in `.stabilization/goal-audit-mobile-return.png`.

## Work still open

- Complete the physical-device touch, save, and visual checklist. The installed APK passed startup and package parity, but another app took the foreground before a game-screen capture could be reviewed.
- The character-motion ledger records 12 currently strict accepted characters out of 47. The broad scan's 1,343 warnings mostly came from applying a generic frame rule to those accepted characters; all twelve passed their individual contracts without warnings. Nine older sets still show 42 warnings under their own contracts. Courier Lizard's staged set has zero motion-audit issues but 16 Sprite Doctor height warnings and was never installed. Earlier draft validation now invokes Sprite Doctor, but the staged art and semantic acceptance still need review. Other legacy-complete characters remain in a reconciliation queue.
- The expanded spoken dialogue pool and the retired conversation quests require author-supplied or explicitly approved character speech. The game retains neutral task interfaces until that writing is supplied; the missing contexts are listed in `docs/DIALOGUE_REVIEW.md`.

These open items keep the audit goal active. Passing current runtime checks does not certify unreleased art, new dialogue, or an untested Android device.
