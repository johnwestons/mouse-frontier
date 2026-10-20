# Stop 5 Badlands expedition walk masks

| Map image | Editable mask |
| --- | --- |
| `badlands-approach-background.png` | `walkmask-badlands-approach.png` |
| `redwash-basin-background.png` | `walkmask-redwash-basin.png` |

Both masks are opaque 1672 × 941 PNGs in the same native coordinates as the artwork. White allows the player's feet to pass; black blocks cliffs, rocks, and dense scrub. The player needs six pixels of clearance around their feet. The approach starts below the wooden entrance gate and bends around the central rock face; its supply-cache interaction is on the ground below the tent.

Both maps' paths and clearings are 30% wider than the initial traced layout, as requested for easier movement. Their centerlines and the six-pixel foot clearance stay the same.

The user's red-marked extensions are stored as additive `walkRegions`: 13 on the approach and 12 in the basin. Each polygon follows the marked boundary, and its interior navigation nodes connect it to the original paths. The builder unions these regions with the existing paths; the same polygons are available to headless collision checks.

Redwash Basin follows the painted channel and low banks from the bottom entrance to the arch exit. The high terraces are separated by sheer cliffs, so the cairns are surveyed from marked viewpoints on reachable ground. The flood closes one sandy bend; the gravel-bank detour keeps the exits, viewpoints, and caches connected. Interaction IDs and collected progress remain unchanged.

Keep the approach return, both basin exits, survey points, caches, mob patrols, and flood detour connected. Trace the visible ground in `game/expedition_areas.lua`, then regenerate its collision mask and inspect the overlay against the artwork:

```powershell
python tools/build_expedition_walkmask.py --area stop05-badlands-approach --preview-dir .stabilization/walkmask-alignment
python tools/build_expedition_walkmask.py --area stop05-redwash-basin --preview-dir .stabilization/walkmask-alignment
```

The builder needs the test dependencies in `tools/requirements-test.txt`. It updates only the selected mask, never the background artwork. Both the PNG and the Lua route geometry must stay aligned; geometry-only tests cannot detect a path traced over a painted cliff. `tools/tests/test_expedition_asset_walkmask_behavior.py` loads the shipped PNGs to check visible trail anchors, movement, interactions, patrols, and flood-safe routes.

Restart the game after changing a mask; loaded collision images are cached. Rebuild a mobile package to include the changed masks on a device.
