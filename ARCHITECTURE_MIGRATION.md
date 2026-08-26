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
| Legacy module adapters | String-key dependency resolvers using `setfenv` | Explicit context objects and direct module APIs | All production gameplay adapters complete |
| Application state | Session plus many application-local overlay fields | Coherent runtime state grouped by domain | Central session, gameplay, inventory, journey, screen, renderer, and HUD fields complete |
| Composition root | Combat, world-scene, audio, inventory-presentation, event, train-car, mobile-control, frame-presentation, startup, and persistence-lifecycle behavior split across `game/app.lua` | `game/app.lua` wires dedicated domain services | Battle, world-scene, audio, inventory-presentation, event, train-car, mobile-control, frame-presentation, startup, and persistence-lifecycle orchestration extracted; further domain extraction is incremental |

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

## Definition of done for this migration wave

- `main.lua` contains lifecycle forwarding only and stays below 40 lines.
- `game/app.lua` is the only application composition root.
- Shared values no longer originate in `main.lua`.
- Architecture and sprite-tool tests pass.
- The 42-check smoke run and full route to stop 50 pass.
- The generated mobile package contains `game/app.lua`, `game/config.lua`, `game/save_schema.lua`, and `game/systems.lua` from the same commit.
- All project source changes are committed; ignored generated output is not committed.

## Acceptance results

Verified on August 25, 2026:

- 12 Python architecture and Sprite Doctor tests passed.
- The normal autonomous smoke playthrough passed all 42 checkpoints, including legacy migration, invalid-save rejection, backup recovery, overlay-aware presentation coordinates, startup-runtime readiness, and forced focus-loss persistence.
- The full-route smoke playthrough reached the ending at stop 50.
- The shared `.love` package built successfully and passed all 46 mobile checkpoints.
- Package inspection confirmed the lifecycle shell, application module, configuration, save schema, system manifest, and mobile adapter are present in the same archive.
