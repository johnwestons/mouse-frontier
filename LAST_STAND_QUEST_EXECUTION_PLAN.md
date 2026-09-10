# Last Stand Quest: Final Execution Plan

## 1. Locked Creative Direction

The quest is a prolonged firefight between two fixed positions roughly 300 meters apart:

- Friendly position: a lived-in railway keeper's homestead occupied only by friendly NPCs.
- Hostile position: an abandoned railway relay and freight station occupied only by firearm-capable mobs.
- The player can explore the backyard and interior between shooting sessions.
- The player fires from either of two front windows using the first-person shooting mechanics established by the range.
- Friendly NPCs continue defending the home while the player moves, talks, reloads, treats wounded critters, or changes windows.
- The siege ends only after the player has held the position long enough and reduced enemy morale enough to make the survivors flee.

The current concept art establishes composition and tone. Concept images containing NPCs are staging references only. Production backgrounds must not contain baked-in characters, enemies, weapons, muzzle flashes, bullet tracers, or scenery inside transparent window openings.

## 2. Final Story Flow

### Beat 1: The scout finds the player

- At an eligible stop, an otter scout enters from a safe edge of the stop and walks toward the player.
- The scout waits rather than interrupting combat, another dialogue, a menu, or a transition.
- Interaction begins automatically only when the player is free and the scout is close. A normal interaction prompt remains available if the approach is interrupted.
- Dialogue choices are `Help now`, `Ask what happened`, and `Not yet`.
- `Not yet` is reversible. The scout waits at the stop and can be approached later.

### Beat 2: Follow transition

- Accepting stores the exact origin stop and starts a short travel montage.
- The montage shows the scout leading the player along a trail, distant gunfire growing louder, and the back of the homestead coming into view.
- The transition is skippable and respects reduced-motion settings.
- The player cannot lose time, supplies, or quest state during the montage.

### Beat 3: Backyard arrival

- The player arrives behind the house, away from the enemy firing line.
- Friendly NPCs only: wounded, resting, reloading, carrying supplies, or watching the back door.
- The back door is usable and clearly marked by interaction feedback rather than a baked-in symbol.
- Optional help: treating one wounded critter through the existing first-aid interaction improves defender support and the final reward, but is not required.

### Beat 4: Interior briefing

- The interior is still recognizably a family home. Furniture has been moved, damaged, or punctured, but it is not a barracks.
- Two unequal front windows provide separate firing positions and slightly different angles on the same enemy location.
- Friendly NPCs occasionally use ranged, reload, idle, sit, lay, and hit-react animations.
- When the player approaches a window, its defender steps aside and says a short handoff line before the shooting view opens.
- When the player leaves the shooting view, that defender can return to the window.

### Beat 5: Rifle and ammunition offer

- The guard fox is the house's weapon lender.
- Recommended loan weapon: `frontier-22-lever-rifle`.
- The offer appears before the first sortie if the player has no serviceable firearm or no compatible ammunition.
- The offer also becomes available whenever the player's selected firearm runs out during the quest.
- A prepared player may still voluntarily choose the house rifle from the firing-position setup screen.
- The loan is represented by quest state, not normal inventory. It cannot be sold, dropped, stored, repaired, duplicated, or carried away.
- House ammunition is a separate quest-only pool. The guard supplies one loaded rifle and additional 12-round batches between sorties whenever needed.
- Extra batches are free. Returning to the guard and re-entering the window creates the cost in time and pressure without allowing an ammunition soft lock.
- Personal ammunition is consumed only when the player chooses a personal weapon.
- Loaned ammunition never enters the player's permanent ammunition inventory.
- The rifle is returned automatically when the quest resolves, is abandoned, or the player returns to the origin stop.

### Beat 6: Prolonged defense

- The mission contains three authored phases, each approximately 60 seconds of active defense.
- Phase 1, `Contact`: slower peeks teach enemy tells and window controls.
- Phase 2, `Crossfire`: more simultaneous apertures and incoming impacts encourage changing windows.
- Phase 3, `Break Their Nerve`: enemy exposure becomes less coordinated as morale collapses.
- Defense time advances only while a firing position is actively contested. Waiting safely in the backyard cannot complete the quest.
- Enemy morale falls from confirmed eliminations, suppression, and phase completion.
- Recommended first tuning target: 180 seconds of active defense and approximately 20 confirmed enemy eliminations.
- Both minimum defense time and morale requirements must be met. Numbers remain data values so playtesting can tune them without rewriting logic.

### Beat 7: Retreat and resolution

- Surviving mobs withdraw through doors, behind the freight shed, and along the disused siding.
- Gunfire loses coordination, then stops. No enemies simply vanish while visible.
- Friendly NPCs hold for a short silence before reacting, preventing an abrupt tonal change.
- The player speaks to the homeowner or scout to resolve the quest and claim the reward.
- Recommended reward: goodwill, scrap, a modest ammunition bundle for the player's chosen caliber, and a relationship increase with the scout and defenders.
- The exceptional reward is earned by treating the wounded critter and keeping house pressure below the severe threshold. It must not require perfect aim.
- A return montage places the player at the exact stop and approximate position where the quest began.

## 3. Layered Scene Architecture

### Free-roaming interior draw order

1. Per-window sky and light layer.
2. Per-window distant terrain and atmospheric parallax.
3. Per-window rail field and enemy station base.
4. Enemy actors positioned in station apertures.
5. Distant muzzle flashes, dust, smoke wisps, and retreat actors.
6. The opaque interior shell with transparent window apertures.
7. Persistent wall-impact decals and short-lived plaster or wood particles.
8. Friendly NPC actors and their held-weapon/action sprites.
9. Player actor.
10. Interior lighting, interaction prompts, subtitles, and HUD.

Each window scene is rendered to its own clipped canvas or stencil before the interior shell. This prevents scenery from leaking through the transparent area around the cutaway room. The two windows crop the same world-space scene with a small horizontal offset, so the station remains geographically consistent.

### Shooting-view draw order

1. Sky and distant terrain layers.
2. Rail field and station base.
3. Empty aperture darkness/masks.
4. Hostile target actors.
5. Enemy muzzle flashes and incoming-fire tells.
6. Dust, impact, and retreat effects.
7. Defender window frame foreground.
8. First-person hip-fire or ADS weapon sprite.
9. Reticle, suppression feedback, ammunition, objective, and accessibility indicators.

### Transparency rules

- The interior production shell must have true alpha-zero pixels across both complete window openings.
- No checkerboard pattern may be painted into the file.
- No landscape, clouds, enemy building, bullets, cracks, or impact decals may occupy transparent pixels.
- Damage may touch the opaque frame and sill but must stop at the aperture edge.
- A small dedicated aperture mask should be exported with the shell. Runtime effects use this mask rather than guessing window bounds.
- The clean enemy station background contains no mobs. All enemies remain independent actors.
- The clean backyard and interior contain no NPCs. All friendly critters remain independent actors.

### Data-driven window scenes

A `windowSceneId` selects a scene descriptor containing:

- Sky layer and lighting palette.
- Far-terrain layers and parallax rates.
- Ground or rail-field layers.
- Landmark/building layer.
- Aperture coordinates for enemies.
- Ambient particles and weather.
- Ambient and combat sound profile.
- Two interior window crops.
- Full-screen shooting-view camera framing.

This allows the same transparent interior shell and window renderer to display different locations, weather, times of day, and story conditions without generating another baked interior.

## 4. Animation and Believability

### Friendly NPC states

- Approach/walk.
- Alert idle.
- Sit and rest.
- Lay/wounded.
- Reload.
- Ranged ready.
- Aim and fire.
- Flinch or duck at nearby impact.
- Step away from a window for the player.
- Celebrate cautiously after the retreat.

Friendly shots should use irregular timing. NPCs must not fire continuously, through walls, while reloading, or while the player occupies their window.

### Hostile target states

- Hidden.
- Shadow or pre-peek tell.
- Peek.
- Aim directly toward the viewer.
- Fire.
- Duck.
- Hit reaction.
- Death or incapacitation.
- Retreat.

Every gun-capable target atlas must show the mob facing the player's location with a convincingly foreshortened firearm. Base mob portraits are identity references, not final firing poses.

### Environmental motion

- Slow cloud drift and heat shimmer.
- Light vegetation movement.
- Telegraph wires and hanging signal hardware moving subtly.
- Dust disturbed by missed rounds.
- Randomized distant muzzle flashes tied to actual enemy fire events.
- Short-lived wall splinters, plaster dust, curtain movement, and furniture impact particles inside.
- Lighting flicker from muzzle flashes should be brief and reduced or disabled by flash-safety settings.

No looping effect should reveal an enemy that is currently hidden or continue after the retreat.

## 5. Shooting Mechanics Reuse

The range remains the behavior reference for:

- Owned ranged-weapon discovery.
- Weapon serviceability checks.
- Ammunition type and capacity.
- Reload rules.
- Hip-fire and ADS switching.
- Cursor-following first-person weapon placement.
- Sway and recoil.
- Shot animation sequences.
- Weapon sound profiles.
- Mouse, keyboard, controller, and touch input conventions.

The range's public behavior should remain unchanged. Shared, stable weapon-session behavior should move into a small neutral module used by both activities. Range-specific lobby rows, paper/steel/clay targets, scoring, and rewards stay in `shooting_range.lua`. Siege-specific enemy AI, incoming fire, morale, pressure, and narrative phases stay in the Last Stand module.

Recommended shared module responsibility:

- Create and switch weapon state.
- Resolve ammunition source: personal or quest loan.
- Reload and dry-fire behavior.
- Aim mode, cursor position, sway, recoil, and shot sequence.
- First-person weapon draw placement.
- Sound-profile lookup.

It must not know about range scores or Last Stand quest outcomes.

## 6. Siege Gameplay Rules

### Enemy exposure

- Every firing aperture has a stable ID and screen-space hit region.
- Spawns choose only unoccupied apertures.
- A pre-peek shadow or movement tell precedes exposure.
- Enemies remain visible long enough to identify before firing.
- Several apertures remain empty at all times to avoid visual noise.
- Hit actors complete a readable reaction before being removed.

### Incoming fire and pressure

- Enemy aim is telegraphed through pose, window darkness, and a restrained glint or movement cue, never color alone.
- Remaining exposed after the tell increases suppression and risks damage.
- Ducking, leaving the firing view, changing windows, or eliminating the shooter breaks the threat.
- Incoming rounds select legal impact points on opaque walls, frames, floor, or furniture. Transparent apertures are excluded by mask.
- Pressure affects aim stability, audio muffling, and edge treatment before it affects player health.
- No unavoidable shot may land during scene entry, reload handoff, menus, or reduced-control transitions.

### Window differences

- Broad left window: wider field of view, more apertures visible, greater incoming pressure.
- Narrow right window: tighter field of view, fewer targets, stronger cover, better precision.
- Progress is shared across windows.
- A short cooldown prevents instantly farming the safest aperture pattern by repeatedly opening and closing a window.

### Leaving and resuming

- The player can leave a shooting view at any time and return to the interior.
- Leaving the house does not erase completed phases, elapsed active-defense time, morale damage, or optional-help progress.
- Returning to the origin stop before resolution pauses the quest rather than silently completing or deleting it.
- Re-engaging restores the correct phase, NPC positions, damage state, ammunition source, and surviving enemy pool.

## 7. Persistent Quest State

Recommended saved fields:

```lua
lastStand = {
    version = 1,
    state = "offered",
    originLocation = 0,
    originX = 0,
    originY = 0,
    questGiver = "otter-scout.png",
    windowSceneId = "rail-relay-siege",
    phase = 1,
    activeDefenseSeconds = 0,
    enemyMorale = 100,
    confirmedEliminations = 0,
    housePressure = 0,
    woundedTreated = false,
    loanAccepted = false,
    loanWeapon = "frontier-22-lever-rifle",
    loanLoaded = 0,
    loanReserve = 0,
    rewardClaimed = false,
}
```

State transitions:

`unavailable -> approaching -> offered -> accepted -> escorting -> backyard -> briefing -> defending -> retreat -> resolved -> returned`

`declined` returns to `offered` when the player speaks to the scout again. Save loading must normalize missing or older fields. Reward claims and relationship gains must be idempotent.

## 8. Production Art Still Required

The current concept images should not be loaded directly as final gameplay sprites. Final production exports should be created under `assets/sprites/quests/last-stand/`.

### Environment assets

- Clean rear-house exterior with open, unboarded windows and no NPCs.
- Clean backyard collision/interaction reference.
- Interior foreground shell with true transparent window apertures.
- Interior aperture mask.
- Initial bullet-damage overlay or damage-stage atlas.
- Clean railway relay station with empty apertures.
- Sky, far hills, rail field, and station separated into parallax-ready layers.
- Defender-window foreground frame for the shooting view.
- Optional dusk or storm palette variant through separate scene layers, not a second interior.

### Character assets

- Otter scout approach/walk atlas.
- Guard fox rifle-lending, reload, ranged, and step-aside actions.
- Gecko ranger ranged, reload, and step-aside actions.
- Wounded/resting friendly variants using normal NPC layers.
- Hooded mouse bandit frontal firearm target atlas.
- Cowboy mouse without skull frontal firearm target atlas.
- Tunnel badger raider frontal firearm target atlas.
- Each hostile atlas needs hidden/peek/aim/fire/hit/death/retreat states with consistent anchors.

### Effects and UI assets

- Distant muzzle-flash atlas.
- Plaster, wood, metal, glass, and dirt impact atlases.
- Small smoke and dust atlases.
- Suppression vignette with reduced-flash alternative.
- Window interaction marker.
- House-rifle and house-ammunition UI badges.
- Quest phase and enemy-morale indicators.

## 9. Recommended Code Boundaries

- `game/first_person_shooting.lua`: shared weapon session, aim, reload, sway, recoil, shot sequence, and weapon-view placement.
- `game/shooting_range.lua`: retains range setup, targets, scoring, purchases, stage lengths, and rewards.
- `game/last_stand_quest.lua`: quest state machine, persistence, dialogue decisions, rewards, return location, and loan ownership.
- `game/last_stand_shootout.lua`: phases, targets, hostile fire, pressure, morale, hit resolution, and completion conditions.
- `game/last_stand_scene.lua`: backyard/interior scene setup, window ownership, NPC staging, and scene transitions.
- `game/window_scene.lua`: reusable layered window descriptors, clipping, parallax, animation, and crop cameras.
- `game/assets.lua`: explicit Last Stand asset manifest and lazy animation loading.
- Existing composition, update, input, HUD, interaction, and save modules: minimal wiring only.

The Last Stand modules must expose small `new`, `update`, `draw`, `keypressed`, `mousepressed`, `mousemoved`, `complete`, and `audit` surfaces consistent with existing activities.

## 10. Execution Order

### Gate A: Art lock

- Export clean production assets from approved concepts.
- Confirm true alpha, no painted checkerboards, exact frame sizes, consistent pixel scale, and stable anchors.
- Approve one friendly ranged animation and one hostile target atlas before producing the complete character set.

### Gate B: Shared shooting core

- Extract only stable first-person weapon behavior.
- Keep the existing range API and behavior intact.
- Establish personal-ammo and quest-ammo adapters.

### Gate C: Quest shell

- Add spawn eligibility, approach behavior, offer dialogue, reversible decline, escort transition, persistence, and return transition.
- Add backyard and interior navigation before combat.

### Gate D: Layered windows

- Load scene descriptors and render independent window canvases.
- Add parallax, environmental animation, clipping, NPC window ownership, and transparent shell composition.

### Gate E: Shootout

- Add enemy aperture actors, frontal firearm poses, hit/death states, incoming-fire tells, pressure, phase timing, morale, window switching, and retreat.
- Add the guard-fox loan rifle and unlimited between-sortie emergency batches.

### Gate F: Narrative polish and validation

- Add dialogue barks, wounded-help branch, rewards, audio transitions, reduced-motion/flash handling, mobile/controller affordances, save/resume behavior, and diagnostics.
- Validate the existing shooting range and unrelated stop activities for regressions.

## 11. Approval Criteria Before Coding

- The interior shell contains exactly two usable window apertures with genuine transparency.
- The green couch is absent and both firing zones are clear.
- No bullet hole or debris appears in transparent window space.
- No landscape is baked into the interior shell.
- No friendly NPC is baked into a house background.
- No hostile mob is baked into the enemy station background.
- Friendly designs appear only at the homestead.
- Hostile firearm-capable mob designs appear only at the station.
- Every hostile firing pose looks and aims toward the viewer.
- All character and effect layers have stable anchors and match the game's pixel scale.
- The clean station has enough authored apertures for varied spawning while preserving empty windows.
- The two windows show coherent crops of the same external location.

## 12. Definition of Done

- The scout reliably approaches and offers the quest without interrupting other states.
- Accepting and declining are safe, understandable, and persistent.
- The player can travel to the homestead, explore the backyard and interior, talk to defenders, and use both windows.
- Window scenery is layered, animated, clipped, and selected by location data.
- Friendly NPCs and hostile mobs are always rendered as independent actors.
- Personal firearms and the temporary house rifle both work with hip-fire, ADS, reload, recoil, sound, and cursor-follow behavior.
- A player with no firearm or no ammunition can always continue using the guard fox's rifle and quest-only ammunition.
- The quest cannot duplicate a weapon, leak loan ammunition, grant its reward twice, or strand the player away from the origin stop.
- The firefight lasts long enough to feel like a siege, remains readable, and ends through both time held and enemy morale broken.
- Enemy retreat, friendly reactions, reward, and return transition complete cleanly.
- Saving, quitting, loading, pausing, changing windows, and temporarily leaving the house preserve valid progress.
- Mouse, keyboard, controller, and touch controls remain usable.
- Reduced motion and reduced flashes preserve all required gameplay information.
- The existing shooting range retains its current setup options, target behavior, ammunition purchase, weapon views, and rewards.

