# Combat balance

Combat pacing is owned by `game/combat_balance.lua` so ordinary encounters, trail events, battle setup, rewards, desktop builds, and Android builds all use the same rules.

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

Base coal, scrap, and experience increase with the tier. Every additional enemy also adds tier-scaled coal, scrap, and experience, so a three-enemy encounter is always worth more than a single-enemy encounter. Defense battles retain their extra resource and experience bonus.

## Automated guarantee

The deterministic combat audit verifies all 50 tier assignments, boundary health and combat statistics, representative group-count rolls, and multi-enemy reward growth. It runs in both the desktop and mobile smoke suites.
