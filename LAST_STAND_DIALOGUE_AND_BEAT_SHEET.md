# Last Stand Quest: Dialogue and Beat Sheet

## Quest identity

- Quest ID: `last_stand_rescue`
- Display title: `A Light in the Windows`
- Quest type: Approaching-NPC stop quest with a walkable defense location and a
  prolonged first-person shootout.
- Primary quest giver: Otter Scout.
- Rifle and emergency-ammo lender: Guard Fox.
- Second healthy defender: Gecko Ranger.
- Additional residents: Existing friendly NPC sprites assigned to wounded, resting,
  reloading, and lookout role slots after art approval.
- Enemy faction: Gun-capable hostile mobs only.

## Core dramatic promise

The player is not clearing a disposable combat arena. They are entering an ordinary
home whose residents have moved their lives out of the line of fire and are trying to
hold long enough to survive. The shootout should feel distant, dangerous, and
exhausting rather than fast or arcade-like. Quiet conversations between bursts of
gunfire are part of the quest, not interruptions to it.

## Quest state machine

| State | Entry condition | Player control | Exit |
| --- | --- | --- | --- |
| `dormant` | Prerequisites not met | Normal stop play | Prerequisites become true |
| `scout_seeking` | Eligible stop visit begins | Normal stop play | Otter reaches approach radius |
| `offer` | Otter initiates conversation | Dialogue choice | Accept or decline |
| `declined` | Player declines | Normal stop play | Cooldown expires or player talks again |
| `escort_transition` | Player accepts | Cinematic transition | Backyard scene loaded |
| `backyard_arrival` | Transition completes | Walkable backyard | Player completes arrival conversations |
| `interior_briefing` | Player uses back door | Walkable interior | Both firing windows introduced |
| `equipment_check` | Briefing completes | Dialogue and inventory | Usable weapon/ammo confirmed |
| `defense_active` | Player uses either firing window | Shootout controls | Intermission, retreat, or victory gate |
| `intermission` | Phase boundary or forced fallback | Walkable interior/backyard | Player returns to a firing window |
| `final_pressure` | Hold and elimination thresholds near completion | Shootout controls | Enemy morale breaks or position fails |
| `victory_quiet` | Enemy morale reaches zero after minimum hold | Walkable interior | Player checks on residents |
| `reward` | Required post-battle conversations complete | Dialogue and inventory | Reward accepted |
| `return_transition` | Player chooses to return | Cinematic transition | Original stop restored |
| `complete` | Return finishes | Normal stop play | Terminal |
| `failed_fallback` | Position integrity reaches zero | Short recovery scene | Retry from latest phase checkpoint |

## Availability and approach

The quest can trigger only while the player is free-roaming at a compatible stop,
not during another dialogue, transition, minigame, arrest, combat, sleep, or scripted
event. The Otter Scout enters from a valid edge of the stop and walks toward a point
slightly in front of the player. The scout stops outside collision range and calls out
instead of snapping directly into dialogue.

### Approach barks

Use one bark, then begin the offer dialogue when the player faces or interacts with
the scout.

- `Hey! You there. Please, I need a steady paw.`
- `Friend, wait. There are families pinned down past the rail cut.`
- `I came for help. I cannot go back alone.`

If the player keeps walking, the scout follows at a respectful distance without
blocking exits. If the player begins another activity, the scout waits near the stop's
main path and resumes later.

## Initial offer dialogue

### Otter Scout

`Bandits took the old relay building beyond the fields. They have rifles and a clear
line on a house across the cut.`

`The folks inside are holding, but they have wounded in the backyard and not enough
hands at the front windows. I know a covered way to their back door.`

### Player choices

| Choice ID | Player text | Result |
| --- | --- | --- |
| `accept_now` | `Lead the way.` | Begin escort transition |
| `ask_risk` | `How bad is it?` | Explain distance, defenders, and expected duration |
| `ask_supplies` | `What if I am short on ammunition?` | Promise loan rifle and emergency ammunition |
| `decline` | `I cannot leave right now.` | Enter declined state without closing the quest permanently |

### Risk answer

`Bad enough that they cannot run, not so close that the bandits can rush the yard.
The houses are about three hundred meters apart. We need to outlast them and make
their shooters lose the stomach for it.`

### Supplies answer

`The guard inside has a spare lever rifle and a little ammunition. If your own piece
runs dry, ask. Nobody there will let pride get you killed.`

### Decline response

`I understand. I will wait near the trail marker as long as I can. Find me before you
leave if you change your mind.`

## Escort transition storyboard

The transition lasts approximately eight to twelve seconds and hides the location
swap without implying instant travel.

1. The stop audio narrows and the Otter Scout gestures toward the trail.
2. The player and scout walk toward the stop edge using their actual sprites.
3. The screen cuts to layered silhouettes of boots crossing dry grass.
4. A train whistle or signal bell sounds faintly beyond the hills.
5. A distant rifle report interrupts the quiet; birds leave a telegraph wire.
6. The pair crouches through a shallow rail cut while dust drifts across the frame.
7. The rear roofline of the friendly house appears beyond a fence.
8. Control returns inside the backyard gate with distant gunfire already audible.

No character is baked into these transition backgrounds. The player and Otter Scout
remain separate animated sprites throughout.

## Backyard arrival

The backyard initially communicates the cost of the siege without graphic injury.
Wounded residents rest on blankets or against moved domestic furniture. One resident
reloads magazines or loose cartridges. Another carries water. Bullets occasionally
strike only valid solid surfaces on the house or fence, using separate impact effects.

### Otter Scout arrival line

`Back door is still clear. Keep below the windows until we are inside.`

### Optional resident barks

- `They have been firing in bursts. Listen for the pause.`
- `The front room is clear enough to move through, but stay away from the walls.`
- `If you see our guard, tell them we found help.`
- `Water first. Questions when this is over.`

### Required backyard interactions

The player must speak to the Otter Scout and use the back door. Other conversations
are optional and may be revisited during intermissions.

## Interior briefing

The player enters through the back door and sees an ordinary home rearranged under
pressure. Furniture has been moved away from exactly two front windows. Existing
damage appears only on solid surfaces. The changing landscape, relay building,
targets, and flashes remain separate layers visible through the transparent openings.

### Guard Fox greeting

`Scout said you might come. We have two firing windows and not enough healthy paws to
hold both.`

`Pick whichever sight line feels better. You can step away between pushes, speak to
the others, reload, or change windows.`

### Gecko Ranger briefing

`Their upper windows have the clearest rifles. The loading bays hide the heavier
shooters. Do not waste rounds on a shadow that has not committed to the opening.`

### Window introduction prompts

- Window A prompt: `Hold position at the wide window`
- Window B prompt: `Hold position at the narrow window`
- Back-away prompt: `Leave the firing position`

The two windows use different foreground surrounds and target-slot weightings, but
share the same battle state. Changing windows must never reset elapsed time, enemy
morale, eliminated enemies, ammunition, or position integrity.

## Equipment check and loan rifle

The equipment check runs before the first firing interaction and whenever the player
returns from an intermission.

### Player has a usable firearm and ammunition

Guard Fox: `Use what you know. I will keep the spare close in case yours runs dry.`

### Player has a firearm but no compatible ammunition

Guard Fox: `Empty does us no good. I can spare a small batch for that piece. If it
runs out again, call to me.`

### Player has no usable firearm

Guard Fox: `Take my spare. Frontier Twenty-Two, lever action. It is not fancy, but it
shoots straight.`

Player choice: `Borrow the rifle` or `Check my equipment again`.

### Emergency ammunition handoff

Guard Fox: `Fresh rounds. Make them count, but do not hoard them while the windows are
hot.`

The loan item is `frontier-22-lever-rifle`. It is quest-bound, cannot be sold, stored,
dropped, or retained, and is removed or returned during resolution. Emergency quest
ammunition is issued in small batches between waves or after the current weapon
reaches zero reserve. The handoff never occurs while a firing animation is active.

## Defense structure

### Baseline tuning target

- Minimum hold time: 180 seconds of active defense time.
- Required player eliminations: 15.
- Enemy morale: 100 at the beginning of the defense.
- Standard elimination morale loss: 4.
- Heavy enemy elimination morale loss: 7.
- Sustained allied suppression event morale loss: 1.
- Maximum intended defense time: 240 seconds before assistance tuning increases.
- Intermissions pause active-defense time and enemy attacks.

Both the minimum hold time and elimination requirement must be met before the enemy
can fully flee. Enemy morale controls pacing and intensity, not a hidden substitute
for the player's required eliminations.

### Phase 1: Finding the rhythm

- Duration window: 0 to 45 seconds.
- Active apertures: Two to three.
- Enemy types: Mouse bandits and cowboy mice.
- Teaching goal: Peek, expose, fire, duck, and visible defeat sequence.
- Allied behavior: Gecko fires occasionally to establish that defenders are active.

### Intermission 1

Guard Fox: `That bought us a breath. Check your ammunition and anyone in the yard.`

The player can walk, speak, switch equipment, receive ammunition, or immediately use
either window.

### Phase 2: Crossfire

- Duration window: 45 to 105 seconds.
- Active apertures: Three to four.
- Enemy types: Mouse bandits, cowboy mice, and the first tunnel badger.
- Pressure change: Shorter aim warnings and occasional simultaneous shooters.
- World change: New valid impact decals appear on solid interior surfaces.

### Intermission 2

Gecko Ranger: `They are moving shooters through the loading bays. The upper floor is
still their best angle.`

An optional resident conversation reveals why the house matters and reinforces that
the occupants are civilians rather than a militia.

### Phase 3: Holding under pressure

- Duration window: 105 to 165 seconds.
- Active apertures: Four to five with controlled overlap.
- Enemy types: All three hostile atlases.
- Pressure change: More frequent heavy enemies, near-miss tracers, and dust impacts.
- Relief rule: If reserve ammunition is empty, the phase yields a safe handoff window.
- Integrity rule: Incoming hits reduce position integrity only after a readable aim
  tell and only while the player remains exposed.

### Phase 4: Breaking their nerve

- Earliest start: 165 seconds.
- Victory gate: At least 180 active seconds and at least 15 player eliminations.
- Presentation: Enemy fire becomes less coordinated as morale drops.
- Final push: A small deliberate group exposes from upper windows and loading bays.
- Victory cue: Surviving hostiles fire a disorganized final burst, then withdraw from
  apertures while distant movement and dust imply retreat.

If the hold threshold is met before the elimination threshold, exposed targets become
more readable and remain available longer. If eliminations are met early, pressure
continues until the minimum hold time without inventing extra required kills.

## Damage, pressure, and fallback

The player is threatened through `position_integrity`, not instant random damage.
Every damaging shot requires an enemy aim tell, a muzzle flash, travel cue, and valid
impact response. The player avoids damage by firing first, leaving ADS, ducking, or
backing away from the window.

If integrity reaches zero, the player is forced away from the window into a short
recovery scene. The quest enters `failed_fallback`, restores a limited amount of
integrity, offers emergency ammunition, and restarts only the current phase from its
checkpoint. Elimination count, conversations, borrowed equipment, and completed
earlier phases remain saved. The quest cannot become permanently failed or softlocked.

## Ambient defender behavior

- Guard Fox occupies the window the player is not using when available.
- Gecko Ranger alternates between aiming, firing, reloading, and stepping clear.
- Allied shots use separate flashes and audio but do not steal the player's required
  elimination credit.
- Allied suppression can reduce enemy morale slowly, preventing a stalled battle
  without bypassing the required player eliminations.
- Wounded residents never stand in firing lanes.
- Interior and backyard NPC positions are restored consistently after every
  minigame transition.

## Victory quiet

When the enemy breaks, gunfire does not stop at one instant. It falls apart over four
to six seconds: fewer reports, one distant shouted retreat cue, a final dropped object
or closing door at the relay, then wind and house creaks. The HUD fades before control
returns to the room.

### Gecko Ranger

`They are leaving the windows. Hold a moment. Make sure it is real.`

### Guard Fox

`That is it. They have broken for the tracks.`

### Otter Scout

`You gave us the minutes we did not have.`

The player must check on at least one resident and speak to Guard Fox before reward.

## Reward and equipment return

### Guard Fox with borrowed rifle

`I will take the spare back. It did right by you.`

### Guard Fox with player's weapon

`You came prepared and still shared the danger. I will remember that.`

### Reward package

- Scrap reward scaled modestly by completed optional resident conversations.
- A fixed reputation or goodwill gain with the rescued residents.
- A small supply item from the household rather than military loot.
- Optional later stop encounter or letter confirming the household recovered.

No reward depends on perfect accuracy. Accuracy, damage taken, ammunition spent, and
optional conversations may change closing remarks without withholding quest completion.

## Return choice

### Otter Scout

`I can take you back by the same covered trail whenever you are ready.`

Player choices: `Return to the stop`, `Stay a little longer`, or `Ask what happens
next`.

The player may revisit both the backyard and interior before leaving. Once return is
chosen, the transition mirrors the approach at a calmer pace and restores the player
at the original stop near the trail marker, with normal control, camera, audio, and
inventory state.

## Persistence requirements

- Save the current quest state, completed phase, active-defense time, eliminations,
  enemy morale, position integrity, window choice, dialogue flags, and loan state.
- Save before entering every shootout phase and after every phase completion.
- Loading inside the quest restores the player to a safe walkable location, never
  directly into an unavoidable incoming shot.
- Loading while a loan rifle exists restores the quest-bound item exactly once.
- Completing or abandoning through a supported resolution removes the loan and any
  unused quest-only ammunition exactly once.
- Returning to the original stop restores the correct stop scene and does not respawn
  the approaching Otter Scout.

## Content acceptance checklist

- The Otter Scout visibly approaches instead of appearing in a dialogue box.
- Declining does not permanently lose the quest.
- The escort transition communicates distance and following the scout.
- The backyard reads as a normal home's rear yard under pressure.
- The interior reads as a normal home with furniture moved, not a barracks.
- Exactly two distinct firing windows are available.
- Window scenery remains replaceable and animated through separate layers.
- Guard Fox offers the loan rifle or ammunition before a softlock can occur.
- The defense requires both time held and player eliminations.
- Walking, conversations, reloading, and window switching remain meaningful between
  battle phases.
- Hostiles aim toward the viewer and occupy only masked enemy-building apertures.
- Victory uses an audible and visual collapse of enemy morale rather than an abrupt
  score screen.
- Reward, loan return, and stop restoration complete without duplicating or deleting
  the player's permanent equipment.
