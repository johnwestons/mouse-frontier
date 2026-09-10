# Expedition Corrupted Mob Atlases

These pilot assets establish the sludge-host visual family:

- `sludge-bandit-action-atlas.png`: a recognizable mouse bandit in an early-to-mid takeover stage.
- `sludge-badger-boss-action-atlas.png`: a tunnel badger in an advanced takeover stage, used by The Buried Host boss.

Both action files are 1536 x 1024 RGB atlases with a 3 x 2 grid of 512 x 512 cells: idle, locomotion placeholder, attack, hit, defeat, alert. The selected `sludge-bandit-walk-v5.png` and `sludge-badger-boss-walk-v4.png` provide separate eight-frame, 4 x 2 walking sheets (1774 x 887 source pixels, split proportionally).

`game/expedition_sprites.lua` removes only border-connected or explicitly reviewed enclosed matte regions, preserving eyes, highlights and pale fur. It normalizes frames onto a 512 x 512 canvas at anchor `(256,492)`, retaining consistent scale. Actual resolved movement distance drives walking; blocked actors idle. Explicit source-facing metadata resolves world mirroring. Runtime-owned frames are protected from the generic asset streamer across area and battle changes.

Visual rules for future corrupted hosts:

- Preserve the host silhouette, clothing, gear, and at least half of the face.
- Grow glossy black sludge asymmetrically from one limb or flank.
- Use one glowing yellow infected eye and restrained cyan seam light.
- Progress corruption by coverage and posture, not by replacing the host with a generic sludge creature.
- Keep all actions centered on the same ground contact point and at consistent apparent scale.
- Avoid text, UI, cast shadows outside the sprite footprint, and cropped extremities.

These pilot files provide coherent single-view walking for the existing side-facing mob renderer. They do not represent eight camera directions. See `docs/concepts/expedition-sprite-audit/` for normalized visual checks and recorded directional-coverage limits. Original action art and intermediate walk sheets remain source references; rejected walking iterations are archived under that audit folder rather than bundled as game assets.
