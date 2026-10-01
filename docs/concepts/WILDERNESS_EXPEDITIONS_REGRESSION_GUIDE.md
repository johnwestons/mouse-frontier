# Expedition regression checks

Run the expedition checks before adding another stop, changing painted paths, or updating the combat return flow. The behavioral suites execute the actual Lua modules. They require Lupa's Lua 5.1 runtime; if it is installed outside the active Python environment, set `LUA_RUNTIME_PYTHONPATH` to that package directory. Missing Lua support is reported as skipped tests and must not be counted as a successful gameplay validation.

Run the deterministic, full-application playthrough smoke on desktop and mobile layouts:

```powershell
.\tools\expedition-playthrough-smoke\run.ps1 -Mode both
```

The smoke walks through Stop 5's Badlands route and the harder Stop 6 forest route using the actual path resolver and movement code. It checks the timed flood and ridge detour, cairn completion, both optional basin caches, regular mob fights, map objectives, storage controls, Stop 6 gate progression, boss health carry into tactical combat, vault access, both stop returns, and the defeat return. Tactical outcomes are accelerated through the normal battle completion and Continue paths; use the behavioral combat and persistence suites for detailed turn rules. It touches no player save slots: the run uses an unslotted journey under `mouse-frontier-expedition-playthrough-qa`, and writes reports under `.stabilization/expedition-playthrough-smoke/`.

`-Mode both` checks the desktop and touch layouts and sends touch events for the visible map close and battle Continue controls. Movement is driven deterministically through the keyboard path in both layouts. `tools/tests/lua/test_expedition_input.lua` separately covers the expedition touch controls and input dispatch.

```text
python -m unittest discover -s tools/tests -p "test_expedition*.py" -v
```

## What the suites protect

| Suite | Gameplay contract |
| --- | --- |
| `test_expedition_geometry_behavior.py` | Bridge decks remain walkable, water and masonry remain blocked, long movement steps cannot jump between separated paths, every exit/cache/mob/patrol is connected, both bandits gate the boss, the boss gates the vault, and geometry revisions preserve health and looted storage. |
| `test_expedition_persistence_behavior.py` | Exact fractional battle-return positions; loss saved on the train before Continue; actual save serialization and reload of turn/HP/status/consumed supplies; one-time potion/reward handling; resumed actions use the restored battle; switching slots resets transient state; completed result screens do not autosave repeatedly. |
| `test_expedition_combat_behavior.py` | Field attack timing, hit-triggered battle entry, attack/weapon rules, health carry, boss behavior, and consistent reward claims. |
| `test_expedition_asset_lifecycle.py` | Cached expedition sprites remain valid across area/battle/save transitions while ordinary streamed sprites can still be released. |
| `test_expedition_framework.py` | Production asset dimensions and expected integration points. These source/asset checks supplement the behavioral suites. |

The geometry suite follows each navigation waypoint with the actual movement resolver. A waypoint that crosses blocked ground, a loop, an unreachable destination, or a collision disagreement is a failure. Exact-return fixtures first assert that the chosen fractional point is walkable; a changed map must update the fixture deliberately without weakening the coordinate comparison.

## Short in-game acceptance route

1. At Stop 5, enter Red Mesa Approach, open the supply cache, and follow the trail into Redwash Basin.
2. Wait for the basin's flood warning. Confirm the low wash closes and the ridge stays reachable; if caught in the wash, confirm the player is carried to a safe bank. Mark all three cairns, fight the regular Badlands mobs, open both optional caches, then return to Stop 5.
3. At Stop 6, enter Riverwood Outskirts, cross the eastern bridge, open its cache, and enter the waystation. Check that painted water and ruins stop movement at normal and sprint speed.
4. Fight near an obstacle. Dodge an enemy wind-up, land field hits, then allow a strike to begin tactical combat. Confirm each enemy's damaged health carries over.
5. Suspend/restart during a tactical turn after using ammunition or a healing item. Confirm the same turn and enemy HP return, the supply is still consumed, and a pre-battle potion is not applied twice.
6. Defeat the two dungeon bandits, enter the newly opened boss chamber, defeat the boss, loot the vault, and return through both areas. Repeat with a loss, closing the game on the result screen before Continue; reload must place the player inside the train.
7. Revisit a battle and change save slots. Check that sprites remain visible and valid, enemies do not inherit another slot's pending attack, and key interactions work on mobile and while zoomed or panned. Open Settings during a nearby enemy's approach and verify that both player and enemies pause together.

Automated logic tests do not replace the visual route. Painted collision alignment, sprite anchors/transparency, touch targeting, camera placement, and readable combat tells still require an in-engine check.

## Isolated full-application preview

Run `tools/expedition-integration-preview/run.ps1 -Mode both` with LÖVE installed. The harness uses a separate QA identity and fresh unslotted journey, without reading or writing user save slots. It captures 14 stages in each layout, including map closing, modal pause, caches, gate progression, boss challenge with 37/58 HP carry, exact victory return, vault access and defeat return inside the visible train floor. Combat outcomes are accelerated through the real completion/Continue paths. Reports and screenshots are saved in `docs/concepts/expedition-validation/`; pass `-OutputDirectory` to send a review run elsewhere.

`tools/tests/lua/test_expedition_input.lua` additionally exercises actual input, update, touch controls, HUD dispatch, train floor arrival, and exploration/battle music categories. The sprite verification harness checks normalization, alpha preservation, depth ordering, distance-based movement, stopped idle, attack-ring reach and resource release. See `docs/concepts/expedition-sprite-audit/`.
