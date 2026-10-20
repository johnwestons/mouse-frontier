# Character weapon swings

The 55-character roster has six authored swing frames per character. Original
`melee.png` strips remain the unarmed attacks, including Scratch. The repaired
Botanist Frog source separates the first-frame forearm and fist from the cloak.

Each `swing.png` is a 3072 by 256 RGBA strip of six 512 by 256 cells. The sequence
is ready, wind-up, overhead apex, strike, follow-through, recovery. Playback uses
the same normalized action phase for the character and held item. West-facing
actors reflect the entire body, hand position and weapon orientation.

`hands/` stores six reviewed source-space grip positions and angles per character.
`weapon-grips.json` stores the actual handle and shaft direction for all 37 melee
item sprites. The equipped sprite retains its original artwork; a small patch of
the authored gripping hand covers the handle. Swing frames contain no baked-in
weapon. First-person weapon art and animations are unchanged.

`acceptance.json` records installed hashes, frame bounds, hand points, body scale
and review evidence. `game/character_swing_profiles.lua` is generated from that
ledger. Body scale and baseline corrections account for the overhead arm's extra
space, including mobile packages with smaller cells.

## Rebuild and review

1. Keep the generated source atlases in `output/character-swings/sources/`.
   `sources.json` and `generation/` record the generation provenance.
2. Run `python tools/build_character_swing_assets.py` (or `--only character-slug`).
3. Inspect every staged frame on both backgrounds in `contact-backgrounds.png`,
   plus source hand vectors, before running `--install-reviewed`.
4. Run the swing behavior and asset tests and
   `tools/character-swing-smoke/run.ps1 -Mode both` with LÖVE installed.

All 330 frames were reviewed on light and dark backgrounds. The audit reports
zero errors. Its `top_bound_jitter` warning is expected for this action: the
raised hand changes the silhouette top while the core anchor and feet stay
stable. This warning is retained rather than hiding it with a wider threshold.

The isolated LÖVE harness captures the roster and all equipped melee items,
checks every character/item/frame combination in both facings, verifies the
animation viewer exposes Swing, and releases streamed characters. Captures and
reports are in `.stabilization/character-swing/`. Mobile package cell geometry
and resolution-independent held-item transforms are also regression-tested.

Field combat selects a working equipped melee item or falls back to Scratch.
Unarmed attacks keep normal reach, obstruction checks and cooldowns and do not
wear an item. Co-op commands retain ownership and cooldown validation. QA uses
an isolated identity and in-memory saves; no existing game saves were opened.
