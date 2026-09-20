# Editable expedition walk masks

| Map image | Editable mask |
| --- | --- |
| `outskirts-background.png` | `walkmask-outskirts.png` |
| `buried-waystation-background.png` | `walkmask-buried-waystation.png` |

Both masks start completely white and match their map image at **1672 × 941 pixels**.

- Leave **white** where characters may walk. Paint **black** over water, walls, obstacles, and other blocked ground.
- Place the matching map underneath the mask as a reference layer in your image editor. Export only the black-and-white mask, with its original filename and dimensions.
- Use an opaque image and a hard brush for clear boundaries. The game uses the same brightness threshold and small clearance around the feet as the stop masks.
- Save the PNG and restart the desktop game to load edits. Mobile builds include these masks without resizing; rebuild/install to update a device.

These PNGs replace the old path restrictions. Until painted, the white templates allow movement across the map. The outer screen boundary and the dungeon's existing boss/vault progression locks still apply. Enemy patrol waypoints remain defined in `game/expedition_areas.lua`.
