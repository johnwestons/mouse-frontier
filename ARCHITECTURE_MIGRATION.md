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
| Save version | Entry-point constant passed through implicit resolvers | Owned by `game/save_schema.lua` | Complete |
| Mobile inheritance | Mobile adapter wired directly in the former monolithic entry point | Adapter owned by `game/app.lua`; package stages the shared tree | Complete |
| Structural regression protection | Smoke tests only | Fast source-architecture tests plus smoke tests | Complete |
| Legacy module adapters | String-key dependency resolvers using `setfenv` | Explicit context objects and direct module APIs | Planned incrementally |
| Application state | Session plus many application-local overlay fields | Coherent runtime state grouped by domain | Planned incrementally |

## Execution sequence

1. Capture a clean smoke baseline and inventory all existing desktop/mobile changes.
2. Extract the application lifecycle without changing callback behavior.
3. Centralize configuration, save-schema ownership, and system composition.
4. Add architecture tests that fail if `main.lua` grows back into a gameplay module or the mobile packager stops staging shared Lua.
5. Run Python tests, the normal smoke playthrough, the full-route smoke playthrough, and a mobile package smoke run.
6. Commit the complete source baseline so desktop and Android upgrades can be mirrored through normal Git history.
7. Convert remaining implicit resolver-based modules to explicit contexts one domain at a time, starting with session bootstrap and input, with a smoke pass after every conversion.

## Definition of done for this migration wave

- `main.lua` contains lifecycle forwarding only and stays below 40 lines.
- `game/app.lua` is the only application composition root.
- Shared values no longer originate in `main.lua`.
- Architecture and sprite-tool tests pass.
- The 33-check smoke run and full route to stop 50 pass.
- The generated mobile package contains `game/app.lua`, `game/config.lua`, `game/save_schema.lua`, and `game/systems.lua` from the same commit.
- All project source changes are committed; ignored generated output is not committed.

## Acceptance results

Verified on August 25, 2026:

- 12 Python architecture and Sprite Doctor tests passed.
- The normal autonomous smoke playthrough passed all 33 checkpoints.
- The full-route smoke playthrough reached the ending at stop 50.
- The shared `.love` package built successfully and passed all 37 mobile checkpoints.
- Package inspection confirmed the lifecycle shell, application module, configuration, save schema, system manifest, and mobile adapter are present in the same archive.
