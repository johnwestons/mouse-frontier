# Loot and Equipment Balance

Mouse Frontier uses `game/loot_progression.lua` as the shared desktop and Android authority for loot rarity, weapon progression, shop value, ammunition availability, condition, repair, and resale.

## Route progression

The 50-stop route is divided into nine equipment tiers, advancing every six stops. The catalog contains 83 playable weapons across all nine tiers. Automated validation requires every tier to be populated and each tier's average base damage to exceed the previous tier.

| Route point | Common | Uncommon | Rare | Legendary |
| --- | ---: | ---: | ---: | ---: |
| Stop 1 | 78.0% | 20.0% | 1.8% | 0.2% |
| Stop 50 | 35.0% | 40.0% | 23.8% | 1.2% |

Rare rolls can reach weapons above the current route tier, while common rolls stay near it. Trade stock always includes supplies, ordinary loot, improved loot, and at least an uncommon weapon roll.

Standard item rarity unlocks by route tier: common and uncommon items are available from tier 1, rare items from tier 3, and legendary items from tier 6. Item-specific unlocks can delay an item further. Ammunition uses its own unlock tier; food, water, and healing items are also limited by their effect size. Weapon rolls retain their separate tier-based progression and can still reach above the current route tier on rare rolls.

## Home containers

Each newly visited home receives four ordinary finds: one food item, one water item, one route-eligible general item, and one household curiosity. Only the first home at a stop receives one crafting material. A weapon appears in that first home only at a route-tier transition (stops 7, 13, 19, 25, 31, 37, 43, and 49). The first home has a 30% repair-part chance only when the player owns a critically damaged weapon and lacks its matching part. Repair finds never target an unowned weapon.

This caps random finds in normal homes at four items and the first home at five, with the occasional weapon or needed repair part as a bonus. New saves also seed one introductory item in the first home at each of stops 1–5: a coal bucket, pickaxe, potted sprout, flower pot, and potted flowers respectively. Those scripted items are additional to the random-find budget. Homes already marked as looted keep their contents. Older saves missing the one-time sewing-cache marker still receive the existing cache migration; the new schedule applies to unvisited homes and new saves.

Food and water supply rolls apply the complete item eligibility check, including rarity, individual unlocks, and all food/water/healing effects. A water item with a large food effect cannot enter an early home merely because its water effect is small. The regression suite checks seeded home budgets, unlock boundaries, targeted repair finds, persistence, and container overflow; the engine smoke additionally transfers actual chest loot into the backpack and reloads it from disk.

## Purchase and resale value

- Melee weapon price: `4 + tier × 3` scrap.
- Ranged weapon price: melee price plus 2 scrap.
- Item prices: common 3, uncommon 6, rare 11, and legendary 18 scrap.
- Ammunition pickups add 2 scrap to their rarity value.
- Backpack price is twice its slot capacity.
- Base resale value is 45% of purchase value, rounded down with a minimum of 1 scrap.
- Weapon resale is further reduced by condition, from full value when sound toward 35% of that value when broken.

## Durability and repair

An equipped non-scratch weapon loses exactly one durability point on every valid attack attempt, including a miss. Running out of range or ammunition does not cause wear. Proficiency also advances on attempted player attacks rather than only on hits.

| Durability | Condition | Damage multiplier |
| --- | --- | ---: |
| 75–100 | Sound | 100% |
| 50–74 | Used | 90% |
| 25–49 | Worn | 78% |
| 1–24 | Critical | 65% |
| 0 | Broken | Cannot attack |

The train workshop repairs the most damaged equipped weapon to 100%. Repair cost is the missing durability divided into 20-point blocks, rounded up, plus half the weapon tier rounded up. Scratch never wears and never needs repair.

## Ammunition safety

Every ranged weapon's ammunition type must exist as a pickup, and each ammunition type must unlock no later than the first weapon that needs it. The deterministic loot audit rejects missing ammo unlocks and checks that high-rarity gear, advanced ammo, and large supplies stay within their route unlocks.
