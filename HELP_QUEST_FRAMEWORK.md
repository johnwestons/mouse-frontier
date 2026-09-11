# Shared Help-Quest Session Framework

Stop help uses one persistent domain model across Windows and Android. Item requests, first aid, and dialogue quests share reward and lifecycle rules.

Goodwill rewards remain positive-only and pass through the existing exactly-once claim guard.

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

Older completed requests import as resolved and already rewarded. This prevents migration from creating duplicate goodwill. Merely discovering an offer does not add it to the active-objective list.

## Integration rules

New sprite minigames and dialogue quests should call `HelpQuest.ensure` when authored content is assigned, then use `accept`, `investigate`, `activate`, `progress`, `pause` or `retry`, and finally `resolve`. Goodwill must be issued through `HelpQuest.claim`; this is what guarantees one award even if a completion callback or save reload occurs twice.

The trail-map objective summary places accepted help before ordinary deliveries and passengers. Both desktop and Android read the same saved session; minigame views may differ in layout, but they may not create platform-specific quest state.

## First branching dialogue quests

Four authored conversations now use that contract: **Missing Family Trail**, **Crop Dispute**, **Bandit Warning**, and **Broken Promise**. Each has three stages, two or three choices per stage, persistent evidence flags, and more than one helpful resolution. Listening carefully and combining relevant evidence can earn an exceptional result; direct compassionate help still produces a successful result, so the player is never forced into a cruel choice.

The assigned NPC remembers the session between conversations and after a save reload. Pausing returns to the stop without erasing choices, completed NPCs provide relationship-aware follow-up dialogue, and goodwill is awarded once through the shared claim guard. Use **1–3** or the large on-screen choices; **Escape/Q** or the pause button safely closes an unfinished conversation. Mouse and Android touch use those same controls and quest state.

## Community activity retirement

Water-pump repair, sludge containment, track-debris clearing, garden rescue, and wildlife-trough care have been removed, including their world spots and hazards. The former community minigames' shared coordinator, rules, and sprite atlases are also retired. Existing saves clear retired activity spots and their help-quest sessions, including any active objective for those sessions. First aid, item requests, and dialogue quests remain active.

## Verification

The deterministic `help_quest_session_lifecycle` smoke checkpoint covers acceptance, investigation, activation, progress persistence, pause/resume, resolution, and duplicate reward rejection. `branching_help_dialogue_quests` additionally verifies the four definitions, evidence paths, resolutions, follow-ups, and shared goodwill rules. The `settlement_without_water_pump` checkpoint verifies that the retired activity is absent, and save-migration regression tests verify cleanup of world spots, help-quest sessions, and active objectives. Existing item-help, first-aid, save-migration, full-route, and packaged-mobile checks remain required.
