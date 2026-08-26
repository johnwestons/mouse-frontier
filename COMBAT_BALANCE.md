# Combat balance

Combat pacing is owned by `game/combat_balance.lua` so ordinary encounters, trail events, battle setup, rewards, desktop builds, and Android builds all use the same rules.

Board geometry, pathfinding, line of sight, obstacles, zoom coordinates, and obstacle generation are owned by `game/battle_grid.lua`. The battle controller and interface consume the same rules, preventing visual highlights from disagreeing with legal movement or attacks.

## Tactical board

- The battlefield contains 10 columns by 6 rows, for 60 traversable grid spaces before obstacles.
- Movement uses breadth-first pathfinding. Units cannot jump through allies, enemies, or blocked spaces.
- The mouse wheel scales the entire tactical layer around one origin: terrain, units, obstacles, projectiles, effects, health bars, and hit testing remain aligned.
- Each biome now has three six-tile atlases, providing 18 terrain appearances per biome and 72 across the four route biomes.

## Obstacles and cover

Every battle places five to seven deterministic obstacles according to difficulty. The generated obstacle atlas contains a dead tree, rusty car, ruined shack, boulders, barricade, and rail cart.

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

Base coal, scrap, and experience increase with the tier. Every additional enemy also adds tier-scaled coal, scrap, and experience, so a three-enemy encounter is always worth more than a single-enemy encounter. Defense battles retain their extra resource and experience bonus. Boss encounters at stops 15, 35, and 47 feature an alpha enemy with additional health, armor, aim, a dedicated objective/music category, and bonus rewards.

## Allies, AI, and statuses

- Every passenger and temporary settlement defender receives a route-scaled fallback weapon if they entered battle unarmed. Late-route allies use at least uncommon weapon rolls.
- Enemy movement searches every reachable space for a useful approach, goes around occupied or blocked squares, and repositions ranged enemies when an obstacle breaks line of sight.
- Ally abilities scale with route progress instead of remaining at rank one for the entire campaign.
- Boss, guard, regeneration, sleep, paralysis, and snare states are labeled directly on units.
- Every battle displays its objective in the tactical header and battle feed.

## Automated guarantee

The deterministic combat and grid audits verify all 50 tier assignments, boundary health and combat statistics, representative group-count rolls, boss and multi-enemy reward growth, 60-space geometry, obstacle counts, path detours, blocked line of sight, and zoom-aware hit testing. They run in both the desktop and mobile smoke suites.
