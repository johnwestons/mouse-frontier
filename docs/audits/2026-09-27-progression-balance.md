# Main journey progression balance audit — September 27, 2026

## Scope and decision

This pass traces the 50-stop journey's loot, NPC requests, authored conversations, random events, encounters, combat rewards, and train upgrades. Stop 50 is the finale; the probability counts below use stops 1–49, where new outdoor task offers can appear.

The general curves are staged consistently, so they remain as they are. The one clear variety problem was supply cargo: a typical route offers about 2.64 supply tasks, but independent cargo rolls made repeated types common and several types easy to miss. The supply-task pace stays the same. Cargo types now rotate through weighted, no-repeat groups of six. The order still uses the existing early-to-late weights, each assignment is saved, and old saves seed the rotation from their latest saved cargo offer.

No authored dialogue was edited.

## What a route currently serves

Each ordinary stop resolves into either a random battle or one random event. Fifteen stops also carry a required story or mystery chapter, and three stops carry a forced boss battle.

| Journey segment | Ordinary stops | Random battle chance | Expected random battles | Expected random events | Required story / mystery | Forced bosses |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Stops 1–12 | 8 | 48% | 3.84 | 4.16 | 4 | 0 |
| Stops 13–30 | 12 | 58% | 6.96 | 5.04 | 5 | 1 |
| Stops 31–49 | 11 | 64% | 7.04 | 3.96 | 6 | 2 |
| **Stops 1–49** | **31** | — | **17.84** | **13.16** | **15** | **3** |

Random-event category weights change by phase. The latest category is excluded from the next random-event roll, so these are the base weights before that repeat guard.

| Category | Stops 1–12 | Stops 13–30 | Stops 31–50 |
| --- | ---: | ---: | ---: |
| Battle event | 15% | 20% | 20% |
| Help | 25% | 23% | 20% |
| Fortune | 30% | 22% | 18% |
| Mishap | 15% | 20% | 22% |
| Defense | 15% | 15% | 20% |

NPC requests average about 15 prompts over a full route when the player talks to the outdoor resident at every eligible stop. Expected counts are about 2.9 mail deliveries, 2.2 rides, 2.6 supply deliveries, 3.7 trades, 1.7 item requests, and 1.9 first-aid offers. This includes the existing Crow Merchant trade exception. The rates already move from more mail and rides early toward more trade and item requests later.

The 13 authored conversation trees are assigned once each, with a random gap of 2–4 stops. Regular chatter uses a shuffled cycle per NPC, so every supplied line appears once before a new cycle and the boundary avoids repeating the previous line.

## Item and battle progression

The generic loot rarity roll moves smoothly from stop 1 to stop 49. Specific event, quest, or shop rewards can impose a minimum rarity, so these percentages describe only the underlying roll.

| Rarity | Stop 1 | Stop 25 | Stop 49 |
| --- | ---: | ---: | ---: |
| Common | 78.0% | 56.9% | 35.9% |
| Uncommon | 20.0% | 29.8% | 39.6% |
| Rare | 1.8% | 12.6% | 23.4% |
| Legendary | 0.2% | 0.7% | 1.2% |

Weapon loot spans 83 weapons across nine increasing damage tiers. Ammunition types unlock at stops 1, 13, 19, 25, 31, 37, and 43. Opening a house supplies food, water, and 2–4 additional rolled items; the first door also has an uncommon-weapon milestone every five stops. House loot is generated once and stored, including overflow, so these are opportunities rather than forced pickups.

Enemy HP and combat groups also rise by phase:

| Phase | Enemy HP range | Enemy armor / aim by phase end | Group chance |
| --- | ---: | ---: | --- |
| Easy, stops 1–12 | 10–12 | 1 / 1 | 12–20% for two enemies |
| Medium, stops 13–30 | 16–24 | 3 / 3 | 30–50% for two enemies |
| Hard, stops 31–50 | 26–34 | 5 / 4 | 50–70% for groups; 18–35% for three enemies |

Winning every ordinary and forced train battle yields about 398 XP on average before optional event fights, quests, conversations, or expeditions. That is level 8 under the current 1,210 XP level-12 cap. This estimates encounter rewards, not battle success or a player's chosen route; side content can raise it further.

Base travel costs across the 49 legs total 145 food, 175 water, and 175 coal before passenger load, traits, maintenance, and upgrades. Engine upgrades unlock at stops 5, 14, 26, and 38 and can reduce those per-leg costs by up to 28% for food/water and 45% for coal. Train cars unlock from stops 4–28; greenhouse and medical cars add steady arrival support.

## Supply-cargo tuning result

The comparison uses 200,000 simulated routes, one outdoor talk per eligible stop, the current 1-in-45 Crow Merchant exception, and the existing location weights. The rotation changes variety only; the expected number of supply prompts remains 2.64.

| Cargo | Seen at least once before | Seen at least once with rotation |
| --- | ---: | ---: |
| Food | 47.7% | 54.4% |
| Water | 39.1% | 47.0% |
| Medicine | 38.1% | 46.3% |
| Repair materials | 32.5% | 41.4% |
| Ammunition | 28.6% | 38.0% |
| Keepsake recovery | 25.9% | 35.0% |
| **Average distinct cargo types per route** | **2.12** | **2.62** |
| **All six cargo types in one route** | **0.15%** | **4.76%** |

The full six-type set remains uncommon because most routes have fewer than six supply tasks. When six supply tasks do occur, the rotation shows all six types once. The saved rotation also avoids repeating the last visible cargo when it rolls into a new group.

## Verification

- The quest, loot, event, combat, player-level, train-upgrade, travel-cost, merchant, expedition, caravan, first-aid, and help-session balance audits all report ready.
- Focused Lua behavior tests pass for weighted first offers, six-type rotation, cycle boundaries, old-save seeding, schema validation, and the talk-to-NPC flow.
- The full automated suite passed: 288 tests, no failures or skips.
