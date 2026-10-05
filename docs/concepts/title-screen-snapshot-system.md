# Title screen snapshot system

The title screen has three visual layers:

1. **Memory scenes** in the two open side bays. Each complete pair fits in the space between the actual window edge and the save panel, including the extra room outside the 960px stage on wide displays.
2. **Train-car chrome** behind the title, journey prompt, and lower control row.
3. **Save controls** with their own reserved central column. Memories end at least 12 logical pixels before this column; the cards never conceal part of a scene.

## Snapshot recipes

`game/title_snapshots.lua` selects from twenty-five four-frame authored sprite strips. The menu shows the art without captions:

- share water
- share food
- bandage a wound
- share a laugh
- help them walk
- meet with trust (handshake)
- tend a seedling
- share shelter under an umbrella
- repair a field radio
- prepare tea together
- move supplies together
- play a tune by lantern light
- plan a route with a compass
- deliver medicinal herbs
- repair a roadside cart
- tend a quiet garden
- share a camp supper
- repair a lantern together
- bandage a fellow traveler
- make a fair trade
- repair a small boiler
- find a safe river ford
- mark a trail
- learn a hand signal
- read a route card together

The strips are composited raster sprites, created from existing character sheets as identity and style references. They contain the full interaction and props in four animation frames. A missing strip leaves its bay empty.

## Comfortable memory playback

Each memory lasts 36 seconds. It fades in over four seconds, holds its poses, then dissolves to the next authored pose over three seconds at seconds 7, 15, and 23. The final pose rests before fading out during seconds 31–35. A one-second quiet interval separates the next memory. The two sides are staggered by 18 seconds and start with different scenes.

The camera and sprite position stay fixed. There is no zoom, rotation, drift, echo, opacity pulse, or backwards jump from pose four to pose one. A shader blends the two poses in a single draw, preserving opacity through the dissolve. Different scenes fade through the menu background without overlapping.

## Sprite assets

- `assets/sprites/ui/title/title-header-backdrop-v1.png` — wide transparent train trim for the upper control area.
- `assets/sprites/ui/title/title-footer-backdrop-v1.png` — wide transparent sill for the lower controls.
- `assets/sprites/ui/title/snapshots/*.png` — twenty-five four-frame authored helping scenes.

The assets are loaded lazily with the rest of the title scenery. Each memory retains its transparent background, feathered alpha edge, and subtle warm tint. Scene sizing follows the current title transform, including custom menu position, scale, and rotation; the same card bounds drive both control placement and the memory exclusion area.

The renderer fits the visible artwork rather than the transparent padding around it. A single content envelope covers all four poses so sizing and position remain steady throughout the scene. Enlarged memories use an eight-pixel outer margin and preserve their 12-pixel separation from the controls. Mobile packaging resizes each of the four authored cells independently, preventing colors from leaking across frame boundaries.

If a side bay is smaller than 120 logical pixels, its decoration is omitted rather than reduced to an unreadable pair or placed under the controls.
