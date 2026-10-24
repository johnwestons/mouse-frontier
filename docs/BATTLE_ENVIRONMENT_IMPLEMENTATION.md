# Large tactical battle environment implementation

New encounters are turn based crossings on a 72 by 40 procedural battlefield: 2,880 tactical spaces, four times the reviewed 720-space native preview and 48 times the original 60-space board. New hard maps normally retain 2,432 walkable spaces after 448 blocking cells. Connectivity checks and a bounded fallback guarantee at least 2,400 reachable spaces.

The current refinement adds population, patrols and building compounds to the larger map with persistent fog and adjustable draw distance. The [concept study](concepts/battle-environment-study/REPORT.md) remains an art and feasibility reference; its browser mockup is not the game renderer.

## October 24 population and scenery refinement

- Ordinary crossings have six groups: 12 enemies on easy, 18 on medium, and 24 on hard. The groups are spread across the north, center and south approaches. Enemy statistics are unchanged; avoiding a group remains an option. Boss, event, expedition and nonstandard-HP scripted encounters keep their assigned rosters.
- Passive patrols move together once per round rather than spending individual idle turns. Sight and near-field hearing trigger group pursuit; shots can attract nearby groups. At most two groups pursue simultaneously. Enemies navigate around walls, search a remembered location for three rounds, then resume patrol. They cannot track a hidden player's current position. The host saves and replicates their patrol and search state.
- Twelve seed-varied ruined houses have five-to-seven by four-to-six-space footprints, level foundations, working entrances, collapsed sections, window openings, hearths, chimneys, roof beams, weathered floors and rubble. Walls are real shared blockers. Interiors remain clear of randomly placed obstacles. Decoration quality does not alter collision or cover.
- The ordinary scenery budget is now 384/416/448 blocking cells by tier. The 100-seed hard-map check found no empty fallback maps, while existing reachability tests continue to require all three routes and at least 2,400 reachable cells.
- Each crossing uses no more than three enemy sprite families, reusing animation atlases across the larger roster. The mobile-asset desktop profile measured about 107.3 MiB of total texture allocation, a 3.36 ms map-generation P95, and 0.63–1.14 ms warm draw CPU-submission P95 across six views. These are desktop measurements with mobile assets, not phone frame pacing. Low-detail cache retention stayed at 28 chunks.
- Native rendering passed 65 reference checks, 93 production desktop checks and 95 production mobile-layout checks. The reference contained 182,997 high-detail and 63,683 low-detail triangles before fog culling. See `output/battle-terrain/population-final-focused.log`, `population-compat.log`, `population-regression-final.log`, `population-packaged-mobile-profile.log` and `population-native.log` for the current audit results. New behavior tests cover real host pursuit commands, remembered positions, pursuit-group limits, legal patrol routes, doors, foundations, save rejection and compact replication.

The update is configured as Android **0.7.0-mobile.51**, campaign schema **49**, and co-op protocol **33**. New fields use geometry version **3**. Previous 72-by-40 version-2, 36-by-20 version-1, and flat saves retain their pending battles. New scenery and population appear when a new encounter is generated; a resumed fight keeps its layout. Update both Local Play peers together.

![Ruined-house compounds in the actual native renderer; fog disabled for inspection](../output/battle-terrain/native-house-detail.png)

The remaining sections preserve the October 22 implementation and benchmark evidence where explicitly dated; current population and version information is above.

## Integrated behavior

| Area | Current implementation |
| --- | --- |
| Journey and extraction | Every surviving participating player must reach the eastern exit. Killing ordinary enemies alone does not finish the operation. Boss and defense battles also require their designated threats to be defeated. Fallen players are carried out and revived through the existing result flow. NPC followers cannot block extraction or keep a defeated player party alive. |
| Routes and elevation | Continuous triangular terrain supports hills, uphill movement costs, terrain sight blocking, a central route, two flanks, and three cross-connections. Movement follows a legal reconstructed route instead of interpolating through cover. |
| Encounter pacing | Ordinary enemies occupy six patrolling groups, with at most two groups pursuing at a time. Passive groups advance together once per round. Clear ground allows longer march moves; nearby threats restore tactical movement budgets. |
| Camera | Device-local 360-degree orbit, 20–85 degree tilt, zoom 0.05–3.5, unconstrained pan, unit focus, full-map framing, and terrain ray picking. Right-drag orbits; middle/Shift-drag pans; the wheel zooms. Q/E orbit, brackets tilt, O frames the map, and Home focuses. Touch supports pinch zoom and camera toolbar controls. |
| Screen space | The battlefield expands across the actual widescreen viewport. Objective, actions, and toolbar stay fixed during camera movement. Mobile reserves space for its pause control. |
| Characters | Existing directional critter art is sampled onto camera-facing cutout planes. Facing accounts for camera rotation; gait phase follows traveled world distance. No dialogue or weapon art is generated or rewritten. |
| Compatibility | Saved flat 60-space battles retain their dimensions and completion rules. Prior 36 by 20 and 72 by 40 native fields remain supported. New fields use geometry version 3. Campaign schema is 49; co-op protocol is 33. Both devices need the matching build. |

## Fog and options

`game/battle_fog.lua` computes shared sight from living allies with an eight-space circular radius. Terrain and solid cover can block sight. Unexplored ground is hidden. Explored ground remains dimly visible when rendered. Enemies outside current sight are absent from sprites, labels, minimap markers, inspection, and target controls. The host rejects hidden-target attacks without charging ammo or advancing the turn.

Exploration is saved as a 720-character hex bitset for all 2,880 spaces. Long moves reveal the traveled route as well as the destination. Exploration survives saves, reconnects, and replica updates. Fallen allies stop scouting. Visibility calculations are cached across guest presentation wrappers instead of being repeated every frame.

Options → Graphics offers 10, 14, 20, and 28-space terrain draw distances, plus AUTO. AUTO selects 10 on mobile and 14 on desktop. This preference saves in `local-preferences.txt` on the device. It does not change a campaign, submit gameplay commands, or alter tactical sight. Guest settings expose the same controls. Both players retain identical gameplay sight rules regardless of quality settings.

The minimap remembers exploration outside the terrain draw radius. It marks the eastern destination while the intervening environment remains unexplored. Panning the camera does not scout terrain.

## Rendering and resource use

`game/battle_renderer3d.lua` uses LÖVE meshes, depth testing, a surface atlas, and reusable solid scenery. Terrain and props are divided into six-space chunks. Detailed meshes are built on demand for explored chunks within both the party draw radius and the camera viewport. Unvisited distant regions do not allocate detailed meshes.

The normal cache retains up to 40 chunks on desktop and 28 at low detail. Currently visible chunks can exceed that retention limit: the deliberately explored, maximum-distance overview used 69 chunks. Older unseen chunks are released. The shader hides unexplored terrain, dims explored terrain outside current sight, and fades the draw boundary. CPU culling avoids submitting distant or entirely unexplored chunks. Mobile lowers decoration density and uses a 0.75-resolution render canvas with logical input coordinates.

Construction is spread over frames, with at most three new chunks per desktop frame and two at low detail. A time budget stops additional builds between chunks; an individual chunk can exceed that budget. The nearest needed chunks build first, and the interface briefly shows a loading indicator while work remains. Leaving a battle releases its meshes, fog texture, and render targets.

The revised surface kit has worn paths, gravel, grass, stone, timber, rust, and brick. Solid props add ruin openings and roof beams, car windows and wheels, open rail carts, leafy trees, rocks, debris, and terrain-following contact shadows. Four biome variants share these reusable pieces. The independent full-map fixture measured 159,239 high-detail triangles and 48,471 low-detail triangles; ordinary fog-limited gameplay submits a portion of those totals.

Geometry and obstacles occupy a separate reliable `battlefield` replication domain. Turn updates send actors, actions, and exploration without resending unchanged terrain. Flat tile arrays required by legacy accessors are reconstructed deterministically on the receiver. Cameras, visibility textures, decorations, GPU meshes, and quality preferences are never synchronized.

Measured in the two-player easy-encounter fixture (`output/battle-terrain/packet-evidence.json`):

| Measurement | Bytes |
| --- | ---: |
| Initial full campaign snapshot | 42,970 |
| Static battlefield record | 33,093 |
| Initial combat record | 3,765 |
| Move update | 5,447 |
| Canonical height string | 5,986 |
| Exploration bitset | 720 |

Before the static-domain change, the same move update was 191,354 bytes. These are serialized fixture sizes, not physical network latency measurements.

## October 22 verification evidence

- Field tests cover three routes and at least 2,400 reachable spaces across 100 seeds, deterministic generation, malformed geometry, fallback generation, weighted paths, hill occlusion, and picking across camera azimuths, tilts, and zooms.
- Fog tests cover hidden-target rejection without costs, route exploration, save/reload, shared sight, fallen scouts, ridge occlusion, local preference persistence, cached guest visibility, static-domain omission from moves, reconnect reconstruction, and previous native geometry compatibility.
- Production native screenshot/control smoke: 93 desktop checks and 95 simulated-mobile checks, through the real battle screen and Options callbacks. The mobile run used the optimized package assets. On a partially explored map, reducing draw distance from 28 to 10 cut submitted terrain chunks from 13 to 7. Initial exploration did not build the whole map. Mobile pinch changed the camera without issuing a unit action.
- Native presentation checks cover authored projectile sprites, simultaneous status labels, personal ammo and equipment inspection, scrollable battle history, hidden-enemy focus rejection, overlay input capture, high contrast, and the largest accessibility text at 960, 1,280, and 1,560 pixels wide.
- Final integrated playthrough smoke passed 110 desktop and 117 simulated-mobile checkpoints with the larger field and fog, including movement inputs through far-side extraction. Both the source mobile run and the optimized `.love` archive passed. Earlier failed attempts remain in the output directory; use the final evidence paths below.
- Updated zoom/HUD smoke passed 350 checks and produced its required 20 screenshots, including the native battlefield’s fixed HUD and inverse picking.
- The independent renderer fixture passed 61 checks covering shader/canvas restoration, geometry reuse across equivalent co-op tables, camera angles, picking, and reduced low-detail geometry. Its full-map reference deliberately disables fog for generation inspection; normal gameplay keeps fog enabled.
- The final full repository regression audit passed all 2,190 tests with no skips. This includes legacy flat-board saves, prior native fields, large-field crossings, exploration persistence, malformed saved routes, and compact replication.
- Real two-process ENet co-op passed with desktop assets and with optimized mobile assets/touch callbacks. The fixtures verify independent inventory/ammo, failed-save retry without double charges, reconnect, result settlement, and host-only continuation. A separate host process restart restored the battle from disk and reconnected the guest. These are two Windows processes, not a physical phone network test. The result-specific fixture stages actors near extraction; full-map traversal is separately covered by real command and playthrough tests.
- The optimized mobile archive passed the shared-source package audit: 365 Lua files, campaign schema 48, and co-op protocol 32. Both co-op devices must use the matching source identity.
- Release-50 preparation passed the 113-checkpoint full-route scenario, including all 49 charged departures and arrivals, a mid-route disk resume, and ending persistence. This provisioned route scenario marks interruptions handled; natural combat is covered separately. Expedition integration passed all 14 staged captures and transition assertions on both desktop and mobile layouts. Its fixture now completes the normal home departure before moving to the expedition stop, and the route fixture uses the current action-menu travel control.

Outputs and screenshots are in `output/battle-terrain/`. Fixtures use isolated disposable profiles rather than the user’s campaign saves.

## October 22 performance evidence and device acceptance

The production profiler ran the actual battle draw path on an NVIDIA RTX 3050 with OpenGL 3.3. Each case warms the renderer and records 90 draw submissions. These measurements establish desktop costs and relative quality behavior; they do not establish phone FPS.

| Measurement | Desktop source assets | Optimized mobile assets on desktop |
| --- | ---: | ---: |
| Generation, 24 maps, P95 | 3.79 ms | 4.07 ms |
| Visibility update, 24 changes, P95 | 0.95 ms | 0.53 ms |
| Warm draw CPU submission, P95 range across six views | 0.64–1.03 ms | 0.70–0.83 ms |
| First cold draw, maximum | 30.30 ms | 8.44 ms |
| Retained chunks after 12 camera moves | 40 | 28 |
| Near-view mesh allocation, distance 10 | 3.98 MiB | 1.18 MiB |
| Max-distance overview mesh allocation | 16.53 MiB | 4.59 MiB |
| Texture allocation in measured battle cases | 228.03 MiB | 111.30 MiB |

Texture allocation includes the application's characters and interface, rather than terrain alone. Mobile packaging reduces existing character sheet dimensions while preserving authored frames. The cold desktop spike remains a reason to measure real device frame pacing; incremental terrain construction limits subsequent work rather than promising every frame is below budget. The profiler's `batchWithReadbackMs` field amortizes a batch plus one canvas readback and must not be interpreted as individual GPU frame time.

Implementation acceptance is complete for the enlarged environment, fog and options, native presentation, regression suite, local co-op, and package source parity. No character dialogue or weapon art was changed. The art kit is a reusable procedural foundation and remains open to later aesthetic revisions.

`adb devices -l` found no connected device on October 22. Physical Android frame pacing, memory pressure, thermal behavior, and phone-to-PC co-op acceptance remain unverified. No physical-device release-readiness claim is made.

## Final evidence and previews

| Evidence | Path |
| --- | --- |
| Full regression audit | `output/battle-terrain/regression-release.log` |
| Desktop integrated playthrough | `output/battle-terrain/release-desktop.rpt` |
| Source mobile integrated playthrough | `output/battle-terrain/release-source-mobile-confirm.rpt` |
| Packaged mobile integrated playthrough | `output/battle-terrain/release-mobile.rpt` |
| HUD and camera audit | `output/battle-terrain/release-zoom.rpt` |
| Desktop production render/profile | `output/battle-terrain/production-run-507287f97acc461a8f1f1fd187331333/result.txt` |
| Packaged mobile production render/profile | `output/battle-terrain/production-run-7deafed83a634cdabe99ff0c65892ea9/result.txt` |
| Renderer and geometry audit | `output/battle-terrain/native-result.txt` |
| Standard desktop co-op | `output/battle-terrain/lan-native/run-c285e73b6c484b56b6359e36322044e5/` |
| Mobile-asset co-op | `output/battle-terrain/lan-mobile-native/run-6a0f8fc1ea9e444fa97bc59847716e0b/` |
| Host disk restart co-op | `output/battle-terrain/lan-native-restart/run-272405b9cf8b4507a93b11679f3c05d9/` |
| CPU, allocation, and cache measurements | `output/battle-terrain/production-profile.json`, `mobile-production-profile.json` |
| Mobile package and source verification | `output/mobile/battle-environment/build-report.json`, `output/battle-terrain/release-package-audit.json` |

The implementation-stage game archive is `output/mobile/battle-environment/mouse-frontier-0.7.0-mobile.49.love` (349,050,678 bytes). Its SHA-256 is `67992bcb653ddf6f8d5bb4455f77f8d4e005fb68e2a188705ba8689f5b62d246`. This historical verification archive is for the LÖVE runtime, not an installed Android APK.

The October 22 update was distributed as **0.7.0-mobile.50**, with version code **50**, to update build 49. Its historical release is `v0.7.0-mobile.50`, protocol 32/schema 48. The October 24 refinement above supersedes it with build **51**, protocol **33**/schema **49**. Build from clean source with `BUILD_ANDROID.ps1 -SkipDeviceProbe`; archive, signing, embedded-source and ABI evidence goes into `output/mobile/build-report.json` and `output/mobile/apk-report.json`. Physical-device acceptance remains separate from package verification.

![Native battle screen with party fog](../output/battle-terrain/production-default.png)

![Solid scenery detail, fog disabled for inspection](../output/battle-terrain/native-entry-detail.png)

Additional captures include `native-overview.png`, `native-biome-1.png` through `native-biome-4.png`, `production-fog-explored.png`, `production-fog-short.png`, `production-unit-info.png`, and `production-accessible-info-960.png` in `output/battle-terrain/`.

## Useful commands

```powershell
$env:LUA_RUNTIME_PYTHONPATH=Join-Path (Get-Location) '.stabilization/python-deps'
$env:PYTHONPATH=Join-Path (Get-Location) 'tools/tests'
python -m unittest test_battle_field_behavior test_battle_operation_behavior test_battle_fog_behavior
python tools/run_tests.py
./tools/run_battle_production_smoke.ps1
./tools/run_battle_production_smoke.ps1 -Mobile
./tools/run_battle_production_smoke.ps1 -Mobile -Profile -GameRoot output/mobile/battle-environment/stage
./tools/run_smoke.ps1 -ReportPath output/battle-terrain/fog-desktop.rpt
./tools/run_smoke.ps1 -Mobile -ReportPath output/battle-terrain/fog-mobile.rpt
./tools/run_zoom_smoke.ps1 -ReportPath output/battle-terrain/fog-zoom.rpt
```

Python checks use Lupa under `.stabilization/python-deps`. Native smoke scripts require the installed LÖVE runtime. Graphics generation and local camera settings never influence authoritative battle RNG.
