# Weapon repair workbench design

This design builds on the [real-world visual research](real-world-maintenance-research.md) and [pixel-style concept](weapon-repair-minigame-concept-v2.png). The [sprite workbench preview](workbench-sprite-preview.png) shows the current renderer, with the sewing minigame as the user's requested visual reference. The repair UI is an abstract game interaction; it does not depict literal firearm instructions.

## Player flow

1. Open **TRAIN WORKSHOP**, then choose **WEAPON WORKBENCH**.
2. Select any owned weapon from the equipped slots or backpack.
3. Read its condition, scrap cost, and any critical part requirement.
4. Start the timing check. Tap or press Space/Enter when the moving marker reaches the target band.
5. A successful check consumes the listed scrap and, for a major repair, the required part. A miss spends nothing and allows another attempt.

The screen presents the selected weapon and its dedicated component on a large green work mat. An open ledger lists owned weapons; a parchment clipboard shows condition, exact part requirements and scrap cost.

## Repair rules and initial tuning

- Durability remains on the current 0–100 scale. The existing combat penalties and broken-at-zero behavior remain the condition model.
- **Field service:** condition 26–99. Costs scrap and uses no critical part.
- **Major repair:** condition 0–25. Requires one compatible, world-found critical part plus scrap. At zero, the weapon stays unusable until this repair succeeds.
- **Cost:** keep the current base formula: `ceil((100 - condition) / 20) + ceil(tier / 2)`. Major repair adds `6 + 2 × tier`. Example: a tier-7 weapon at 23 condition costs 28 scrap.
- **Timing result:** a perfect hit restores 100 condition. A good hit restores to at least 75, at most 95, and never lowers current condition. A miss consumes no scrap or part.
- **Parts:** critical parts are uncraftable and appear as item pickups in house caches. They use ordinary backpack slots and can be placed in existing storage. When a player has a critically damaged weapon but lacks its part, cache loot is biased toward that missing compatible part.

The thresholds preserve ordinary scrap-only upkeep while making severe damage a reason to search. The good-hit floor means a successful major repair always makes a zero-condition weapon usable again.

## One component per weapon

Every one of the 83 player weapons has exactly one unique component. Its item ID, sprite and fit are specific to that weapon. The three creature/unarmed attacks are excluded. The complete visual catalog is [weapon repair parts](part-sprite-catalog.html), with source specifications in [firearm parts](firearm-part-specs.json) and [hand-weapon parts](hand-weapon-part-specs.json).

Examples include the Sawed-Off Shotgun's Stacked Barrel Set, Heavy Frontier Pistol's Heavy Cylinder (its approved art is a Redhawk revolver), Frontier 5.56 Carbine's Bolt Carrier Group and Frontier Katana's Blade Collar. Two weapons may use the same general kind of component but never the same inventory item.

The workbench displays the component name and backpack count. All 83 components can appear in chest salvage. An owned critically damaged weapon biases successful component rolls toward its missing exact part.

## Minigame readability and controls

- Keep the timing rail large enough for mouse, touch, keyboard focus, and controller confirmation.
- Mark a broad green **GOOD** area and a smaller brass **PERFECT** center. Color is paired with text so color alone never communicates the result.
- Show the active weapon, current condition, required part, current scrap, and final cost before the player begins.
- While a timing run is active, selecting another weapon or closing the workbench cancels it without consuming resources.
- Keep all guidance as neutral interface text; no character dialogue is required.

## Style and scope

Use the game’s full 960×720 logical canvas and the sewing bench's authored art language: a worn timber desktop, parchment ledger and clipboard, green woven work mat, brass fittings and wooden buttons. Preserve the existing weapon and part sprites, Courier Prime type, green success state and red critical state. Keep real manuals as silhouette and grouping references; don’t turn the interface into a photoreal workshop or an instructional exploded diagram.

This design uses the existing backpack and save format for found parts, so the repair feature does not need a save migration.

## Implemented feature scope

The playable workbench is reached through **TRAIN WORKSHOP → WEAPON WORKBENCH**. It lists every owned player weapon from equipment and backpack, shows its durability and repair class, and previews the existing weapon sprite. Five tall parchment cards appear at a time. The list supports mouse-wheel scrolling, mouse or touch dragging, Page Up/Page Down, and previous/next controls. Dragging scrolls without selecting a weapon or interrupting its active timing check.

### Authored GUI sprites

`assets/sprites/ui/repair/workbench-surface-v1.png` is the repair-specific tabletop. `workbench-controls-v1.png` supplies authored condition tracks/fills, timing rail, target zones and pointer. Both were created with the built-in image generation tool; their complete prompts and source records are in `assets/sprites/ui/repair/generation-prompts.json`. Paper, cards and button states reuse the sewing minigame's existing `bench-controls-v1.png`.

`game/repair_workbench_art.lua` loads the PNGs, selects authored source regions, and crops the painted condition fill to current durability. It measures weapon/part alpha bounds as display metadata so the existing artwork fills the mat without changing its pixels. Atlas coordinates adapt to mobile package resizing. `game/repair_workbench_layout.lua` supplies the shared drawing/input geometry. Repair panels, cards and gauges no longer use procedural rectangle artwork.

The current sprite preview was rendered with the real LÖVE screen renderer and normal game font, using temporary display data. This artwork pass did not run the gameplay test suite or touch player saves. The earlier mechanics audit below predates this visual revision.

### Repair outcome and cost

- **Field service:** 26–99% condition, uses scrap only.
- **Major repair:** 0–25% condition, uses scrap and one matching part from the backpack. A broken weapon remains unusable without both.
- The base cost is `ceil((100 - condition) / 20) + ceil(tier / 2)`. Major repair adds `6 + 2 × tier`. A tier-7 weapon at 23% costs 28 scrap.
- Starting a repair runs a repeating alignment meter. A tap, click, Space, or Enter in the broad **GOOD** zone restores condition to 75–95%. A hit in the smaller brass **PERFECT** band restores 100%. A miss spends nothing. Above 95%, a GOOD hit that would not improve the weapon also spends nothing; a PERFECT hit can finish the repair.
- Changing the selected weapon, returning to the workshop, or closing the panel cancels the meter without spending resources.
- A successful major repair consumes one matching part only after the timing check succeeds.

### Part compatibility

`game/weapon_repair_parts.lua` holds the explicit 83 weapon-to-component entries. Catalog builds `weaponRepairParts` and `repairParts` from that list. Each definition includes its owning weapon, component label, rarity, dedicated sprite path and description. Repair lookup requires the owning weapon to match; it never infers compatibility from a family or words in the weapon ID.

Artwork lives at `assets/sprites/weapon-parts/<partId>.png`. Each image is a distinct transparent sprite imported at a maximum of 512 pixels, with generated originals preserved. Inventory identifies the exact fit, and the workbench uses a short component label beside the selected weapon.

The 16 component IDs from the earlier prototype are read-only compatibility aliases to 16 exact replacements. They do not add extra active components or enter new loot rolls, and an alias does not allow fitting any other weapon. No save rewrite is needed.

### Finding and storing components

Repair parts enter as supplemental house-cache loot, not as crafting recipes or merchant stock. Each house receives one 14% component-drop roll. If an owned weapon is at 25% or below and the backpack lacks its matching part, a successful component drop has a 72% chance to target one of those missing parts. Existing visited houses receive this additional roll once as well. Ordinary rolls start with common and uncommon components, add rare parts at loot tier 6, and add legendary parts at loot tier 9. All 83 parts are reachable in late-game ordinary rolls; a needed part can still be targeted regardless of its rarity tier.

Parts use ordinary backpack slots, can be moved into existing storage, and cannot be sold to merchants. A major repair checks the backpack, so a stored part must be moved there first. Loot, inventory, durability, and one-time cache markers all use existing save fields; no schema version change or save migration is needed.

### Research-to-game boundary

The real-world maintenance research remains in [real-world-maintenance-research.md](real-world-maintenance-research.md). It guides separate part silhouettes and family groupings: the 870 reference distinguishes its barrel, action group, and bolt; lever-action care favors a restrained wipe-down rather than a dramatic teardown; rifle families use their own grouped action components; bows and crossbows use string/cable/limb cues; and melee weapons use blade, head, haft, or sharpening cues. The meter remains an explicit game abstraction rather than a depiction of literal maintenance steps.

## Readiness audit — October 2, 2026

All 47 repair-specific automated tests and real LÖVE desktop/mobile-mode runs pass. The runtime runs each complete six checkpoints: balance, game entry, workshop entry and preview, successful repair and return, all 83 component sprites plus an empty inventory, and list dragging/wheel scrolling/selection/back navigation. Mobile mode uses the actual touch callbacks; this is a desktop simulation, not a fresh physical-device installation. The mobile packager's inclusion and image processing were also checked for all 83 sprites in temporary output, preserving their resolution, transparency and silhouettes.

The audit fixed omitted weapons when equipment slot 1 was empty, unreachable legendary components in ordinary late-game rolls, the 25% critical-condition boundary, timing target/scoring disagreement, keyboard/controller confirmation, list dragging, transformed button hit regions, disabled focus targets, stale selection/result state, and duplicate names for the two .22 pistols. No real player saves were touched.

Automated coverage includes every weapon across 14 durability values, exact part compatibility, cost/consumption, failed and repeated attempts, 16 prototype aliases, save round trips, storage capacity, chest-roll persistence, 495 drop/pickup combinations, merchant protection, layout fit, and cancellation. All part artwork was reviewed over light/dark backgrounds and at inventory scale.

The broader 388-test game regression run is not clean: its 18 reported failures comprise 13 older test-contract/mock/assertion mismatches and five existing character asset/specification mismatches. Read-only triage found none caused by the repair feature. These remain separate whole-game release issues. The repair flow passes the checks described above; whole-game release readiness remains unconfirmed.
