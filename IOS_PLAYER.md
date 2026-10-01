# Mouse Frontier in an iOS LÖVE player

Mouse Frontier is distributed here as a `.love` game archive for a compatible iOS LÖVE player such as Love2D Studio. It runs inside that host app; the archive is not an IPA or a standalone iOS app. The current package uses LÖVE 11.5 APIs.

## Playtest package

- File: `output/mobile/ios-player-playtest/mouse-frontier-0.7.0-mobile.21.love`
- Version: `0.7.0-mobile.21` (LÖVE 11.5)
- Size: 282,975,663 bytes (about 283.0 MB)
- Source commit: `e13ad7f655cc1f48394e5a0e22118aab125d576a`; working tree was dirty at build time.
- SHA-256: `5ab4a82c8d388d955a146e357c352ac8e7fd4c9455a0ba8b0f60cd3667f86851`

Importing this exact package and checking its size limit on a physical iPhone or iPad are still pending.

## Import and launch

1. Install Love2D Studio from the App Store.
2. Download the supplied `mouse-frontier-0.7.0-mobile.21.love` file.
3. Save or open it through the iOS Files share/open flow.
4. Choose Love2D Studio to import the game.
5. Select Mouse Frontier in the player and launch it.
6. Use an empty save slot for testing unless you intentionally want to use existing progress.
7. When reporting an issue, include the device model, iOS version, host-app version, package version, steps to reproduce, and a screenshot or recording.

## Host and save behavior

The player controls the supported device orientations and its presentation area. Mouse Frontier starts from its existing 960×720 landscape layout and scales uniformly through the shared viewport when the host resizes the game surface. LÖVE 11.5 supports safe-area queries, but this package does not move controls based on safe-area values without device evidence that the host reports useful insets and that an essential control is obstructed.

The game keeps the shared `mouse-frontier` save identity and schema version 35. Saves live in the host app's sandbox. Another LÖVE player has its own app container, so moving the `.love` archive to a different host does not transfer saved progress.

## iPhone and iPad playtest checklist

Physical verification is pending. Test the exact package in Love2D Studio and record the host-app version, device model, iOS version, and package checksum. Check:

- Import from Files and launch in landscape; rotate or resize the host view.
- Clearance around the notch or Dynamic Island, rounded corners, Home Indicator, and host toolbar.
- Save-slot display and starting a new test game in an empty slot.
- Joystick movement, sprinting, contextual actions, Talk, Give, Backpack, Menu, and Back.
- Direct touch in menus, inventory, map, conversations, trading, travel prompts, and activities.
- Shooting-range and Last Stand aiming with one touch and independent firing with another.
- Pinch zoom, two-finger camera pan, touch release/cancel, and interruption while a control is held.
- Background and resume, save persistence after reopening, audio behavior, performance, memory pressure, and any import-size limit.

Capture a screenshot or short recording for layout or input failures. Do not treat mocked OS checks or Windows smoke runs as physical iOS verification.
