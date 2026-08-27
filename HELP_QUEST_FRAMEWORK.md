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

## Verification

The deterministic `help_quest_session_lifecycle` smoke checkpoint covers acceptance, investigation, activation, progress persistence, pause/resume, resolution, and duplicate reward rejection. Existing item-help, first-aid, stop-activity, save-migration, full-route, and packaged-mobile checks remain required.
