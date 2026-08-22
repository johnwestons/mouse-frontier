# Mouse Frontier Code-Structure Freeze

**Declared:** August 22, 2026  
**Baseline tag:** `code-freeze-2026-08-22`

The game's current architecture is now frozen. The major extraction and module-migration phase is complete, and `main.lua` is limited to application lifecycle wiring and coordination between the extracted game systems.

## Allowed during the freeze

- Bug and crash fixes
- Performance, compatibility, and accessibility fixes
- Gameplay balancing and tuning
- Content, dialogue, quests, encounters, and assets
- Sprite Doctor repairs and asset-pipeline improvements
- UI polish that uses the existing screen and overlay structure
- Save migrations required by an approved gameplay change
- Tests, diagnostics, documentation, and release tooling
- Small local refactors necessary to make an approved fix safe

## Frozen without explicit approval

- New architectural layers or broad framework changes
- Moving major responsibilities between existing modules
- Recombining extracted systems into `main.lua`
- Large public-interface rewrites across several modules
- Replacing the screen/state, session, input, rendering, inventory, journey, or update-loop architecture
- Unrelated cleanup bundled into a feature or bug-fix change

## Change discipline

1. Keep each change narrowly scoped and commit it separately.
2. Preserve save compatibility or add a sequential migration.
3. Run the relevant focused tests for every change.
4. Run the normal smoke playthrough for gameplay or UI changes.
5. Run the full-route smoke playthrough before a release candidate and after changes to travel, encounters, progression, saves, or the ending.
6. Reopen architecture only through an explicit decision that records the reason, affected systems, migration plan, and verification plan.

## Exit criteria

This freeze remains active through final content integration, stabilization, and release polishing. It may be lifted only when a documented structural blocker cannot be addressed safely within the frozen design.
