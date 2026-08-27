# Shared Help-Quest Session Framework

Stop help now uses one persistent domain model across Windows and Android. Item requests, first aid, and community activities no longer own separate reward or lifecycle rules.

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

## Verification

The deterministic `help_quest_session_lifecycle` smoke checkpoint covers acceptance, investigation, activation, progress persistence, pause/resume, resolution, and duplicate reward rejection. `branching_help_dialogue_quests` additionally verifies the four definitions, evidence paths, resolutions, follow-ups, and shared goodwill rules. The stop-world audit verifies all three sludge stages, persistence, clean completion, the three-mistake retry boundary, keyboard input, and touch input. Existing item-help, first-aid, save-migration, full-route, and packaged-mobile checks remain required.
