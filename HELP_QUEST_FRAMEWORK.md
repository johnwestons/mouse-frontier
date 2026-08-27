# Shared Help-Quest Session Framework

Stop help now uses one persistent domain model across Windows and Android. Item requests, first aid, and community activities no longer own separate reward or lifecycle rules.

Authored community activities share a three-band progression profile. Stops 1–16 use three rounds and three allowed mistakes, stops 17–33 use four rounds and three mistakes, and stops 34–50 use five rounds with two allowed mistakes. Each band also supplies a regional palette and target arrangement, with mouse and touch hit areas following the visible positions. Sludge containment, track clearing, garden rescue, and wildlife trough care remain separate modules while consuming this one shared rule.

## Lifecycle

Every session moves through the same save-safe states:

`offered → accepted → investigating → active → resolved`

Cancelling a minigame pauses it without discarding its state. Resuming restores its stage and serializable progress values. A failed attempt may reset the activity progress for a clean retry without deleting the accepted quest. Resolved sessions record one of three positive result grades: `assisted`, `successful`, or `exceptional`.

The framework intentionally has no failed or evil alignment state. An unfinished or abandoned attempt awards nothing; it never subtracts goodwill.

## Persistent contract

Save schema version 30 stores sessions in `helpQuestSessions` and optionally identifies the focused session with `activeHelpQuestId`. Each session owns:

- a stable source, stop, NPC, activity kind, and input mode;
- its title, current objective, stage, and total stage count;
- serializable minigame or dialogue progress;
- attempts and pauses;
- its result grade and goodwill amount;
- an irreversible reward-claimed guard.

Older completed requests and community activities import as resolved and already rewarded. This prevents migration from creating duplicate goodwill. Merely discovering an offer does not add it to the active-objective list.

## Integration rules

New sprite minigames and dialogue quests should call `HelpQuest.ensure` when authored content is assigned, then use `accept`, `investigate`, `activate`, `progress`, `pause` or `retry`, and finally `resolve`. Goodwill must be issued through `HelpQuest.claim`; this is what guarantees one award even if a completion callback or save reload occurs twice.

The trail-map objective summary places accepted help before ordinary deliveries and passengers. Both desktop and Android read the same saved session; minigame views may differ in layout, but they may not create platform-specific quest state.

## First branching dialogue quests

Four authored conversations now use that contract: **Missing Family Trail**, **Crop Dispute**, **Bandit Warning**, and **Broken Promise**. Each has three stages, two or three choices per stage, persistent evidence flags, and more than one helpful resolution. Listening carefully and combining relevant evidence can earn an exceptional result; direct compassionate help still produces a successful result, so the player is never forced into a cruel choice.

The assigned NPC remembers the session between conversations and after a save reload. Pausing returns to the stop without erasing choices, completed NPCs provide relationship-aware follow-up dialogue, and goodwill is awarded once through the shared claim guard. Use **1–3** or the large on-screen choices; **Escape/Q** or the pause button safely closes an unfinished conversation. Mouse and Android touch use those same controls and quest state.

## Sludge containment

The sludge-seep stop activity now opens a three-stage visual session instead of resolving with one button. The player reads the animated flow direction to anchor a canvas barrier, packs absorbent moss into three pulsing leaks, then uses the seal and collection tools in a safe order. The generated four-prop atlas is shared by the desktop and Android packages.

Correct steps and mistakes are written into the session after every input. **1–3**, mouse clicks, and touch activate the same targets; **Q/Escape** pauses without discarding progress. Three mistakes end that attempt but consume no resources or goodwill and leave the quest available for a clean retry. Completion clears the damaging slow hazard and awards the normal activity reward exactly once; a mistake-free containment earns the exceptional two-goodwill grade.

## Track-debris clearing

Sharp track debris also uses a three-stage visual session. First, the player marks three unstable piles from the pulsing safe edge inward. Next, each obstruction must be matched to work gloves, a pry bar, or the magnetic spike sweep. Finally, recovered timber, metal, and sharps are routed to their safe destinations before the path reopens. This produces nine decisions rather than an instant completion.

Inspection order, current obstruction, sorting progress, and mistakes persist after every input. The same **1–3**, mouse, touch, pause, retry, exceptional-grade, hazard-clearing, and exactly-once reward rules used by sludge containment apply here. Its generated transparent atlas contains the gloves, pry bar, magnetic sweep, and salvage cart.

Both activities are independent rule/render modules registered through `stop_activity_minigames.lua`. World, HUD, and input code talk only to that coordinator, keeping activity-specific logic out of `main.lua` and preventing a new platform branch for each future minigame.

## Garden rescue and wildlife care

Garden rescue asks the player to distinguish pulsing thorn clusters from healthy growth, match pruning shears, protective gloves, and support stakes to damaged plants, then restore the bed with compost, water, and mulch in root-safe order. The wildlife activity reads three fresh track approaches, removes old feed, scrubs and rinses the trough, then measures small, medium, or large portions for songbirds, field mice, rabbits, and deer.

Each activity contains three stages and nine decisions. Both use `activity_minigame_ui.lua` for hit targets, atlas sprites, panels, feedback, and the shared mistake footer, while their rules remain isolated in dedicated modules. Wildlife food is verified before the session opens and consumed only after successful completion; pausing, mistakes, and retries never waste it. Completing the trough activates the existing wildlife gathering behavior.

## Verification

The deterministic `help_quest_session_lifecycle` smoke checkpoint covers acceptance, investigation, activation, progress persistence, pause/resume, resolution, and duplicate reward rejection. `branching_help_dialogue_quests` additionally verifies the four definitions, evidence paths, resolutions, follow-ups, and shared goodwill rules. The stop-world audit verifies all four authored activity modules, their three stages, nine-decision flows where applicable, persistence, clean completion, three-mistake retry boundaries, keyboard/touch input, protected wildlife food, and all coordinator registrations. Existing item-help, first-aid, save-migration, full-route, and packaged-mobile checks remain required.
