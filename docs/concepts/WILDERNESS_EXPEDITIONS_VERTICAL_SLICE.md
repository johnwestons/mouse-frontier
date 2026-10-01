# Wilderness Expeditions: Stop 6 Vertical Slice

## Reviewed pilot — September 2026 correction pass

Stop 6 now owns the first data-driven expedition: **Riverwood Outskirts**, leading to **Buried Waystation**. It is deliberately small enough to tune, but it uses the final reusable boundaries for area data, roaming enemies, interactions, combat handoff, persistent loot, and save migration.

Stop 5 now adds the first earlier-stop expedition: the **Red Mesa Approach** opens into **Redwash Basin**, a broad outdoor route through split ridges and a flood-carved wash. The low crossing periodically floods; players can wait on high ground or take the longer ridge path. A player caught in the wash is carried to the nearest safe bank. They survey three cairns, find optional caches, and deal with regular Badlands creatures along the way. This gives Stop 5 a traversal and route-reading loop instead of reusing Stop 6's guardian gate and vault.

### Play route

1. At Stop 5, enter **Red Mesa Approach**, fight or pass the dust beetle and cactus rat, search the supply cache, and follow the trail into **Redwash Basin**.
2. Explore the wash and the elevated ridge. The UI warns before each flash flood; the low crossing closes briefly while the ridge remains passable. Anyone caught in the wash is carried to a safe bank.
3. Mark the north, wash, and arch cairns to survey the basin route. Two optional supply caches and three roaming regular mobs reward exploration.
4. Return to Red Mesa when ready. At Stop 6, follow the familiar Riverwood Outskirts route into the Buried Waystation.
5. Defeat both sludge-taken bandits to open the boss chamber. Weaken **The Buried Host** in real time or challenge it nearby; field damage carries into tactical combat.
6. Defeat the Host to open the corruption vault, then return through both areas.

### Controls and combat contract

- Movement, sprint, inventory, zoom, and interaction use the existing game controls.
- The on-screen **Attack** control and `F` quick-attack key use an equipped usable melee weapon. Touch always retains **ATTACK**, with a separate **OPEN / ENTER / RETURN / CHALLENGE** control when relevant.
- Aim selects targets in the swing direction or near the clicked point. Quick attack follows the last movement direction. Walls, water and closed gates block attacks, awareness and battle recruitment.
- Weapon reach, cooldown, condition, wear and proficiency apply in the field. Broken weapons cannot attack. Ordinary hits cannot cancel a committed enemy windup; blunt stagger is limited.
- The red warning ring matches the actual hit radius. Settings and other modal menus pause both sides; repeated attack input during cooldown never opens dialogue.
- Enemies patrol, alert nearby pack members, chase, visibly wind up, and only start a battle when that strike connects. Mere overlap does nothing.
- Real-time damage is stored immediately on the stable expedition mob record.
- The tactical battle receives each participating mob's exact current and maximum health.
- Victory copies tactical health/death back to the expedition and returns the player to the exact `(x, y)` where the battle started, with 1.5 seconds of enemy grace. Attacking ends that grace.
- Loss or retreat returns the player inside the train and clears the active expedition.
- An active battle checkpoint saves the turn, board, health, statuses and used supplies. Result destinations are saved before Continue; closing the game on a defeat screen cannot bypass the train return.
- Field and tactical kills claim the same once-only per-enemy XP, coal and scrap. Authored chests provide item treasure. Defeat/retreat preserve survivor damage and already earned casualty rewards.
- **AREA MAP** shows paths, exits, caches, sealed routes, threats and the player. Opened caches and completion have persistent feedback.

The expedition HUD keeps only the area name, player health and a clearly labeled defeated-enemy count in a small corner card. Train supplies, campaign progression and ammunition summaries stay off the playfield. Desktop actions share one top row; the area map hides the HUD and row while open, then shows the current objective above the route artwork. Opening expedition storage hides the toolbar and keeps a close control in the clear strip above the inventory panels. Touch movement, attack and context controls remain available around the screen edges.

## Content manifest

| Area | ID | Size | Content |
| --- | --- | ---: | --- |
| Red Mesa Approach | `stop05-badlands-approach` | 1672 x 941 | Stop 5 trailhead, supply cache, Redwash Basin entrance, dust beetle and cactus rat |
| Redwash Basin | `stop05-redwash-basin` | 1672 x 941 | Open wash and ridge routes, timed flash floods, three survey cairns, two optional caches, three regular Badlands mobs |
| Riverwood Outskirts | `stop06-outskirts` | 1672 x 941 | Town return, ruin cache, dungeon entrance, two corrupted bandits |
| Buried Waystation | `stop06-buried-waystation` | 1672 x 941 | Surface return, side cache, two gate bandits, boss arena, locked vault |

Persistent state lives under `saveData.expeditions[areaId]`. Each mob has a stable ID, position, health, death state, and reward receipt. Each chest has a stable ID and persistent storage contents; cairn survey progress is saved per marker. Redwash Basin completion derives from all three cairns being recorded. Its flood phase advances while the area is active and pauses with the world. Stop 6 content version 2 moves old mob origins onto corrected paths without restoring health or refilling emptied chests. Stop 5's approach has its own version 2 layout, and the replacement basin uses a new area ID so old mine progress cannot mark it complete. Transient AI resets when switching saves.

## Art and animation contract

All four maps are 1672 x 941 backgrounds with matching black-and-white walk masks. Gameplay characters, mobs, health feedback, the moving flood water, and interaction beacons are rendered separately. Wilderness maps can reuse a normal enemy sprite for field encounters; a dedicated action atlas adds richer field animation when one is authored.

The pilot corrupted mobs use 1536 x 1024 action atlases arranged as a 3 x 2 grid of 512-pixel cells:

| Cell | Action |
| ---: | --- |
| 1 | idle |
| 2 | locomotion |
| 3 | attack |
| 4 | hit reaction |
| 5 | defeat |
| 6 | alert / alternate locomotion |

`game/expedition_sprites.lua` normalizes action and walking frames onto a 512 × 512 canvas with the same ground anchor `(256,492)`. Connected matte cleanup retains intentional light details. The selected bandit v5 and boss v4 walk sources provide eight separate phases in a 4 × 2 sheet; actual resolved movement distance drives animation. World drawing interleaves the player and enemies by foot depth. Explicit native-facing metadata keeps the left-facing boss oriented correctly.

These remain single-view pilot sprites with horizontal facing, not eight distinct camera directions. The motion reports retain that limit explicitly. Original art and rejected intermediate sheets are preserved.

## Adding the next expedition

1. Add a new surface or wilderness definition to `game/expedition_areas.lua` with an ID, stop, dimensions, background, spawns, clearings/corridors, interactions, and mobs. Use dungeon gates and bosses only where they fit the area's intended play loop.
2. Give every mob, chest, and interaction a stable unique ID.
3. Add clean background art at the declared dimensions.
4. Reuse a regular mob sprite for field encounters, or register a dedicated action atlas in `game/expedition_runtime.lua` for richer field animation.
5. Trace footpaths against the art, including narrow bridge decks and gated floors. Keep exits, mob origins and every patrol target reachable. Visibility-graph waypoints route mobs around corners using the same collision data.
6. Add behavioral geometry and progression tests, including closed/open gates, every route, migration and once-only rewards. Increment the area's content version when changing authored geometry.
7. Play-test the path at normal and sprint speed, with camera zoom at minimum and maximum, then verify save/reload across connected areas.

No new scene-specific combat or inventory UI should be added for future areas. New expeditions should be content manifests and art unless they introduce a genuinely new shared mechanic.

## Pilot tuning values

- Player melee reach: weapon-specific, normally 100–180 world units
- Player melee cooldown: weapon-family-specific, normally 0.34–0.50 seconds
- Standard awareness: 185 world units
- Standard strike reach: 82 world units
- Standard alert tell: 0.34 seconds
- Standard wind-up: 0.46 seconds
- Boss awareness / reach / wind-up: 225 / 112 / 0.62
- Pack participation distance: 330 world units
- Lose-interest distance: 390 world units

Mobs follow a cached visibility graph built from authored path endpoints and floor centers. Movement uses collision substeps and axis sliding, so a long frame cannot jump across water. Initialization is cached per save; movement checks no longer reinitialize every area. Dynamic expedition sprites are explicitly owned by their runtime so the generic asset streamer cannot release them between battles.

## Validation

- All Lua sources parse successfully.
- The expedition content audit verifies all four maps, stable IDs, art sizes, walkable spawns, walkable mob origins, walkable interaction origins, and gate progression.
- Behavioral tests cover combat, aiming, weapon condition, gates, routes, interruption/reload, exact return, modal pause, touch controls, migration and resource ownership. See [regression guide](WILDERNESS_EXPEDITIONS_REGRESSION_GUIDE.md).
- The isolated playthrough smoke visits Stop 5 and Stop 6. It verifies the flood warning, closed low wash, open ridge detour, cairn survey, optional caches, regular field fights, and Stop 6 gate/boss/vault flow. It uses a separate QA identity and no user save slots; see `tools/expedition-playthrough-smoke/run.ps1`. The visual integration preview continues to capture the Stop 6 pilot at `tools/expedition-integration-preview/run.ps1`.
