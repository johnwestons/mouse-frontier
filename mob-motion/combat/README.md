# Mob combat animation assets

All 24 enemy profiles now use six authored frames for each melee attack, ranged
attack, hit reaction, and death. Eighteen creature suites were generated with
built-in ImageGen; six humanoid profiles reuse their existing reviewed NPC strips.
Each generated suite's JSON records the final prompt, source hash, runtime hashes,
dimensions, and timing. Runtime art lives in `assets/sprites/Mobs/combat/`.

The eagle has one head. Sludge creatures have round mouse-like ears, following
the user's final reference. The crawler's battle neutral pose comes from the
corrected suite so its ears stay consistent between actions.

## Playback contract

- Six 512 by 256 cells form each 3072 by 256 strip, with transparent padding and
  a common scale and baseline across the creature's entire suite.
- Attacks and hit reactions follow the existing battle action timers and play
  once per action. Death lasts 0.85 seconds and holds the sixth frame.
- Death timing and facing survive replacement unit tables in co-op snapshots;
  a new encounter resets transient playback state.
- Combat image aliases use the existing lazy asset tables and ownership rules.
- Mobile builds preserve six complete cells and calculate quads and world scale
  from decoded dimensions.

## Authoring and review

Stage an ImageGen source atlas with six columns and four rows (melee, ranged,
hit, death). A sources JSON is a list of records containing `name`, absolute
`source` path, and final `prompt`.

```powershell
python tools/build_mob_combat_assets.py --sources sources.json
```

Inspect every staged `output/mob-combat/staged/<name>/contact-backgrounds.png`
and the per-action GIF previews. The contact sheets composite every frame over
light and dark backgrounds. Resolve audit errors before installing reviewed art:

```powershell
python tools/build_mob_combat_assets.py --install-reviewed <name> --write-profiles
```

Installation verifies the source and staged image hashes before copying assets.
The builder splits and normalizes authored poses; it does not synthesize motion.

The focused behavior tests are in
`tools/tests/test_mob_combat_animation_behavior.py`. The native LÖVE harness draws
all 24 suites through the production battle renderer in desktop and mobile UI
layouts, checks every frame, and writes battle screenshots without accessing
campaign saves:

```powershell
$env:MOUSE_FRONTIER_PROJECT_ROOT = (Get-Location).Path
& 'C:/Program Files/LOVE/lovec.exe' tools/mob-combat-smoke
```

Set `MOUSE_FRONTIER_MOB_ASSET_ROOT` to a staged asset root to repeat the native
check against optimized mobile PNGs.
