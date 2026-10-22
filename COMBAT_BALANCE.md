# Combat balance

Combat pacing is owned by `game/combat_balance.lua` so ordinary encounters, trail events, battle setup, rewards, desktop builds, and Android builds all use the same rules.

Shared movement and sight rules live in `game/battle_grid.lua`; canonical procedural geometry lives in `game/battle_field.lua`. The controller and interface consume the same rules. Crossing and exploration rules live in `game/battle_operation.lua` and `game/battle_fog.lua`.

## Tactical board

- New battlefields contain 72 columns by 40 rows: 2,880 spaces, four times the reviewed 720-space preview. At least 2,400 reachable spaces are guaranteed. Existing flat 60-space and native 720-space checkpoints retain their saved dimensions.
- Weighted pathfinding accounts for uphill costs and steep slopes. Units cannot jump through occupied or blocked cells. Distant threats permit an eight-space march budget; nearby enemies restore the unit’s tactical movement budget.
- Every surviving participating player must reach the eastern exit. Ordinary kills alone do not finish the crossing. Boss and defense threats must also be defeated. Fallen players and NPC followers cannot block extraction.
- Native fields use continuous textured terrain and solid scenery with local orbit, tilt, zoom, pan, and terrain ray picking. HUD controls remain fixed. Legacy flat boards retain their sprite renderer and biome tile atlases.
- Party sight has an eight-space radius and respects terrain and cover. Exploration persists; enemies outside current sight cannot be inspected or targeted. Draw distance is separately adjustable in device Graphics settings.

## Obstacles and cover

New fields normally place 224, 256, or 288 deterministic obstacles by difficulty. Reserved routes and a connectivity fallback protect traversal. Saved flat battles retain their five-to-seven-obstacle layouts. The scenery kit contains dead trees, rusty cars, ruins, boulders, barricades, and rail carts.

All six block movement. Trees, cars, shacks, and boulders block ranged line of sight completely. Barricades and rail carts can be fired across, but add cover to the defender. Existing terrain cover still contributes to defense.

## Journey tiers

| Stops | Tier | Enemy HP | Armor | Aim | Movement |
| --- | --- | ---: | ---: | ---: | ---: |
| 1-12 | Easy | 10-12 | 1 | 0-1 | 2 |
| 13-30 | Medium | 16-24 | 2-3 | 2-3 | 2 |
| 31-50 | Hard | 26-34 | 4-5 | 3-4 | 3 |

The previous ordinary-encounter rules made stop 9 and all 41 later stops hard, while event battles used separate tier boundaries. Enemy health also jumped directly between flat 12, 20, and 32 HP profiles. The shared curve keeps clear difficulty bands while smoothing growth inside each band.

## Encounter size

- Easy encounters gradually increase from a 12% to 20% chance of two enemies.
- Medium encounters increase from a 30% to 50% chance of two enemies.
- Hard encounters increase from a 50% to 70% group chance. The chance of three enemies rises from 18% to 35%.

## Rewards

Base coal, scrap, and experience increase with tier. Defeated enemies contribute to ordinary crossing rewards; bypassed surviving enemies do not add a kill bonus. Defense battles retain their extra resource and experience bonus. Boss encounters at stops 15, 35, and 47 feature an alpha enemy with additional health, armor, aim, an explicit objective/music category, and bonus rewards. Expedition rewards retain their per-enemy receipts. Results wait for host dismissal and cannot be paid again by retry or reload.

## Allies, AI, and statuses

- Every passenger and temporary settlement defender receives a route-scaled fallback weapon if they entered battle unarmed. Late-route allies use at least uncommon weapon rolls.
- Enemy movement searches every reachable space for a useful approach, goes around occupied or blocked squares, and repositions ranged enemies when an obstacle breaks line of sight.
- Ally abilities scale with route progress instead of remaining at rank one for the entire campaign.
- Both battle renderers show boss, guard, regeneration, sleep, paralysis, and snare states. The native view also offers unit inspection, personal ammo/equipment information, scrollable battle history, and authored projectile sprites, subject to current party sight. See [implementation evidence](docs/BATTLE_ENVIRONMENT_IMPLEMENTATION.md) for tested layouts and device limits.
- Every battle displays its objective in the tactical header and battle feed.

## Automated guarantee

The combat audit verifies tier assignments, boundary statistics, group rolls, boss and reward growth. The legacy grid audit retains its 60-space regression cases. Dedicated native tests cover 100 large-field seeds, three routes, reachable area, weighted movement, hill sight blocking, camera picking, exploration persistence, local graphics settings, hidden-target rejection, extraction, and compact co-op replication. Desktop and forced-mobile smoke exercise real input flows; physical Android acceptance remains outstanding when no device is connected.
