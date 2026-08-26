# Mouse Frontier — Version 0.7

A playable foundation for a post-apocalyptic critter journey aboard a four-car train.

The former code-structure freeze has been lifted for a staged [architecture migration](ARCHITECTURE_MIGRATION.md). Save compatibility and the shared Windows/Android source contract remain mandatory.

## Run on Windows

1. Install [LÖVE 11.x for Windows](https://love2d.org/) using the 64-bit installer.
2. Double-click `RUN_GAME.bat` in this project folder.

You can also drag the entire project folder onto `love.exe`. Do not open `main.lua` by itself because LÖVE needs the artwork and configuration files too.

## Build for Android

Run `BUILD_ANDROID.ps1` to derive the current shared game into a phone-sized package, execute the mobile smoke checks, and create a signed sideloadable APK. The first build downloads and verifies its Android build dependencies; later updates reuse the local cache.

Android controls, installation, update flow, and device verification are documented in [ANDROID_PORT.md](ANDROID_PORT.md). The deliberately small platform boundary is recorded in [MOBILE_ARCHITECTURE_DECISION.md](MOBILE_ARCHITECTURE_DECISION.md).

## Controls

- Click one of the three save slots, then choose a main character.
- Existing slots offer **Continue**, **New** (overwrite), and **Delete** controls.
- Move with **WASD** or the **arrow keys**.
- Use the travel control to preview the next leg's food, water, and coal cost. Costs rise at clear journey milestones, with terrain, passengers, engine upgrades, traits, and maintenance modifying the total.
- Open the backpack with its top-right button or press **I**.
- Click an item and then another slot to rearrange it.
- Select an item and click **DROP SELECTED ITEM** to place it permanently in the train.
- Stand near a dropped collectible and press **E** to pick it up.
- Walk to the final train-car door and press **E** to leave at a stop.
- Stand beside the engine fire and press **E** to add a coal chunk or coal bucket from the backpack.
- Stand near an NPC and press **E** to talk. NPCs idle and wander near their homes.
- Stand at a house entrance and press **E** to enter; its furniture can be collected and placed elsewhere.
- Open the journey map with its top-right button or press **M**. Only visited stops are revealed.
- Some stops have a one-time mob encounter before you can enter. Choose a weapon to attack or retreat to the train.
- Early stops favor helpful and fortunate trail events; battles and mishaps become more common later, and every event retains an actionable fallback.
- Train cars unlock across the route and provide shared storage, production, passenger, healing, or navigation benefits; the workshop shows when each upgrade becomes available.
- Winning an encounter clears that stop permanently and awards coal. Player health is retained in the save file.
- Weapons must be carried and placed into one of the two equipment slots before they appear in battle. Scratch is always available.
- Equipped weapons wear by one point on every attack attempt, including misses. Broken weapons cannot attack; repair the most damaged equipped weapon for scrap at the train workshop.
- Weapon damage and mob difficulty increase across smooth easy, medium, and hard journey bands; larger enemy groups award more coal, scrap, and experience.
- On the train, click **MOVE / SCALE** to drag, resize, rotate, or collect placed decorations. Click **DONE** to save the arrangement.
- Hold **Shift** while moving to sprint.
- Battles award experience; gaining levels improves maximum health and adds an attack bonus.
- Travel chests hold 10 persistent items. Stand nearby and press **E**, then drag items between chest and backpack slots.
- The cowboy mouse uses dedicated left- and right-walking sprites while moving.
- New houses receive a persistent randomized selection of four to six furniture pieces.
- Home and train interiors use new original pixel-art wood, rug, iron, brass, and upholstery textures.
- Mobs float while idling, flash when struck, and attacks display an animated slash impact.
- The map reveals terrain sketches, biome names, encounter status, and a winding dotted trail for visited stops.
- Stop scenes retain the current landscape without scrolling and include generated homes, trees, collectibles, and an NPC.
- Press **Escape** to close the backpack or return to the save menu.
- Progress saves after important choices, when traveling, and when the game closes.

## Project layout

- `main.lua` — thin LÖVE lifecycle forwarding only
- `game/application_composition.lua` — validated runtime graph construction
- `game/app.lua` — thin lifecycle adapter
- `game/systems.lua` — application-facing system manifest
- `game/config.lua` — shared runtime dimensions, layout, timing, and palette configuration
- `game/save_schema.lua` — authoritative save format version
- `game/` — gameplay, screens, input, rendering, saves, tests, and platform adapters
- `conf.lua` — window and game settings
- `RUN_GAME.bat` — double-click Windows launcher
- `assets/sprites/MainCharacters/` — selectable player characters
- `assets/sprites/NPCS/` — characters encountered at stops
- `assets/sprites/Mobs/` — future enemy units
- `assets/sprites/props/` — inventory and decoration sprites
- `assets/sprites/items/` — generated collectible sprites
- `assets/sprites/environment/` — generated houses, trees, and train furniture
- `assets/sprites/train/` — generated locomotive and train-car artwork
- `backgroundReferences/` — landscape references; the prototype currently scrolls the desert landscape

LÖVE stores the three save files in its `mouse-frontier/saves` save-data folder, safely outside the artwork folder. Older saves are upgraded sequentially to the current schema on load, with the original retained as a backup; invalid primary files recover from a validated temporary file or backup when available.

Loot rarity, weapon tiers, pricing, durability, repairs, ammunition availability, and resale rules are documented in [LOOT_EQUIPMENT_BALANCE.md](LOOT_EQUIPMENT_BALANCE.md).

## Automated smoke playthrough

Run `.stabilization/run-smoke.ps1` from PowerShell to launch the hidden watchdog test. The tester starts a fresh character, walks, opens and scrolls menus, spends supplies to travel, enters and exits a house, exercises an encounter and retreat, renders every major screen, and validates the asset contract.

Each run writes `.stabilization/smoke-report.rpt`. The report contains pass/fail checkpoints plus typed action return values and snapshots of important game variables. A callback error, failed expectation, stalled step, missing report, or watchdog timeout produces a nonzero exit code.

To test route reachability all the way to stop 50, use:

```powershell
powershell -ExecutionPolicy Bypass -File ".\\.stabilization\\run-smoke.ps1" -Full -Visible
```

Full-route reports identify whether the run reached the ending, exhausted supplies, stalled, or hit a code error. Full-route mode provisions supplies and auto-resolves encounters so route/ending reachability can be separated from combat difficulty; the normal smoke run continues to exercise battle controls.

## Character sprite processing

Use `tools/character_sprite_doctor.py` to audit, preview, repair, or import complete character animation sets. It checks frame counts, crop and scale consistency, centering, baselines, alpha residue, missing actions, and likely character-identity mix-ups. Repairs are previewed by default and applied changes receive timestamped backups.

The complete workflow and atlas layout are documented in [`tools/SPRITE_WORKFLOW.md`](tools/SPRITE_WORKFLOW.md).
