# Crow Caravan Campsites — Concept Plan

Status: initial gameplay implementation complete  
Working feature name: **The Rookery Caravan**

## 1. Core concept

On a small number of journey stops, the player can discover a visiting caravan of crow merchants. The caravan occupies a separate, compact campsite reached from the stop through an obvious entrance point.

The campsite is a calm trading interlude rather than another settlement or wilderness challenge:

- no enemies, sludge, hazards, or combat;
- one small hand-authored campsite shared by all appearances;
- three crow merchants with different specialties;
- unusually broad, progression-aware stock;
- persistent stock and trade budgets for that appearance;
- a clear **Return to Stop** control at all times.

The caravan should feel exciting because it is rare and useful, not because it is random enough to be missed for an entire journey.

## 2. Place in the journey

The Rookery Caravan is the same travelling group whenever it appears. Its merchants remember that they have met the player, allowing greetings and trade dialogue to evolve across the journey without requiring a large quest system.

It complements normal merchants rather than replacing them:

| Normal stop merchant | Crow caravan |
|---|---|
| Common and locally useful stock | Broad, curated and sometimes exceptional stock |
| Usually four sale listings | Twelve listings split across three traders |
| Part of the stop scene | Optional safe campsite entered from the stop |
| Familiar supply stop | Rare discovery and preparation opportunity |

## 3. Relationship to Wilderness Expeditions

Wilderness Expeditions now provide the implemented **off-stop area** foundation. The caravan campsite reuses a smaller, safer form of that foundation:

- a manifest describing an area;
- a painted background and walk mask;
- placed actors and interaction markers;
- an entrance that remembers the player's exact return position;
- an obvious exit;
- persistent, roll-once contents.

The campsite deliberately avoids the harder wilderness requirements: no scrolling map, streaming, combat, enemies, loot nodes, hazards, or extraction rules. This keeps the caravan focused as a short, safe trading interlude while sharing the established area-transition model.

## 4. Design pillars

1. **Rare but dependable** — every new journey gets a few caravan opportunities, distributed across the route.
2. **Immediately safe** — entering the campsite never exposes the player to combat or environmental damage.
3. **Worth investigating** — the caravan offers breadth, at least one affordable purchase, and a chance at gear not commonly seen at ordinary stops.
4. **No progression bypass** — stock respects weapon tiers, ammunition unlocks, and backpack progression.
5. **A recurring cast** — the same crows recognize repeat visits and become a small piece of journey continuity.
6. **Fast on mobile** — entering, moving, trading, and leaving require clear, large controls and no precision tapping.

## 5. Appearance schedule

### Recommended rule

Create exactly **three hidden caravan appearances per new 50-stop journey**:

- one between stops **7–16**;
- one between stops **22–32**;
- one between stops **38–48**;
- keep appearances at least eight stops apart.

The player is not shown these locations in advance. This preserves surprise while preventing a journey from receiving no caravans because of unlucky random rolls.

### Ineligible host stops

Do not place a caravan at:

- the tutorial or opening stop;
- story-critical, boss, or finale stops;
- a stop hosting the shooting-range activity;
- a stop selected for a future Wilderness Expedition entrance;
- any map that lacks a safe, authored entrance position.

The schedule is rolled once when a journey is created and then saved. For an older save upgraded after this feature ships, only eligible future stops should be selected; the system must never rewrite already visited stops.

### Optional tuning after playtesting

If three visits feels too common, retain the three scheduled candidates but give the final candidate a lower reveal chance. The first test build should use three guaranteed appearances so balance can be judged without testers missing the feature.

## 6. Discovery and entry

An eligible stop gains a small caravan arrival vignette near a safe edge of the map: a feathered signpost, wagon tracks, or a perched crow banner. It must not overlap the train, building doors, shooting range, pumps, or stop hazards.

Approaching it presents:

- desktop prompt: **VISIT CROW CARAVAN**;
- mobile action label: **CARAVAN**.

Entry should feel like walking into another nearby space, not opening a shop overlay. The stop position and facing direction are saved so **Return to Stop** places the player exactly where they entered.

Candidate host stops should be curated and given authored gate coordinates. Automatically clamping a gate to a map edge is not reliable enough for existing stop layouts.

## 7. Campsite layout

Use one reusable **960 × 720** isometric campsite with no camera scrolling.

Suggested layout:

- **bottom:** arrival path and return marker;
- **center:** warm fire, rugs, stools, crates, and a small social space;
- **left:** Trail Provisioner's food and supply stall;
- **right:** Ironbeak Arms' weapon rack and worktable;
- **upper area:** Curio Keeper's decorated wagon and display table;
- **rear edge:** two caravan wagons, tether posts, banners, and stacked cargo.

The player should be able to see all three merchants and the exit immediately after entering. Wide paths and generous interaction radii are more important than packing the scene with props.

Existing campfire, tent, barrel, crate, and crow-merchant art can establish the first version. New art should focus on a caravan wagon, crow banner/sign, stall dressings, and a distinct entrance marker.

## 8. Safety contract

The campsite is explicitly marked as a safe area:

- no combat encounters can spawn;
- no sludge or environmental hazard logic runs;
- merchant actors cannot be targeted or damaged;
- the attack/fire control is hidden or disabled;
- opening a trade or inventory panel pauses campsite movement;
- the return route can never be locked by dialogue, purchases, or inventory state;
- autosave occurs on entry, completed transactions, and exit.

Any future event that would violate this contract should be a different area type, not a surprise attack inside the merchant campsite.

## 9. The three merchants

Each merchant presents four listings, for twelve total listings per caravan appearance.

### 9.1 Trail Provisioner

The practical merchant. Its stock should solve immediate journey problems.

Typical four-slot mix:

1. food or water;
2. medicine;
3. oil or another useful journey resource;
4. ammunition appropriate to a weapon the player owns or can currently use.

Every caravan appearance must include at least one practical item costing **6 scrap or less**, so an early discovery is still meaningful.

### 9.2 Ironbeak Arms

The equipment merchant. Its stock gives the player a broader weapon choice without invalidating progression.

Typical four-slot mix:

1. one melee weapon;
2. one ranged weapon;
3. one weapon the player does not own, biased toward the current progression tier;
4. a second weapon or a matching ammunition bundle.

Rules:

- prefer unowned weapon families;
- do not sell locked ammunition types;
- early and middle appearances may offer at most one tier above normal local stock;
- the late appearance may rarely reach two tiers above local stock;
- weapon repair is not part of version one because it would overlap the train workshop's role.

### 9.3 Curio Keeper

The exciting merchant. Its stock contains uncommon consumables and the appearance's headline item.

Typical four-slot mix:

1. a next-battle potion;
2. an action vial or similarly scarce consumable;
3. a backpack upgrade better than the player's current pack;
4. a featured rare item.

The late caravan's featured slot may have a **20% legendary chance**. A permanent-heart item may appear no more than once per save.

## 10. Stock generation and persistence

Stock is generated once for each scheduled appearance and then saved. Leaving and returning cannot reroll it.

Generation rules:

- no duplicate listings within one camp;
- never offer a backpack equal to or worse than the equipped one;
- favor ammunition for owned ranged weapons;
- favor weapon families the player has not tried;
- respect all progression and unlock gates;
- guarantee at least one rare-or-better featured item somewhere across the journey's three camps;
- sold-out listings remain sold out;
- purchases, resale stock, and merchant budgets persist for that appearance.

The caravan should use existing item prices and relationship discounts. A hidden markup would make the rare discovery feel punitive.

## 11. Buying, selling, and delivery

All three merchants accept normal scrap. There is no caravan-only currency.

The caravan has one shared resale budget for the entire campsite:

`15 + floor(current stop × 2) + existing relationship budget bonus`

Sharing a budget prevents the player from multiplying resale cash by visiting three adjacent merchant panels. Each crow can still have an individual portrait, name, dialogue, and stock list.

Purchased items behave as follows:

- ammunition goes directly to the appropriate reserve;
- normal items go to the player's inventory when space exists;
- if the inventory is full, offer **Send to Train** instead of cancelling the purchase;
- if neither immediate inventory nor train delivery is valid, clearly explain why before taking scrap.

The trade panel should support paging or scrolling through all player sale items. The current small visible sale list should not strand items below the fold.

## 12. Relationships and dialogue

Use one persistent group identity, **crow-caravan**, for goodwill and trade terms. Keep separate stable merchant IDs so each trader can have distinct dialogue.

Suggested recurring progression:

- **first meeting:** guarded welcome and explanation of the caravan;
- **second meeting:** recognition, comments on the player's route, warmer sales lines;
- **third meeting:** familiar greeting and a sense that the caravan has been following another road alongside the player.

Completed trades can influence greetings and existing relationship terms, but version one should not add a loyalty meter or a second reputation economy.

Ambient personality can come from short merchant calls, crows hopping between wagons, fire sounds, hanging charms, and occasional references to goods gathered beyond the current route.

## 13. Optional caravan-exclusive curios

These are good expansion rewards after the core campsite and trade flow are stable:

- **Crow Cache Map — 12 scrap:** the next Wilderness Expedition contains an uncommon-or-better cache. Only enable after expeditions exist.
- **Brass Warranty Tag — 10 scrap:** the next weapon that would break instead remains at 25 durability, then consumes the tag.
- **Black Feather Charm — 16 scrap:** the next ordinary item reward gains one rarity step, capped at rare, then consumes the charm.

Exclusive effects should live in a dedicated caravan-special catalog so they cannot leak into ordinary merchant pools. None is required for the first playable version.

## 14. Navigation and controls

### Desktop

- interact at the stop gate to enter;
- interact with a merchant to trade;
- interact at the arrival path or use the persistent **Return to Stop** control to leave.

### Mobile

- large context labels: **CARAVAN**, **TRADE**, and **RETURN**;
- merchant interaction radii generous enough that exact character overlap is unnecessary;
- persistent **Return to Stop** button placed away from movement and other primary action controls;
- no combat button in the safe campsite;
- returning to the stop restores the stop controls, including the separately planned **Return to Train** button.

Returning to the train should normally remain a two-step path—camp to stop, then stop to train—so the player cannot accidentally skip the stop. A direct **Return to Train** option may also live in the pause/journey menu as a convenience if playtesting shows the extra transition feels slow.

## 15. Saved state

Recommended conceptual save structure:

```lua
crowCaravans = {
  schedule = { 12, 27, 43 },
  groupRelationshipId = "crow-caravan",
  camps = {
    ["caravan-stop-12"] = {
      discovered = true,
      visited = true,
      stockByMerchant = { ... },
      resaleBudget = 39,
      purchaseHistory = { ... },
    },
  },
  meetings = 1,
  trades = 3,
  permanentHeartSold = false,
}
```

The active off-stop area also needs:

- stable area ID;
- source stop ID;
- exact return position and facing;
- area-tagged dropped items;
- player position inside the area if saving there is allowed.

The save-schema migration must be additive and deterministic. Existing saves receive defaults plus future-only scheduled appearances.

## 16. Recommended system boundaries

The implementation should avoid building a caravan-only scene loop. Recommended responsibilities:

- **area runtime:** entering, leaving, walk masks, actor lists, interaction markers, safe-area behavior, return positions;
- **crow caravan system:** schedule, stock generation, campsite state, merchant dialogue state;
- **generic merchant trade:** source-agnostic buying, selling, budgets, delivery, and paged inventory lists;
- **interaction router:** new caravan gate, area exit, and caravan merchant interaction kinds;
- **save schema:** caravan state and support for off-stop scenes.

The area runtime must support multiple actors with stable IDs. A single special NPC slot will not scale to three merchants or later wilderness characters.

## 17. First playable slice

The smallest complete version includes:

- one reusable campsite map and walk mask;
- deterministic scheduling of three appearances;
- one authored gate on each eligible host map;
- three named crow merchants using existing crow animation assets;
- four persistent listings per merchant;
- normal buying and selling with one shared budget;
- relationship-aware greetings;
- full-inventory delivery to the train;
- reliable return to the exact stop position;
- desktop and mobile controls;
- saving, loading, and migration tests.

Defer from the first slice:

- combat or ambushes;
- theft, haggling, or merchant hostility;
- caravan-specific currency;
- recruitment or a caravan questline;
- multiple campsite visual themes;
- animated caravan arrival/departure;
- weapon repair;
- exclusive curio effects that depend on Wilderness Expeditions.

## 18. Suggested implementation order

1. Build the generic off-stop safe-area transition and exact return behavior.
2. Create the campsite map, walk mask, entrance, exit, and three actor positions.
3. Extract trade logic so any merchant source can provide stock and a budget.
4. Add caravan scheduling, eligibility rules, and persisted camp records.
5. Add merchant stock generation and progression safeguards.
6. Add mobile controls, persistent return control, and full-inventory delivery.
7. Add relationships, dialogue variations, ambience, and visual polish.
8. Run save migration, economy, layout, and return-path tests.

## 19. Acceptance criteria

The concept is successfully implemented when:

- every new journey schedules three valid, well-spaced caravan appearances;
- no excluded or physically unsuitable stop receives one;
- the entrance is clear but does not reveal future appearances on the route map;
- the campsite is always safe and all three merchants are immediately readable;
- each appearance has twelve valid, non-duplicated listings;
- early players can afford at least one useful listing;
- stock cannot be rerolled by leaving, loading, or reopening trade;
- progression-locked items and ammunition never appear early;
- buying, selling, shared budgets, discounts, and train delivery behave consistently;
- the player can always return to the exact stop position;
- mobile players can move, choose a merchant, trade, and leave without precision taps;
- saving inside or around the campsite cannot lose purchases, dropped items, position, or caravan state;
- ordinary stop merchants retain their current role and economy.

## 20. Recommended defaults for approval

- Working name: **The Rookery Caravan**
- Frequency: **three hidden appearances per journey**
- Area: **one 960 × 720 safe campsite**
- Cast: **three recurring crow merchants**
- Inventory: **four listings each, twelve total**
- Currency: **normal scrap**
- Pricing: **existing prices and relationship terms, no markup**
- Exit: **persistent Return to Stop, restoring the exact entry position**
- Architecture: **first consumer of a reusable off-stop area framework**
- Version-one scope: **trading and atmosphere only; no combat, quests, or bespoke currency**
