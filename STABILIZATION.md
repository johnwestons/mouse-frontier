# Mouse Frontier Stabilization Release 1.9.1

This pass focuses on reliability rather than adding gameplay systems.

## Changes

- Created a recoverable pre-stabilization code checkpoint under `.stabilization/`.
- Moved music, ambience, and sound-effect loading into `game/audio.lua`.
- Audio failures are logged and shown in the in-game Options panel.
- Normalized the locomotive animation canvases to a common bottom edge.
- Added a shared rail-contact baseline for the track, locomotive, and train car.
- Removed dynamic locomotive rotation around the PNG corner.
- Removed the obsolete distance-based battle renderer.
- Removed duplicate backpack header rendering.
- Added sequential save migrations through save version 22.
- Added uniform viewport scaling with letterboxing to prevent fullscreen stretching.
- Moved asset discovery/loading into `game/assets.lua`.
- Moved reusable tactical calculations and temporary-status cleanup into `game/battle_rules.lua`.
- Added strict required-asset validation for base character, NPC, mob, and core animation art.
- Added a deterministic smoke matrix covering slots, character select, train, stop, house, inventory, event, battle, and ending screens.
- Fixed the tactical battle draw crash caused by a stale stop-layout reference.
- Fixed expanded-backpack coal lookup, stale player-as-NPC save data, modal right-click click-through, and invalid-save continuation.
- Fixed event ammunition affordability/deduction and routes overflow rewards into house storage instead of loose ground loot.
- Fixed temporary combat buffs/debuffs so they expire and prevents an ally victory from leaving the player at zero health.

## Current controls

- Move: WASD or arrow keys
- Sprint: Shift
- Pick up/use: E
- Talk, doors, train boarding and car navigation: Q
- Backpack/container: I
- Map: M
- Boombox radio: P while standing nearby
- Close menus: Escape

## Recovery

The code from immediately before this stabilization pass is stored at:

- `.stabilization/main-pre-stabilization.lua`
- `.stabilization/conf-pre-stabilization.lua`
