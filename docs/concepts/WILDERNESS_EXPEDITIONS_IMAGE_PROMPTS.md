# Wilderness Expeditions Concept-Art Prompts

The two concept images were generated with the built-in image-generation mode. Existing project art was used as visual reference; the original files were not edited.

## Surface wilderness prompt

```text
Use case: stylized-concept
Asset type: full-screen game environment concept art for a large explorable wilderness map
Input images: Image 1 and Image 2 are visual style, rendering, palette, scale, and isometric-environment references from the existing game; Image 3 is the existing sludge-crawler enemy reference.
Primary request: show how a player can leave a frontier stop and explore a much larger nearby wilderness region. The map should feel like a natural extension of the existing settlement sprites but be wider, more open, and more top-down.
Scene/backdrop: overgrown forest-and-river frontier wilderness with a broken stone ruin, a small abandoned camp, scattered salvage, one tucked-away loot chest, and a dark stone dungeon entrance built into a rocky hillside. A wooden path or gate at the lower edge implies the route back to town.
Subject: a clear looping network of broad walkable dirt paths and clearings; three small roaming hostile creatures including one recognizable black sludge crawler with glowing yellow eyes; a tiny mouse adventurer with a melee weapon for scale; distinct sight lines and room for enemies to patrol and chase.
Style/medium: detailed hand-painted high-resolution pixel art matching the reference settlement sprites; grounded post-apocalyptic woodland frontier; game-production concept art, not a loose painting.
Composition/framing: 16:9 landscape, entire traversable region visible like a large map sprite, approximately 60-degree overhead top-down isometric view, noticeably more overhead than the references, no horizon. Make the route back to town, ruin clearing, optional chest route, and dungeon entrance readable at a glance. Use trees, cliffs, water, and rubble to form natural boundaries.
Lighting/mood: late-afternoon filtered forest light, inviting exploration with a little danger.
Constraints: preserve the visual language of the reference game; broad walkable surfaces suitable for mouse-character navigation; clean depth ordering; no UI, no labels, no text, no logos, no watermark.
Avoid: side-view perspective, realistic 3D render, tiny maze-like paths, tile-grid outlines, excessive buildings, giant characters, battle arena UI.
```

References:

- `assets/sprites/stops/settlement-wide-06.png`
- `assets/sprites/stops/settlement-wide-16.png`
- `assets/sprites/Mobs/sludge-crawler.png`

## Dungeon prompt

```text
Use case: stylized-concept
Asset type: full-screen game environment concept art for an explorable dungeon map
Input images: Image 1 is the matching surface wilderness concept and establishes the camera, scale, and visual treatment; Images 2 and 3 are existing game environment references for rendering detail and frontier construction.
Primary request: design the dungeon reached through the wilderness entrance as a separate large walkable map sprite. It should support real-time exploration with roaming enemies, then culminate in a boss or multi-mob battle and a valuable treasure reward.
Scene/backdrop: an ancient stone waystation buried under the wilderness, partially reclaimed by roots and underground water, with improvised frontier salvage, broken rail machinery, lanterns, moss, and collapsed masonry.
Subject: a clearly readable entrance chamber; a central hub; two short optional branches with one ordinary loot chest and one resource cache; two broad enemy patrol rooms; a locked-looking threshold leading to a large circular boss chamber; and a distinct treasure vault beyond the boss arena containing a prominent good-treasure chest.
Style/medium: detailed hand-painted high-resolution pixel art matching the reference game; grounded post-apocalyptic frontier dungeon; production-ready environment concept art.
Composition/framing: 16:9 landscape, entire dungeon floorplan visible like one large map sprite, approximately 60-degree overhead top-down isometric view, no horizon, no roof and no cutaway walls blocking paths. Use walls, rubble, shallow water, rails, and height changes as clean boundaries. Keep walkable floors broad enough for the mouse player and several pursuing mobs. Make the critical route understandable without labels: entrance -> hub -> patrol spaces -> boss chamber -> treasure vault. Include a tiny mouse adventurer and several small dark hostile creatures for scale, plus one larger boss silhouette in the boss chamber.
Lighting/mood: warm lantern pools against cool green-blue underground shadows; mysterious but readable.
Constraints: consistent with Image 1 and the existing game sprites; clean depth ordering; no UI, no labels, no text, no logos, no watermark.
Avoid: narrow maze corridors, first-person view, realistic 3D, tile-grid outlines, excessive darkness, giant characters obscuring the layout, battle interface.
```

References:

- `docs/concepts/wilderness-expedition-surface-concept.png`
- `assets/sprites/stops/settlement-wide-05.png`
- `assets/sprites/stops/settlement-wide-16.png`
