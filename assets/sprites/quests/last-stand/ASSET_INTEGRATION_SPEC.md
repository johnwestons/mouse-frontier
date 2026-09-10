# Last Stand Asset Integration Specification

## Status

This directory contains source-quality art candidates for the Last Stand rescue quest.
The files are not approved runtime assets until the visual approval and normalization
gates below are complete.

Only the alpha-candidate files listed below are compositing-safe. Generated checker
sources, chroma-key intermediates, and superseded `v1` alpha attempts must never be
loaded by the game. The two full-frame distance plates are intentionally opaque.

## Non-negotiable visual rules

- Friendly-house backgrounds contain no baked NPCs.
- Enemy-building backgrounds contain no baked mobs.
- The house interior has exactly two distinct firing windows.
- Both house-window openings remain transparent in the interior shell.
- Relay windows and doorways remain transparent in the relay facade.
- The landscape, relay facade, targets, muzzle flashes, impacts, window surround,
  player weapon, and HUD are separate layers.
- Bullet damage belongs only on solid walls, trim, floors, furniture, and props.
- No bullet holes, impact marks, or debris may float in an aperture or open air.
- Only gun-capable hostile mob atlases may occupy enemy target slots.
- Friendly and hostile character assets are never shared across factions.

## Environment inventory

| Runtime ID | Candidate file | Source canvas | Alpha policy | Purpose |
| --- | --- | ---: | --- | --- |
| `last_stand.backyard_shell` | `friendly-house-backyard-shell-alpha-candidate-v4.png` | 1672x941 | Transparent outside footprint | Walkable exterior and backyard shell |
| `last_stand.interior_shell` | `friendly-house-interior-shell-alpha-candidate-v4.png` | 1671x941 | Transparent outside room and through both windows | Walkable domestic interior foreground |
| `last_stand.grassland_distance` | `grassland-distance-plate-candidate-v1.png` | 1672x941 | Opaque | Reusable distant landscape plate |
| `last_stand.relay_distance` | `rail-relay-background-candidate-v1.png` | 1672x941 | Opaque | Flattened concept/reference only; not used when the layered facade is active |
| `last_stand.relay_facade` | `rail-relay-facade-cutout-alpha-candidate-v4.png` | 2001x786 | Transparent outside silhouette and through target apertures | Enemy position laid over a location plate |
| `last_stand.window_frames` | `house-firing-window-frames-alpha-candidate-v4.png` | 1774x887 | Transparent outside frames and inside openings | Two distinct close-up firing-position foregrounds |
| `last_stand.shootout_fx` | `shootout-effects-atlas-alpha-candidate-v4.png` | 1774x887 | Transparent between effects | Muzzle flashes, smoke, impacts, and near-miss tracer |
| `last_stand.damage_decals` | `house-surface-damage-decals-alpha-candidate-v3.png` | 1774x887 | Transparent between decals | Runtime damage restricted to valid solid surfaces |
| `last_stand.distant_dust` | `distant-dust-loop-alpha-candidate-v3.png` | 2172x724 | Transparent around each phase | Eight-frame atmospheric loop |
| `last_stand.domestic_props` | `domestic-siege-props-atlas-alpha-candidate-v3.png` | 1774x887 | Transparent between props | Movable blankets, medical supplies, water, chair, casings, and lantern |

## Character inventory

| Runtime ID | Candidate file | Source canvas | Logical layout | Faction and use |
| --- | --- | ---: | --- | --- |
| `last_stand.enemy.mouse_bandit` | `mouse-bandit-rifle-target-atlas-alpha-candidate-v4.png` | 1774x887 | 4x2 source poses | Hostile rifle target |
| `last_stand.enemy.cowboy_mouse` | `cowboy-mouse-rifle-target-atlas-alpha-candidate-v4.png` | 1774x887 | 4x2 source poses | Hostile rifle target; no skull mount |
| `last_stand.enemy.tunnel_badger` | `tunnel-badger-rifle-target-atlas-alpha-candidate-v4.png` | 1774x887 | 4x2 source poses | Heavy hostile rifle target |
| `last_stand.friend.guard_fox` | `guard-fox-rifle-action-atlas-alpha-candidate-v4.png` | 1774x887 | 4x2 source poses | Defender and loan-rifle NPC |
| `last_stand.friend.gecko_ranger` | `gecko-ranger-pistol-action-atlas-alpha-candidate-v4.png` | 1774x887 | 4x2 source poses | Second healthy window defender |
| `last_stand.friend.otter_scout` | `otter-scout-support-action-atlas-alpha-candidate-v4.png` | 1774x887 | 4x2 source poses | Quest giver, guide, wounded support, and ammo handoff |
| `last_stand.friend.otter_scout_walk` | `otter-scout-approach-walk-alpha-candidate-v4.png` | 2172x724 | 8x1 source poses | Controlled side-on approach sequence |

## Required normalization outputs

Generated source atlases are intentionally retained, but their odd dimensions are not
safe for uniform runtime quads. After visual approval, extract and normalize them into
new files rather than changing these candidates.

- Combat and support atlases: eight 512x512 frames in a 2048x1024 runtime atlas.
- Otter approach: eight 320x512 frames in a 2560x512 runtime strip.
- Effects: eight 512x512 frames in a 2048x1024 runtime atlas.
- Window surrounds: export two independent transparent PNGs instead of runtime quads.
- Use a bottom-center foot anchor for standing characters.
- Keep the weapon muzzle anchor as per-frame metadata rather than moving the character
  pivot to follow the gun.
- Keep a shared head-height guide within each character atlas.
- Trim only transparent space before placing a frame on its normalized canvas.
- Do not resample during extraction. Runtime draw scale handles final screen size.
- Record every frame rectangle, pivot, muzzle point, hit region, and aperture assignment
  in data rather than hard-coding them in draw functions.

## Logical animation states

### Hostile 4x2 atlases

1. `peek`
2. `raise`
3. `aim_at_viewer`
4. `fire_recoil`
5. `duck_or_hit`
6. `hit_confirm`
7. `collapse`
8. `down`

The exact source pose order may vary slightly by candidate. Normalization is the point
where poses are mapped to these state names. No hostile becomes hittable until `peek`
has exposed the configured hit region. A killed hostile finishes `collapse`, holds
`down` briefly, and then vacates its aperture.

### Guard fox 4x2 atlas

Map the eight poses to `idle_rifle`, `check_weapon`, `offer_rifle`, `offer_ammo`,
`raise`, `aim`, `fire_recoil`, and `recover` during normalization.

### Gecko ranger 4x2 atlas

Map the eight poses to `low_ready`, `raise`, `aim`, `fire_recoil`, `reload_start`,
`reload_finish`, `duck`, and `step_clear` during normalization.

### Otter support 4x2 atlas

Map the eight poses to `tired_idle`, `seated_rest`, `bandage`, `rise`,
`reload_start`, `reload_finish`, `low_ready`, and `beckon` during normalization.

### Effects 4x2 atlas

Map the cells to `flash_small`, `flash_medium`, `flash_large_smoke`, `smoke`,
`impact_wood`, `impact_masonry`, `impact_dirt`, and `near_miss_tracer`.

## Enemy aperture IDs

The facade supports a reusable logical slot map. Exact normalized rectangles are
captured after the facade is approved and scaled for the firing scene.

- `upper_left`
- `upper_right`
- `annex_left`
- `center_door`
- `center_window`
- `loading_bay_left`
- `loading_bay_right`
- `side_door`

Each slot owns a stencil rectangle or polygon, depth value, target scale, target
baseline, muzzle point, allowed enemy types, and cover timing profile. Targets are
drawn behind the facade and clipped to their assigned aperture so no body, weapon, or
death pose can spill across a solid wall.

## Walkable interior draw order

1. Location-specific distance plate behind both transparent windows.
2. Optional slow cloud and atmospheric-light layers.
3. Distant relay facade or another location-specific structure layer.
4. Tiny distant target and muzzle-flash layers when ambient gunfire is active.
5. Interior shell.
6. Floor decals and dynamic incoming-impact particles on valid solid surfaces.
7. Player and friendly NPCs using the existing interior depth-sort rules.
8. Interaction prompts, dialogue, and HUD.

The interior shell must not be flattened with steps 1 through 4. Changing the window
scene must require only a data selection, not a new interior image.

## Firing minigame draw order

1. Opaque landscape plate.
2. Slow atmosphere and dust layers.
3. Aperture darkness cards behind the relay facade.
4. Hostile targets, clipped to their assigned apertures.
5. Relay facade.
6. Hostile muzzle flashes, clipped to the same apertures.
7. Incoming tracer, near-miss, and valid foreground impact effects.
8. Selected close-up house-window surround.
9. Player hip-fire or ADS weapon sprite.
10. Crosshair, ammo, position timer, pressure meter, and objective HUD.

This order preserves the 300-meter sight line while keeping enemies visibly garrisoned
inside the building rather than pasted onto its front wall.

## Weapon and ammo fallback presentation

- The guard fox owns the temporary `frontier-22-lever-rifle` loan interaction.
- Offer the loan before the first firing prompt if the player lacks a usable firearm.
- Offer quest-only ammunition if the selected gun is empty or incompatible with the
  player's remaining ammunition.
- Repeat emergency ammo handoffs between waves so the quest cannot softlock.
- The loan rifle and quest ammunition cannot be sold, dropped, stored, or retained
  after the quest resolution transition.
- Use the fox `offer_rifle` or `offer_ammo` pose while the inventory transfer occurs.
- Return or remove the loan in the reward scene before normal stop control resumes.

## Approval gates

1. Approve the friendly backyard shell and its clear back-door route.
2. Approve the domestic interior, exactly two windows, damage placement, and clear
   firing areas.
3. Approve the landscape-to-relay composition at the intended 300-meter scale.
4. Approve all three friendly identities and all three hostile identities.
5. Approve the two close-up firing-window variants and effects language.
6. Normalize approved assets and capture pivots, apertures, and hit regions.
7. Build a static compositing scene before implementing battle logic.
8. Implement the quest and minigame only after the static scene passes visual review.

## Asset-level definition of ready

The art package is ready for code integration when every selected file has real alpha
where required, no baked actors or effects, no floating damage marks, normalized frame
geometry, stable anchors, named animation states, measured aperture masks, and explicit
visual approval. Until then, code should refer only to planned runtime IDs and must not
ship these source candidates directly.
