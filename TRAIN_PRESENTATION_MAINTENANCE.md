# Train Presentation and Maintenance

The desktop and Android builds use the same 960×720 train geometry, car navigator, maintenance condition, and upgrade rules.

## Train presentation

- The two marked layout passes move the complete consist 225 virtual pixels forward: 130 pixels initially and another 95 after enlarging the locomotive. The active car begins at x 540; its decorative rear may extend past a 4:3 canvas while its permanent interaction anchors remain reachable.
- The living car uses the final positions captured from the in-game editor: radio `(car + 115.9, carY + 289.4)`, travel chest `(car + 312.1, carY + 268)`, and reward mailbox `(car + 394.9, carY + 230.9)`. A versioned migration applies these anchors to existing saves once.
- `railway-track-v2.png` replaces the perspective pair with one transparent, flat side-elevation rail aligned to the wheel-contact baseline.
- The locomotive renders 30% larger than the previous presentation while retaining its rail-contact anchor.
- The track scrolls 8% faster than the background for restrained foreground parallax.
- Scrolling stop backgrounds render 90 virtual pixels lower to match the marked ground line. The overscan quad covers fullscreen side pillars, while a 64-source-pixel cyclic feather joins the two ends without black borders, hard loop seams, or a mirrored reflection cusp.
- Exactly one active car is rendered at the canonical interaction coordinates. Sliding transitions move complete outgoing and incoming views by one canvas width.
- A numbered consist navigator fits all seven possible cars between x 430 and 935. Its rectangles are shared mouse and touch targets, and selecting any owned car starts the normal door transition.
- Player, passenger, furniture, storage, mailbox, and door coordinates no longer receive a render-only offset in additional cars.

## Running animation and visual regression contract

- The approved red boiler, cab, tender, cowcatcher, and car shell remain invariant. The locomotive composes three generated driver wheels and calculated rods over that body; the car composes four generated bogie phases over a masked undercarriage.
- Driver rotation comes from traveled track pixels. All three crank pins share one phase, the coupling rod stays rigid and horizontal, the piston crosshead stays on its guide, the connecting rod keeps a fixed length, and the far-side gear is quartered by 90 degrees.
- The track uses a fixed `96/181` world scale at every aspect ratio. A stable flat rail bed and two complementary stone bands share the same scroll distance; the stone bands cycle through four one-pixel vibration frames and alternate their front priority.
- `Train.audit` now checks six desktop/mobile/fullscreen layout shapes, rail contact, the real body/coupler anchors, track coverage, and mechanical invariants. `tools/tests/test_train_sprite_assets.py` checks the generated PNG dimensions, transparency, stable frame bounds, contact baselines, unique phases, and safe atlas edges.
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
