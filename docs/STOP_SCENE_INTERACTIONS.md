# Stop scenery interactions

The 50 ordinary stop paintings have 85 authored points: 50 environmental inspections and 35 harvest containers. The introductory home yard keeps its own actions.

- Approach a marker and press **E**, click it, or use the contextual touch/controller action.
- Gardens, greenhouses and planted beds open the familiar chest/backpack interface. Drag crops into the backpack; desktop players can also Shift-click to transfer.
- Gardens start with three carrots. The orchard at stop 28 starts with three apples. Contents persist per stop, including empty containers; revisiting does not replenish them. There is no timed regrowth system.
- Inspection points open a description with a Close button. These are environmental descriptions, not character speech or NPC conversations.
- Co-op players share harvest contents through the existing host-authorized inventory commands. Inspection panels are local to each player.

## Authoring and validation

`game/stop_hotspots.lua` contains the points and descriptions. Coordinates in the definitions refer to a 640 × 480 preview of each painting and are converted to the game's 960 × 720 world. Keep harvests within 75 world pixels of a walkable approach. An inspection may have a longer explicit radius for scenery beyond a fence or waterway.

Harvest IDs identify permanent containers in `droppedItems`; retain an ID when moving an existing point so its saved contents survive. Never seed contents based on whether a container is empty.

Run `python tools/audit_stop_hotspots.py` to check the real collision masks and generate annotated contact sheets in `.stabilization/stop-hotspots`. Behavior tests are in `tools/tests/test_stop_hotspot_behavior.py`, with guest input coverage in `test_coop_guest_view_behavior.py`.
