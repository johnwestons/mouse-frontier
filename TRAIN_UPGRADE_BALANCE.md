# Train upgrade progression

Train-car effects, resource capacities, unlocks, and workshop purchases are owned by `game/train_upgrade_balance.lua`. The same policy is used by travel, battles, events, passengers, inventory refueling, workshop UI, desktop builds, and Android builds.

## Train cars

| Unlock stop | Car | Cost | Journey effect |
| ---: | --- | ---: | --- |
| 4 | Coal Hauler | 20 scrap | Raises coal capacity from 20 to 30 |
| 8 | Storage Car | 22 scrap | Raises food and water capacity from 20 to 30 |
| 12 | Greenhouse | 28 scrap | Produces 2 food after every journey |
| 16 | Sleeper Car | 24 scrap | Halves passenger food and water load, rounded up |
| 22 | Medical Car | 30 scrap | Restores 3 health after every journey |
| 28 | Navigator Car | 34 scrap | Reveals upcoming terrain and saves 1 coal on mountain and ruin legs |

Resource gains from battles, events, quests, passengers, greenhouse production, and manual refueling now respect the same capacities. The HUD displays current and maximum storage instead of assuming every resource caps at 20.

Existing saves that already exceed a newly calculated capacity keep those reserves until they are spent; future gains pause rather than deleting saved resources.

## Engine progression

Engine tiers retain their 15, 28, 45, and 70 scrap prices and now unlock at stops 5, 14, 26, and 38. Existing owned engines and cars remain valid; unlock rules only govern future purchases.

Workshop buttons show the required stop while locked, the scrap price when available, and owned or maximum status after purchase. Purchase validation lives in the balance policy rather than the pointer handler.

## Automated guarantee

The deterministic upgrade audit verifies all six effects, the 20-to-30 capacity expansions, passenger-load reduction, arrival production and healing, Navigator savings, total car and engine costs, first unlocks, and purchase accounting. It runs in both desktop and mobile smoke suites.
