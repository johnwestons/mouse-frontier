# Wilderness Expeditions Production Art Notes

All four pilot assets were generated with the built-in image-generation workflow, using the existing Mouse Frontier stop, mob, and sludge-crawler artwork as style and identity references.

## Clean map backgrounds

### Riverwood Outskirts

Output: `assets/sprites/expeditions/stop06/outskirts-background.png`  
Size: 1672 x 941

Production brief: convert the approved wilderness concept into a clean, playable map background while preserving its high-overhead isometric camera, looping dirt routes, river and forest boundaries, scattered ruins, eastern cache landmark, southern town return, and northeastern dungeon approach. Remove all baked player, enemy, creature, marker, label, and interface imagery so every gameplay actor can be rendered independently. Match the painted pixel-art finish and 16:9 stop-sprite format.

### Buried Waystation

Output: `assets/sprites/expeditions/stop06/buried-waystation-background.png`  
Size: 1672 x 941

Production brief: convert the approved dungeon concept into a clean, playable background. Preserve the entrance, readable hub, two patrol branches, side cache, blocked boss route, broad boss arena, and treasure vault, with warm lantern pools against cool mossy underground shadows. Remove baked player, enemies, boss, labels, markers, and interface imagery. Keep broad walkable floors and clean depth ordering.

## Sludge-host action atlases

### Sludge-Taken Bandit

Output: `assets/sprites/Mobs/expedition/sludge-bandit-action-atlas.png`  
Size: 1536 x 1024; 3 x 2 cells

Production brief: morph the current mouse bandit with the current sludge crawler in a visible early-to-mid infection stage. Keep the bandit's species, outfit, hat, scarf, and gear recognizable. Spread glossy black sludge asymmetrically over one limb and flank, add one glowing yellow infected eye and cyan cracks, and retain the host silhouette. Create consistent full-body idle, walk, melee attack, hit, defeat, and alert poses in reading order. Use a clean high-resolution game-sprite presentation with stable scale and ground contact.

### The Buried Host

Output: `assets/sprites/Mobs/expedition/sludge-badger-boss-action-atlas.png`  
Size: 1536 x 1024; 3 x 2 cells

Production brief: morph the current tunnel badger raider with the current sludge crawler in an advanced infection stage. Preserve the badger face, broad silhouette, miner/raider clothing, and equipment while making it substantially larger and more threatening than the bandit. Grow heavy sludge armor over one shoulder, arm, back, and leg; add one yellow infected eye, cyan seams, tendrils, and an asymmetric hunched posture. Create consistent idle, locomotion, crushing attack, hit, collapse, and roar/alert poses in reading order.

## Integration note

The generators returned opaque neutral matte backdrops. `game/expedition_sprites.lua` performs connected matte removal, including reviewed enclosed background seed points, without globally erasing pale character details. Action and walking frames share the normalized ground anchor `(256,492)`. The existing tactical action-image tables receive normalized frames, marked as owned by the expedition runtime so streaming cannot release them during return transitions.

## Walking correction pass

Selected outputs: `assets/sprites/Mobs/expedition/sludge-bandit-walk-v5.png` and `assets/sprites/Mobs/expedition/sludge-badger-boss-walk-v4.png` (1774 x 887 each). These were produced with the built-in image generator, using original action art for identity and viewing direction. Sources were retained through targeted corrections of opposite-foot phases, healthy/infected limb identity, boss camera orientation, and a missing bandit tail. The requests called for eight row-major phases in a uniform 4 x 2 grid: left contact, left loading, right passing, right propulsion, right contact, right loading, left passing, left propulsion. Fixed proportions, crisp outlines, transparent background, stable scale and baseline, complete silhouettes and no labels were required.

Final prompt records, source limitations and normalized contact-sheet/loop checks are recorded with the sprite audit. Runtime normalization handles the returned matte and source dimensions. These are single-view pilot animations with horizontal facing; they do not claim full eight-direction animation coverage.
