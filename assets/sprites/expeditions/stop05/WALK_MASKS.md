# Stop 5 Badlands expedition walk masks

| Map image | Editable mask |
| --- | --- |
| `badlands-approach-background.png` | `walkmask-badlands-approach.png` |
| `redwash-basin-background.png` | `walkmask-redwash-basin.png` |

Both masks are opaque 1672 × 941 PNGs. White allows the player's feet to pass; black blocks cliffs and dense scrub. The Redwash Basin mask covers the entry spur, elevated ridge, braided wash, cairn overlooks, and cache side paths. The flash-flood closure is applied dynamically to the central low wash; the upper ridge remains available as a detour.

Keep the approach return, both basin exits, cairns, caches, mob patrols, and both route branches connected. Update the route geometry in `game/expedition_areas.lua` with the mask whenever the painted trails change.
