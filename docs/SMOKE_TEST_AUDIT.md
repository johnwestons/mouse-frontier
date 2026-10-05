# Smoke-test capability audit

Audit dates: October 4–5, 2026. Scope: current shared game source, its automated regression suite, and Windows LÖVE harnesses. Android/iOS hardware and packaged release acceptance were not part of this run.

## Assessment

The original smoke suite was useful for startup, composition, balance contracts, rendering, basic navigation, and save handling. It did not exercise enough complete gameplay outcomes to establish that combat, treatment, looting, and campaign completion worked. Several harness defects also allowed missing evidence to be treated as success. This audit strengthens those checks and connects the previously separate suites into one command.

The new system is suitable for repeatable source regression checks. It still needs unassisted campaign playthroughs, longer running sessions, and real device/visual acceptance before it can establish that the whole game is ready for release.

## Findings and changes

| Finding | Change | Evidence |
| --- | --- | --- |
| A check returning `nil` could pass; expectations could be skipped when a snapshot was missing. Thrown expectation errors and completion-hook failures were not consistently represented as failed steps. | Controller validates a nonempty dense plan, requires a check or expectations, rejects missing snapshots and false/nil checks, treats thrown errors as fatal, and records completion only after successful completion hooks. | Focused Lua behavior tests exercise these cases, timeout details, and action hooks. |
| Failed checkpoints and report write/flush/close errors could produce misleading success. | Reporter forces a failed summary for recorded failures, propagates filesystem errors, and supports retry without duplicate summaries. | Focused behavior tests simulate both LÖVE and native file failures. |
| A report did not prove that the requested, complete run had executed. | Watchdog checks run identity, seed, step size, character when requested, mode, mobile setting, scope, exactly one successful summary, exact planned/completed checkpoint agreement, and independent required gameplay anchors. Crash and timeout remain failures. | Real watchdog tests use a fake engine to submit missing, stale, incomplete, duplicate, reduced, contradictory, crashed, and timed-out evidence. |
| Runs could inherit capture/repair flags or share game saves. | Main runner clears inherited smoke flags and uses fresh `APPDATA` for every invocation. Specialist runners also use isolated save folders. Environment values are restored. | Watchdog integration tests retain an untouched original-save sentinel and check cleared flags. Main reports include the actual isolated save directory. |
| The full route replaced the ordinary suite and could force the ending. Large simulation updates skipped normal timing. | Full mode appends to the ordinary suite; production updates are split into 0.01–0.05 second steps. The route checks each charged departure/arrival, stop markers, a stop-25 disk reload, the natural ending trigger, and persisted final choice. | Full engine report records 49 departures and arrivals through stop 50. Route assistance is explicit. |
| Tactical smoke mostly rendered a battle and retreated. | Six controlled encounters test legal/blocked movement, ranged damage/ammunition/wear/turn costs, free rejection of invalid attacks, victory rewards and continuation, defeat health and return, and retreat encounter persistence. | Actual engine input callbacks and updates resolve the encounters. Fixtures establish reproducible geometry and accuracy; no post-attack outcome is forced. |
| First aid was covered by contracts rather than a complete interaction. | Three scenarios accept an actual request and test keyboard treatment, physical gestures and timed steps, wrong-input rejection, pause/resume, exact supply use, and exactly-once goodwill. | Actual request controls, mouse/touch callbacks, and production updates perform treatment. |
| Home loot checks did not prove transfer and reload behavior or systematically enforce item timing. | Engine scenario drags a chest item into the backpack, flushes to disk, reloads, and checks that it does not regenerate. Nine component tests cover budgets, unlocks, targeted repair parts, overflow, serialization, revisits, consumption, and isolation. | Thousands of seeded rolls and every weapon's matching repair part are checked, alongside a real engine save round trip. |
| Range smoke could directly complete a stage. | Scenario fires, checks ammunition and reload, advances ordinary updates until the timer reaches results, and checks rewards/closing. | Engine desktop/mobile scenarios exercise the production range lifecycle. |
| Zoom checks searched obsolete resource text and could compare two empty label collections; mobile pickup expected obsolete Escape behavior. Capture folders could retain old evidence. | Zoom requires specific current HUD controls in every tested scene at both zoom levels. Pickup follows the actual pause/Continue flow and checks item conservation. Zoom/pickup and requested Last Stand captures require fresh nonempty images and copy them to unique folders. | Focused collector tests reject missing HUD controls; specialist engine runs produce new images, including all 17 required Last Stand captures. |
| Regression mocks lagged behind current APIs; animation checks depended on ignored reference PNGs. | Update mocks to current callback contracts and compare decoded RGBA against 144 tracked canonical fingerprints. Baseline generation is explicit and reads reviewed reference art, never installed mismatches. | The initial check preserved all five character failures. The reviewed follow-up passes with ignored `output/` image reads prohibited and retains strict pixel mutation checks. |
| Separate tests were easy to omit; the regression group lacked a time limit. | `tools/run_validation.ps1` runs seven independent gates and aggregates their results without stopping after the first failure. The regression process now has a configurable watchdog and preserves output on timeout. | Separate process logs and reports identify each gate and its exit code; fake child processes check errors and timeouts. |

## Actual defects exposed

The stronger checks found and fixed five game defects:

- Early home water rolls could select a rare or high-food-value item because the supply path checked only one effect. All supply candidates now use complete progression eligibility.
- Movement touches passed through the viewport conversion twice, producing wrong coordinates when its transform was not the identity. The touch path now maps once; behavioral tests use a scaled and offset viewport.
- Closing weapon repair returned to a still-open workshop overlay. Close now dismisses the workshop; Back retains its return behavior. The repair UI tests check both.
- The mobile joystick intercepted touches in the request dialogue, including the first aid Accept button. Dialogue now blocks movement while the contextual Accept/Close action remains usable.
- Once a mobile drag began, movement returning within the initial drag threshold was discarded. Subsequent movement now continues to reach the pointer callback, including rag strokes returning to their starting position.

Test fixture changes preserve the current APIs and intended behavior. They do not waive asset differences, add dialogue, or modify sprite artwork.

## Coverage boundaries

| Layer | What a pass establishes | What it does not establish |
| --- | --- | --- |
| Python/Lua regression | Specific logic, persistence, input routing, content and pixel contracts; Lua uses a mocked LÖVE surface. Missing dependencies/skips fail the strict runner. | Correct integration of every subsystem in the real engine, graphics-driver behavior, perceived quality. |
| Desktop engine smoke | Startup and shared composition, real rendering calls, selected input flows, maintenance/repair, loot transfer, combat outcomes, first aid, range lifecycle, saves and recovery. | Every item, quest branch, encounter geometry, upgrade combination, or player strategy. Some earlier screen checks still seed state solely to render it. |
| Mobile engine smoke | Shared scenarios plus desktop-simulated joystick, action, menus, exit/return, range aiming and pinch input. | Android/iOS packaging, real multitouch timing, safe areas, keyboard lifecycle, background suspension, memory pressure, haptics or device frame rate. |
| Full route | Every stop transition, costs and visit markers, a mid-route disk resume, natural ending and finale persistence. | Survival balance: this segment provisions food/water/coal and suppresses random interruptions. |
| Last Stand | Focused defense, treatment, ammunition, input variants, resume, outcomes and resource release. | Every difficulty, inventory, death/retry timing, or real controller/device. |
| Zoom and mobile pickup | Required HUD controls at tested zooms, fresh captures, selected touch transfers and item conservation. | Readability, correct art, clipping, safe areas, every resolution, or all inventory operations. |
| Asset/audio contracts | Required files, loadability, specified dimensions/pixels and selected lifecycle behavior. | Audible mix, musical suitability, visual appeal, or correctness of unasserted image regions. |

Combat and first-aid fixtures seed controlled requests, encounters, health and inventory. They then drive production callbacks and verify resulting costs, rewards and state. Rendering fixtures directly select screens and are identified by `render_` checkpoints. Checkpoint totals mix these checks with contract audits; totals alone are not a measure of gameplay depth.

First-aid pause/resume currently happens within one engine process. A complete interrupted-treatment disk reload is still a useful additional scenario. The main runner's seed controls startup and ordinary scenarios; combat/first-aid and specialist harnesses also use fixed fixture seeds.

## Sprite reference failure and resolution

The initial audit found five characters differing from their original normalized reference pixels: Botanist Frog, Conductor Cat, Cook Frog, Cook Mouse, and Trail Fox. Across 50 sheets, 26,164 formerly opaque pixels had been cleared to transparent RGBA. The audit correctly kept the test failed while the cause was uncertain.

The October 5 follow-up established the cause: the later, declared magenta-fringe cleanup was missing from the reference contract. Applying the existing cleanup helper to the immutable canonical sources reproduces all 144 installed sheets exactly. All changes follow the connected background-color rule; surviving visible RGB values are unchanged. The 277 affected frames were reviewed over contrasting backgrounds. See the [cleanup review and independent provenance proof](audits/2026-10-05-canonical-sprite-cleanup.md).

The corrected contract retains each original source hash and records a separate, independently derived installed-output hash, removed count, and pinned cleanup policy. Production sprite files remain unchanged. The pixel comparison stays strict; unexpected source/policy changes and altered installed pixels remain failures. Independent review also tightened per-action cleanup validation for runs and bound every walk/idle/run mapping to its actual direction; mutation tests cover both gaps.

## Validation evidence

The initial desktop run passed 92 checkpoints. The initial strict regression run executed 411 methods and reported 8 failures and 29 errors, including stale mocks and the real animation differences.

After expansion, desktop passed 102 checkpoints, mobile passed 109, and the full route passed 105 at seed 810. An additional desktop run passed all 102 checkpoints with Scout Frog, seed 20261004, and 0.01-second updates.

The audit's strict regression group ran 472 test methods in 216.982 seconds, with five failing character subtests, no errors, and no skips. The failures are exactly the canonical animation differences described above.

| Audit gate before follow-up | Result | Evidence |
| --- | --- | --- |
| Regression | FAIL | 472 methods; five canonical character subtest failures; no errors/skips. |
| Desktop | PASS | 102 checkpoints, seed 1337, 0.05-second updates. |
| Mobile | PASS | 109 checkpoints, seed 1337, 0.05-second updates. |
| Full route | PASS | 105 checkpoints, seed 1337; all 49 legs, disk resume and natural finale. |
| Last Stand | PASS | 1,591 checks, 108 save operations, 15 kills, 180-second simulated defense; a separate capture run also verified 17 fresh images. |
| Zoom | PASS | 331 checks and 20 fresh captures; required HUD controls in every tested scene at both zoom settings. |
| Mobile pickup | PASS | 51 checks and three fresh captures. |

The initial combined run completed all seven gates: six passed and one failed. It returned exit code 1, preserving the regression failure while allowing the six independent engine gates to execute. Total gate time was about five minutes.

### Completed goal follow-up — October 5

The follow-up resolves the remaining sprite reference failures through the reviewed cleanup derivation above, adds 13 focused safeguard tests, and reruns the entire matrix with fresh isolated saves. The strict regression executes every method; there are no failures, errors or skips.

| Follow-up gate | Result | Evidence | Gate seconds |
| --- | --- | --- | ---: |
| Regression | PASS | 485 methods in 219.905 seconds; zero failures/errors/skips. | 220.27 |
| Desktop | PASS | 102 checkpoints, seed 1337, 0.05-second updates. | 19.90 |
| Mobile | PASS | 109 checkpoints, seed 1337, 0.05-second updates. | 20.99 |
| Full route | PASS | 105 checkpoints; all 49 legs, stop-25 disk resume, natural ending and finale persistence. | 26.30 |
| Last Stand | PASS | 1,591 checks, 108 save operations, 15 kills, 180-second simulated defense. | 6.33 |
| Zoom | PASS | 331 checks and 20 fresh nonempty captures. | 8.18 |
| Mobile pickup | PASS | 51 checks and three fresh nonempty captures. | 4.28 |

The aggregate reports `passed=7 failed=0 completed=7 planned=7` and returns exit code 0. Summed gate time is 306.25 seconds. A separate independent canonical check also passes with every ignored `output/` PNG read prohibited: all 144 original fingerprints and metadata are preserved, and all 144 derived/installed hashes and removal counts match the provenance proof.

Local diagnostic output is ignored by Git under `.stabilization/smoke-audit/`. The earlier aggregate is `final-validation/validation-summary.rpt`; the completed goal run is `goal-final-validation/validation-summary.rpt`, with a JSON equivalent and a separate log/report for every gate. The independent contract log is `canonical-v2-independent-verified.log`. The tracked cleanup evidence includes all 277 affected frames and enlarged deeper regions. Reproduce using:

```powershell
.\tools\run_validation.ps1 -Seed 1337
```

## Remaining work, in priority order

1. Add unassisted campaigns with a defined player policy, multiple seeds and difficulty bands. Assert scarcity, actual looting, food/water/coal use, encounter resolution, health, weapon availability, and sustainable repair/upgrade choices.
2. Add complete quest journeys for deliveries, passengers, branching conversations and expeditions, including cancellation, overflow rewards, repeated reloads, and interrupted completion. Existing logic tests cover parts of these paths; the default matrix does not drive every journey through UI.
3. Add longer sessions and measurements for memory/asset churn, frame times, repeated scene transitions, repeated saves, and pause/resume. Current bounded smokes are not soak or performance tests.
4. Include fresh packaged builds in release validation and run a real Android/iOS device acceptance matrix for screen sizes, touch, suspension, audio and memory pressure.
5. Add deliberate screenshot review or approved image-region assertions for important screens. Rendering and HUD presence can pass while art, clipping or readability is wrong.
6. Wire the matrix into CI with installed dependencies and LÖVE/display support. No tracked GitHub workflow currently runs it automatically. Review the expedition and convoy engine harnesses' run contracts and incorporate them into the aggregate gate; they are currently outside its seven groups.
