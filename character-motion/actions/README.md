# Authored character actions

Each resident/player character receives six authored frames for sitting,
lying down, melee, ranged, item use, hit reaction, collapse and unconscious
breathing. The seven previously static legacy idles also receive six frames.
Existing directional locomotion and the chore strips retain their artwork.

`generation-prompts.json` records the exact built-in ImageGen prompts and
original paths. `orientation-repairs.json` records the subsequent facing repairs
and takes precedence for its named actions. Active sources are copied into `output/character-actions/sources`;
discarded studies are marked explicitly. Most characters use two four-row
atlases, each with six columns. `actions` records each source's row order.

Stage a set with:

```powershell
python tools/build_character_action_assets.py --only character-name
```

The builder separates complete silhouettes without erasing visible colors,
matches the immutable upright reference scale and baseline in `framing/`,
and writes staged strips, contrasting contact sheets, 1×/half-speed GIFs,
and audit findings under `output/character-actions/<character>`.
Sitting, lying and collapse intentionally change body height; their frames
share a source scale rather than being enlarged to the same bounding box.

After visually reviewing every frame and the playback, install the exact
reviewed staging files:

```powershell
python tools/build_character_action_assets.py --install-reviewed --only character-name
```

Installation verifies source, strip and evidence hashes. `acceptance.json`
records the reviewed result and drives `game/character_action_profiles.lua`.
Runtime action frames are 512×256, six per horizontal strip. Mobile packaging
preserves complete cells, and character body scale follows the decoded height.

Sitting/lying play four transition frames, then alternate the final breathing
poses. Standing reverses the transition; movement may interrupt it. Melee,
ranged and use play once over the existing action timer. Hit and collapse
play once, and a downed actor then breathes in the unconscious loop. Held
weapons use the same frame sampler and reviewed normalized hand points.

`tools/character-action-smoke/run.ps1 -Mode both` renders every installed
action through real LÖVE decoding, quads and the production renderer in
desktop and mobile layouts. Its isolated QA identity does not touch game saves.
Captures and reports are in `.stabilization/character-action`.

The completed roster contains 55 characters, 447 strips and 2,682 authored
frames. The desktop and mobile layout runs each passed 10,333 checks.
`tools/tests/test_character_action_assets.py` verifies roster coverage, reviewed
hashes, six unique complete frames per action, and unchanged chore artwork.
Playback tests cover lowering, resting, rising, interruptions, collapse,
held-item synchronization, mobile cell scaling and the traveler profile preview.

Example motion on a checker background is available in
`output/character-actions/action-preview-1x.gif` and
`output/character-actions/action-preview-half-speed.gif`. These previews
assemble the installed authored frames; they do not create replacement art.
The traveler profile retains its preview actor and repeats one-shot actions
with a pause, so action selection demonstrates the whole sequence.

The orientation review covered all 55 action suites. Sixteen characters received
replacement collapse/resting sequences with a consistent view, including the
affected lying and hit poses. Cook Frog's full eight-action suite was repaired.
All replacement frames were reviewed over light and dark backgrounds before
installation. Facing is held from the start of a collapse until recovery;
explicit direction selection in the viewer starts a fresh preview actor.

The viewer derives its action list from the loaded character set. Sweep, carry
and tend appear with the other eight actions. Directional locomotion shares
the direction controls; extra registered animations remain individually
selectable, with overflow pages. Chores retain their authored tool view and
fit the complete tool stroke beside the profile. The real-engine smoke also
checks every character's viewer controls and captures both layout variants.

The orientation/viewer update passed 50 focused playback, input, asset, chore,
battle and streaming tests, plus LuaJIT syntax checks for 326 game/QA files.
A previous broader mobile test run has an unrelated pre-existing intro-train anchor assertion that
expects a literal rail ratio instead of the current `Train.railRatio` value.
