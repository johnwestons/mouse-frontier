# Mouse Frontier Code-Structure Freeze (Lifted)

**Declared:** August 22, 2026  
**Lifted:** August 25, 2026
**Baseline tag:** `code-freeze-2026-08-22`

This file preserves the historical stabilization policy. The freeze was lifted after a cross-project audit found that substantial application composition and mutable coordination still lived in `main.lua`, while the derived Picture Shop project had established a cleaner lifecycle boundary and stronger structural tests.

Active architecture work is governed by [ARCHITECTURE_MIGRATION.md](ARCHITECTURE_MIGRATION.md). Save compatibility, focused verification, and shared Windows/Android source remain mandatory during the migration.

## Previously allowed during the freeze

- Bug and crash fixes
- Performance, compatibility, and accessibility fixes
- Gameplay balancing and tuning
- Content, dialogue, quests, encounters, and assets
- Sprite Doctor repairs and asset-pipeline improvements
- UI polish that uses the existing screen and overlay structure
- Save migrations required by an approved gameplay change
- Tests, diagnostics, documentation, and release tooling
- Small local refactors necessary to make an approved fix safe

## Previously frozen without explicit approval

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

## Exit decision

The documented blocker was the oversized application entry point and its implicit dependency bridge. The migration was approved on August 25, 2026 with a passing pre-change smoke baseline, staged verification, and a requirement that Android continue to derive from the same Lua source tree.
