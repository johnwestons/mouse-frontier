# Train Presentation and Maintenance

The desktop and Android builds use the same authored train geometry, car navigator, maintenance condition, and upgrade rules. A shared presentation transform fits the complete locomotive and active car to the actual screen at normal camera zoom.

## Train presentation

- Canonical coordinates stay fixed: car x 429, width 620, locomotive nose -115, coupling point 431, and wheel contact y 670. Saved furniture, player and passenger coordinates are never rewritten when the window or device changes.
- `game/train_view.lua` fits the union of all seven car silhouettes, the locomotive, smoke and running-gear phases. It uses the largest uniform scale within 20 logical pixels of the physical screen edges and the space below the HUD/car navigator. The highest roof is the medical car; rotating wheel corners and rear couplers are included in the bounds.
- One parent transform scales the locomotive, shell, boiler/fire, wheels, rods, coupling, furniture, player, passengers, interaction markers and track together. At 2340×1080, the single-car view is about 30% larger than the former fixed layout. A 4:3 view fits the full train instead of cropping its nose and rear.
- The same inverse transform handles world picking, hover and furniture dragging. Menus and editor controls keep their UI coordinates. Camera zoom focuses on the fitted player position, and sliding transitions travel far enough to leave the physical viewport.
- The living car uses the final positions captured from the in-game editor: radio `(car + 115.9, carY + 289.4)`, travel chest `(car + 312.1, carY + 268)`, and reward mailbox `(car + 394.9, carY + 230.9)`. A versioned migration applies these anchors to existing saves once.
- `railway-track-v2.png` replaces the perspective pair with one transparent, flat side-elevation rail aligned to the wheel-contact baseline.
- The locomotive's authored width remains 546; further presentation scaling is shared with the car and contents rather than applied to the engine alone.
- The track scrolls 8% faster than the background for restrained foreground parallax.
- Scrolling stop backgrounds render 90 virtual pixels lower to match the marked ground line. The overscan quad covers fullscreen side pillars, while a 64-source-pixel cyclic feather joins the two ends without black borders, hard loop seams, or a mirrored reflection cusp.
- Exactly one active car is rendered at the canonical interaction coordinates. Changing car type retains a common scale and anchor system, with space reserved for the seven-car navigator.
- A numbered consist navigator fits all seven possible cars. Its rectangles are shared mouse and touch targets, and selecting any owned car starts the normal door transition.
- Player, passenger, furniture, storage, mailbox, and door coordinates no longer receive a render-only offset in additional cars.

## Running animation and visual regression contract

- The approved red boiler, cab, tender, cowcatcher, and car shell remain invariant. The locomotive composes three generated driver wheels and calculated rods over that body; the car composes four generated bogie phases over a masked undercarriage.
- Driver rotation comes from traveled track pixels. All three crank pins share one phase, the coupling rod stays rigid and horizontal, the piston crosshead stays on its guide, the connecting rod keeps a fixed length, and the far-side gear is quartered by 90 degrees.
- The track uses a fixed `96/181` authored scale inside the shared train transform. A stable flat rail bed and four ballast pocket frames share the same scroll distance. Draw scales account independently for actual rail and ballast dimensions; coverage uses the inverse-fitted viewport, so the track remains continuous at every aspect ratio.
- Car bogies likewise convert each actual atlas frame back to its authored 543×724 coordinates. Mobile downsampling no longer changes their wheel contact or spacing.
- `Train.audit` checks 18 desktop/mobile/car-count layouts, complete visibility, maximum fit, rail contact, the real body/coupler anchors, coordinate inversion, track coverage, and mechanical invariants. Train-view, editor-input, bogie-rendering and sprite-asset tests protect the shared transform and packed texture anchors.
- `tools/tests/test_train_track_rendering.py` checks actual draw transforms with authored and resized mobile images. Build `0.7.0-mobile.7` was visually verified on a Galaxy S25 Ultra running Android 16 on September 11, 2026: the floating ballast and track gaps reproduced on build 6 are corrected.
- The September 12 train-fit update passed 200 regression tests, desktop/mobile smoke playthroughs, and 16 real-application train captures each for desktop, mobile presentation, and the actual packed mobile artwork. Run `tools/mobile-ui-audit/run.ps1 -Train` (add `-Desktop` for desktop). Build 9 physical-device validation remains pending while the phone is disconnected.
- Set `MOUSE_FRONTIER_SMOKE=1` for the complete deterministic playthrough. Add `MOUSE_FRONTIER_SMOKE_CAPTURE_TRAIN=1` to create four 1920×1080 phase captures named `train-animation-phase-01.png` through `train-animation-phase-04.png` in the LÖVE save directory for a rapid visual review of wheels, rods, bogies, stones, fullscreen coverage, and background seams.

## Condition and wear

Condition ranges from 0 to 100 and begins at 72 for legacy-compatible saves. Each journey applies:

`wear = route wear + train-length wear - engine wear reduction`, with a minimum of 3.

| Factor | Rule |
| --- | --- |
| Route wear | 5 at stops 1–15, 6 at 16–30, 7 at 31–45, and 8 afterward |
| Train length | +1 at four cars and +2 at seven cars |
| Rebuilt Boiler | -1 wear |
| High-Pressure Drive | -1 wear |
| Frontier Express | -2 wear |

Condition of 25–49 adds one coal to a journey and runs travel at 92% speed. Condition below 25 adds two coal and runs at 82% speed. The journey HUD shows condition, status, and projected wear before departure.

## Oil and servicing

- Base train oil capacity is 20.
- Owning the Coal Hauler raises coal and oil capacity to 30.
- A completed running-gear service costs 5 oil and restores 40 condition.
- Oil is charged atomically when all five lamps are lit and the player confirms completion.
- A train can be serviced once at each stop; reopening the activity at that stop preserves the completed state.

The train workshop shows current condition, oil capacity, and the wear reduction supplied by the installed engine. `Maintenance.audit` and `Train.audit` protect these rules in both package variants.
