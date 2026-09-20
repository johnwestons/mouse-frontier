# Player options

Open **Settings → Cheats / Controls**, or press **F2**. The save selection screen also has a **Cheats / Controls** button. Gameplay pauses while this menu is open. Escape, Android Back, F2, or Close returns to the previous screen.

- **Items:** browse all 221 inventory objects using their existing sprites, including atlas-backed items. Select a category, search by name or properties, and cycle the rarity filter. Hover for details or tap a row to select it. Choose a quantity and press Add. Ordinary items require free backpack slots; requests that do not fit make no changes. Ammunition adds the exact number of rounds to its counter, including when the backpack is full. Adding a backpack item does not automatically equip it.
- **Cheats:** add scrap, food, water, coal, oil, and all 13 ammunition types. Choose a preset quantity, use +/−, or tap the quantity field and type a whole number. Page through the list to reach every resource.
- **Controls:** drag Move, Use, Action, Back, or Menu in the screen preview. Positions save on release and apply to all journeys on the device. Reset Positions restores the original automatic edge placement. Touch control sizes still follow the existing accessibility settings.

Item and resource changes apply to the loaded journey and save immediately through the existing save system. A failed save is reported and remains queued for retry. Loading a journey is required for grants; control positions can be changed from the save selection screen. Position settings are stored separately in `control-layout.txt` in LÖVE's application save directory.

The item list combines the game's sprite folders, item atlases, and mechanical catalog, with source sheets and engine effects excluded. It does not load all sprite images until they are displayed in normal use. No dialogue is added or changed.

## Verification

Run `tools/player-tools-test/run.ps1` for actual LÖVE tests of item coverage and sprites, category/search/rarity filters, resource and item grants, quantity validation, full-backpack handling, save round trips, persisted control positions, moved touch hit areas, and application input routing. The test uses a separate save identity and captures the three menu pages there. Run `tools/run_smoke.ps1` for the existing gameplay checks.
