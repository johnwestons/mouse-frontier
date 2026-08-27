# Mouse Frontier Architecture Migration

**Started:** August 25, 2026
**Reference project:** The Picture Shop
**Status:** Active, with the application-boundary migration complete

## Objective

Move Mouse Frontier from a large entry script with implicit cross-module wiring to a thin lifecycle shell, explicit composition modules, centralized configuration and save-schema ownership, and enforced desktop/mobile parity. Picture Shop is a structural reference only; its game-specific systems are not copied.

## Non-negotiable constraints

- Windows and Android continue to ship from the same `main.lua`, `conf.lua`, `game/*.lua`, assets, saves, and tests.
- Existing save slots remain compatible. Schema changes are sequential and use the version owned by `game/save_schema.lua`.
- Existing uncommitted mobile work is part of the migration baseline and must not be discarded.
- Every structural stage must pass the normal smoke playthrough before the next stage is accepted.
- Generated mobile output remains disposable; source code never moves into a second mobile gameplay tree.

## Migration map

| Area | Previous structure | Target structure | Status |
| --- | --- | --- | --- |
| LÖVE entry point | Gameplay composition and callbacks in `main.lua` | Thin callbacks delegating to `game/app.lua` | Complete |
| Application systems | Dense inline require table | Named composition manifest in `game/systems.lua` | Complete |
| Runtime configuration | Window, canvas, timing, layout, and palette literals split across entry files | Shared `game/config.lua` | Complete |
| Save version | Entry-point constant passed through implicit resolvers | Owned by `game/save_schema.lua`, with sequential legacy upgrades and strict validation | Complete |
| Mobile inheritance | Mobile adapter wired directly in the former monolithic entry point | Adapter owned by `game/app.lua`; package stages the shared tree | Complete |
| Structural regression protection | Smoke tests only | Fast source-architecture tests plus smoke tests | Complete |
| Smoke harness | `setfenv` plus a name-resolved application scope | Validated explicit runtime and service context | Complete |
| Legacy module adapters | String-key dependency resolvers using `setfenv` | Explicit context objects and direct module APIs | All production gameplay adapters complete |
| Application state | Session plus many application-local overlay fields | Coherent runtime state grouped by domain | Central session, gameplay, inventory, journey, screen, renderer, and HUD fields complete |
| Composition root | Combat, world/session state, audio, inventory-presentation, event, train-car, mobile-control, frame-presentation, startup, persistence-lifecycle, screen-flow, content ownership, view construction, and input binding split across `game/app.lua` | One validated graph builder owns ordered service construction; `game/app.lua` only forwards lifecycle events | Complete |

## Execution sequence

1. Capture a clean smoke baseline and inventory all existing desktop/mobile changes.
2. Extract the application lifecycle without changing callback behavior.
3. Centralize configuration, save-schema ownership, and system composition.
4. Add architecture tests that fail if `main.lua` grows back into a gameplay module or the mobile packager stops staging shared Lua.
5. Run Python tests, the normal smoke playthrough, the full-route smoke playthrough, and a mobile package smoke run.
6. Commit the complete source baseline so desktop and Android upgrades can be mirrored through normal Git history.
7. Convert remaining implicit resolver-based modules to explicit contexts one domain at a time, starting with session bootstrap and input, with a smoke pass after every conversion.

## Current modernization sequence

1. `game/runtime_state.lua` now owns authoritative access to screen, selected slot, save data, player, and scene while preserving `GameSession` save behavior and `ScreenManager` transitions.
2. Session bootstrap now uses a validated explicit context and writes central fields through runtime state.
3. Gameplay input now uses a validated explicit context; it no longer receives string-resolved dependencies or writes application locals indirectly.
4. Input-owned overlay, transition, interaction, and battle fields now live in runtime state. Remaining renderer and HUD adapters move in focused changes rather than one high-risk rewrite.
5. Save loading and writing now pass through a non-mutating version 1-to-25 migration boundary. Future, cyclic, and structurally corrupt payloads are rejected; legacy slots are rewritten with their original file retained as a backup; corrupt primaries recover without destroying the known-good backup.
6. Gameplay update now uses a validated explicit context. Its clocks, travel offsets, held-action state, and world-interaction proximity flags are owned by runtime state instead of application locals exposed through hidden reads and writes.
7. Inventory actions now use a validated explicit context and mutate inventory, chest, gift, dialogue, pickup, and battle-item state directly through runtime ownership.
8. Journey rules now use a validated explicit context. Travel costs, passenger contributions, quests, stop entry, encounters, and event routing mutate authoritative runtime/session state directly, including runtime ownership of the active random event.
9. Screen UI now uses a validated explicit context. Menu, slot, character, map, dialogue, event, workshop, editor, and ending screens read/write runtime state directly; mobile and renderer ordering is handled through declared callbacks rather than a global resolver.
10. World rendering now uses a validated explicit context. Landscape, train, character, NPC, passenger, stop, house, item, wildlife, and sludge drawing read current session state through runtime ownership, with declared getters only for startup animations and save-restored sludge collections that can be replaced at runtime.
11. Gameplay HUD now uses a validated explicit context. World composition, travel and car transitions, resources, mobile and desktop menus, interaction prompts, inventory overlays, audio controls, radio, trade, upgrades, and maintenance read current application state through declared runtime and service boundaries. This completes the production resolver-adapter migration.
12. Battle orchestration now lives behind a validated runtime facade. Encounter startup, controller context, battle commands, tactical UI context, mouse-result transitions, and per-frame battle updates share one service; inventory and input consume focused battle operations instead of rebuilding controller access in the composition root.
13. World-scene orchestration now lives behind a validated service. Stop and house layout, NPC restoration, dropped-item location rules, sludge state/combat, chicken flocks, and mice share one owner; save bootstrap resets service-owned encounter state while update, rendering, journey, input, and smoke paths consume focused operations.
14. Audio orchestration now lives behind a validated runtime service. Audio initialization and shutdown, scene-aware music categories, sound effects, weapon sound mapping, train departure playback, radio resets, track controls, mute/pause state, and HUD status share one owner; input and HUD no longer access the raw audio engine.
15. Inventory presentation now lives behind a validated presenter service. Mutable click timing, UI context construction, desktop/mobile slot presentation, battle restrictions, item drawing, and click/release routing share one owner; application and gameplay input no longer build or consume the raw inventory UI context.
16. Trail-event orchestration now lives behind a validated runtime service. Required and random event presentation, choice affordability, pointer hit routing, consequence resolution, battle handoff, stop entry, and result dialogue share one owner; journey, screen, input, and smoke paths consume focused event operations instead of the raw event model.
17. Train-car orchestration now lives behind a validated runtime service. Active-car imagery, floor and object bounds, player clamping, inter-car transition startup/completion, train re-entry, and edited-item placement share one owner; session bootstrap, update, and input consume focused train-car operations, with an automated two-car transition checkpoint.
18. Mobile-control orchestration now lives behind a validated runtime service. Controller creation, action labels, overlay visibility, movement/held/sprint queries, pointer translation, pinch zoom, synthetic-mouse filtering, touch forwarding, drawing, Android back-key translation, and focus cancellation share one owner; gameplay systems consume focused mobile capabilities instead of the raw controller.
19. Frame-presentation orchestration now lives behind a validated runtime service. Viewport scaling, camera-aware coordinate conversion, pan and zoom controls, screen dispatch, exit prompts, mobile overlays, and travel fades share one owner; rendering and hit testing now use one overlay-aware camera predicate, while input and mobile systems consume focused presentation capabilities instead of raw camera and viewport objects.
20. Startup orchestration now lives behind a validated runtime service. Graphics defaults, save-directory creation, audio and mobile initialization, asset hydration, settlement metadata, lazy streaming, character animations, cloud state, and load-ordered gameplay-update construction share one owner; renderers consume stable getters and the application load/update callbacks only delegate.
21. Persistence and application lifecycle orchestration now live behind a validated runtime service. Runtime synchronization, save revision tracking, debounced scheduling, per-frame persistence updates, slot reads/removals, focus-loss flushing, maintenance cleanup, and audio shutdown share one owner; gameplay, screen, input, smoke, focus, and quit paths consume focused persistence operations instead of the raw save engine.
22. Smoke-playthrough instrumentation now uses a validated explicit context. Test fixtures mutate authoritative runtime fields directly, service operations are declared at installation, mobile controls are resolved only after startup, and the final `setfenv`/name-resolver bridge has been removed without weakening save, journey, battle, presentation, or mobile coverage.
23. Screen lifecycle routing now lives behind a validated flow service. Intro, slots, character selection, battle, event, ending, and gameplay update/draw handlers are installed together exactly once; late-bound battle, ending, and HUD callbacks preserve composition order while removing placeholder and split registration from the application root.
24. Content and asset ownership now lives behind a validated registry. Image collections, scenery and UI stores, animation bundles, startup hydration targets, streaming retention groups, and furniture-art lookup are assembled once and shared by reference across desktop and mobile consumers.
25. View-layer construction now lives behind a validated composition module. Screen UI, inventory presentation, world rendering, and gameplay HUD are built in one declared order; late-bound renderer callbacks preserve cyclic screen dependencies while the application root only publishes the four finished services.
26. Adventure-service construction now lives behind a validated composition module. Battle orchestration, inventory actions, journey rules, and trail events are built as one explicit cyclic graph; internal operations use direct service references while only later startup and view services remain declared late-bound callbacks.
27. Platform-service construction now lives behind a validated composition module. Persistence, audio, train-car geometry, frame presentation, and mobile controls are built as one explicit graph; focus/shutdown and presentation/mobile cycles are internal direct closures while later screen UI and gameplay input remain declared late-bound callbacks.
28. Gameplay input construction now lives behind a validated command composition. Keyboard, pointer, inventory, battle, journey, train, camera, audio, and exit-prompt bindings consume the published platform, adventure, and view graphs; the former broad `Systems` dependency inside gameplay input is replaced by four focused capabilities.
29. World and session construction now live behind a validated composition module. World-scene ownership is established first, then session bootstrap consumes its encounter reset operation and platform-owned train bounds; only the later inventory weapon predicate remains an explicit callback.
30. Startup-runtime construction now lives behind a validated composition module. Asset hydration and the gameplay-update context consume the published content, platform, adventure, and world/session graphs; the application root publishes the finished idempotent startup runtime instead of assembling per-frame capabilities inline.
31. View composition now consumes explicit factories and published platform, adventure, world/session, and startup graphs. Its final broad `Systems` lookup and service helper are removed while local late-bound renderer callbacks continue to resolve the intentional screen/render cycle.
32. Module factories and runtime services now have separate ownership. `game.systems` remains an immutable module manifest, while a publish-once service registry holds 18 constructed instances and verifies that no runtime service replaces or aliases its factory.
33. Smoke instrumentation now has a dedicated composition boundary. The application root supplies four grouped inputs while `game.smoke_composition` validates them and owns the detailed playthrough context, keeping test-only service mapping out of production assembly.
34. The complete runtime graph now has one validated owner. `game.application_composition` constructs authoritative state and all ordered domain graphs, verifies seven compositions and 18 published services, and exposes a lifecycle interface consumed by the 27-line `game.app` adapter.
35. Travel progression now uses a deterministic milestone curve. The 49-leg baseline drops from 325/425/295 to 145/175/175 food/water/coal, individual baseline costs remain within storage limits, and desktop/mobile controls show exact affordability and shortage feedback.
36. Combat progression now uses one deterministic curve across ordinary and event battles. Stops are divided into 12 easy, 18 medium, and 20 hard encounters; enemy statistics grow within each band, group sizes ramp gradually, and rewards scale with enemy count.
37. Trail events now use phase-aware pacing and guaranteed choice safety. Early stops favor fortune and help, mob interruptions rise from 48% to 64% across the route, immediate event-family repeats are prevented, and all 40 events expose an always-actionable path.
38. Train upgrades now use one progression and purchase policy. Six cars unlock across the route with consistent resource capacities and fully wired effects, engine tiers have milestone unlocks, Navigator/Storage are no longer cosmetic, and every resource gain observes the owned train's capacity.
39. Loot and equipment now use one progression and economy policy. All 65 playable weapons span nine verified damage tiers, rarity improves across the route, shop and resale values reflect quality and condition, ammunition never unlocks after its weapon, and broken equipment requires a workshop repair.
40. Quests and passengers now use one route-aware progression policy. Offer pacing changes across the trail, longer deliveries pay more scrap and XP, matching train cars improve passenger jobs, active objectives appear on the map, and full-backpack rewards route safely to the train mailbox.
41. Player advancement now uses one capped, save-compatible progression policy. Twelve levels provide visible health, aim, armor, and movement gains; all 12 character abilities scale through four ranks; and the HUD, combat runtime, desktop smoke run, and mobile package consume the same authoritative rules.
42. Stop help and morality now use one goodwill-only progression policy. Ordinary NPC requests are limited to one opportunity per stop and fall to a 36–40% combined rate; persistent item requests and a keyboard/touch first-aid activity award nonnegative goodwill; the HUD and ending expose the saved score; and all supplied ambient dialogue lines are in rotation.
43. Audio playback now uses a validated catalog and lifecycle-aware runtime. Duplicate music copies and non-runtime mobile audio are excluded deterministically, playlists shuffle without immediate repeats, focus loss suspends active audio, invalid stations normalize safely, and slingshots and eagle attacks no longer route through firearm sounds.
44. Delivery quests now use one atomic cargo policy shared by desktop and Android. Food and water consume eligible backpack items before train storage, legacy free-cargo flags no longer bypass payment, and medicine, repair, ammunition, and recovery jobs provide distinct requirements, rewards, objective labels, and goodwill.
45. The stop-50 finale now uses one positive-only progression policy. Ten family clues, mystery clues, goodwill, completed help and passenger rides, train condition, acquired cars, and player level shape three legacy tiers; a saved three-way final decision changes the campaign outcome on desktop and Android.
46. Sprite-driven stop activities now use one composed minigame coordinator. Sludge containment and track-debris clearing retain separate rules, rendering, persistence audits, and atlases while world, HUD, input, and Android translation depend only on the shared activity interface; `main.lua` remains a lifecycle shell.
46. Tactical battles now use one 60-space grid authority. Breadth-first movement, obstacle collision, line of sight, cover, enemy pathing, zoom rendering/hit testing, route-scaled ally equipment and abilities, boss objectives, 24 new biome tiles, and six generated obstacle sprites share the same desktop/Android rules.
47. Presentation now uses one scoped camera authority. World scenes, battles, menus, events, the ending, maintenance, first aid, dialogue, and overlays share bounded zoom/pan transforms and inverse pointer mapping; each surface remembers its view while fixed Android controls stay outside the camera, and touch pinch/two-finger pan use the same service as desktop input.
48. Train presentation and upkeep now use shared authorities. The locomotive and every active car fit canonical desktop/Android coordinates, a seven-car touch navigator uses those same coordinates, and maintenance centrally owns route/length wear, engine reductions, oil capacity, service cost/restoration, coal penalties, condition-speed effects, and HUD/workshop forecasts.

## Definition of done for this migration wave

- `main.lua` contains lifecycle forwarding only and stays below 40 lines.
- `game/application_composition.lua` is the only runtime graph builder; `game/app.lua` is a thin lifecycle adapter.
- Shared values no longer originate in `main.lua`.
- Architecture and sprite-tool tests pass.
- The 71-check smoke run and full route to stop 50 pass.
- The generated mobile package contains `game/app.lua`, `game/config.lua`, `game/save_schema.lua`, and `game/systems.lua` from the same commit.
- All project source changes are committed; ignored generated output is not committed.

## Acceptance results

Verified on August 26, 2026:

- 15 Python architecture, audio-system, mobile-package, and Sprite Doctor tests passed.
- The normal autonomous smoke playthrough passed all 71 checkpoints, including legacy migration through save version 27, invalid-save rejection, backup recovery, scoped camera isolation/restoration, zoomed overlay pointer alignment, responsive seven-car presentation, centralized maintenance balance, startup-runtime readiness, the 60-space tactical grid, obstacle pathing, line of sight, unified zoom hit testing, boss rewards, combat/player progression, event, train-upgrade, loot/equipment, all six delivery types, atomic cargo and legacy compatibility, stop help, first aid, goodwill, positive finale tiers, the saved final decision, and audio priority/lifecycle behavior, shared content-registry hydration, explicit view dependencies, immutable factory/service separation, grouped smoke composition, complete application-graph composition, forced focus-loss persistence, and complete screen-flow installation.
- The full-route smoke playthrough reached the ending at stop 50.
- The shared `.love` package built successfully and passed all 75 mobile checkpoints.
- Package inspection confirmed the lifecycle shell, application module, configuration, save schema, system manifest, and mobile adapter are present in the same archive.
