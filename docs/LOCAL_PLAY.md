# Mouse Frontier Local Play

Local Play is in development. It supports one host and one companion using ENet on a local network. Combat, independent shooting-range courses, save retry and reconnect have bounded desktop and simulated-touch evidence. Physical Windows-host/Android-guest tests passed discovery, joining, guest movement, inventory, maintenance and reconnect on build30. Build31 also passed the event-to-town transition, returning to the train and a private map check. Memory remains high; the observation ended when ADB lost the device before the required 30 minutes. Stability and the remaining device matrix are unfinished. Use matching packages documented in [package evidence](COOP_PACKAGING.md).

## Host a journey

1. Open **Local Play** with **F8** or its menu control from the save-selection screen.
2. Choose **AUTO**, **WI-FI** or **USB TETHER**. The menu shows detected local adapter addresses. The default game port is **22124**; change the hosting port if needed.
3. Select **Host saved journey**, then **Continue** on the save you want to share. Hosting starts before the first world update, preserving the saved co-op scene and firing phase.
4. Your friend can find the advertised journey or enter your local IPv4 address and game port.
5. Approve the first companion request. Rejoining with that companion's saved credential resumes the existing character.

You can also load a journey normally, open Local Play and select **Start hosting**. Normal solo loading retains its existing restoration behavior; for an exact saved Last Stand firing phase, use **Host saved journey**. If startup fails, **Retry hosting** retains that entry state. **Continue solo** cancels the hosting request and permits ordinary offline restoration. Finish any failed critical save through **Retry Save** before retrying hosting.

The journey remains the host's save. Host and companion equipment, health, ammunition and character progress are stored separately inside it. Guests do not receive a writable campaign copy.

## Join a friend

1. Return to the title/save-selection screen, then open **Local Play**.
2. Enter your name and choose a companion traveler for first enrollment. Reconnecting resumes the traveler already saved by the host.
3. Choose a connection mode:

| Mode | Behavior |
| --- | --- |
| AUTO | Search the detected local connections. |
| WI-FI | Filter results to the Wi-Fi/Ethernet side of the local connection. |
| USB TETHER | Filter results to detected USB network adapters. Enable the tether/network connection in the device's operating system first. |
| MANUAL IP | Enter the host's IPv4 address or computer name, optionally followed by `:port`, and select **Join friend**. |

The menu searches automatically while open. **Refresh** rechecks adapters and restarts the search. Found journeys can be selected directly; use the page arrows when more than two are available. Manual joining remains available when discovery is unavailable or blocked by the network.

**Auto-connect one found journey** is optional and off by default. When enabled, exactly one matching journey must stay available for 1.5 seconds before a join begins. Multiple results require your choice. Editing a profile field holds automatic connection; selecting or editing a manual address keeps it held until you choose an automatic connection mode again. Mode and Auto-Connect settings are saved on your device.

Automatic connection still requires the host's first-companion approval and the same compatible game build. Discovery is an address hint, not permission to join a campaign. Select **Cancel connection** to stop a pending join.

## Who controls the adventure

The host controls story choices and major scene progression: departures, getting off the train, important dialogue choices, quest acceptance, battle entry, continuation, retries, withdrawal and the ending.

The companion helps within the scene the host has opened. Implemented assistance includes independent movement, personal inventory/equipment, trading, crafting/repair/healing tasks, accepted quest work, tactical battle actions and train-ambush shooting. Last Stand farmhouse movement, borrowing supplies, treating the wounded defender, choosing a free window and personal aim/fire/reload/cover/weapon/fire-mode controls are connected. Selecting a window does not start the defense; the host starts it. Each actor uses their own gun, magazine and ammunition. Host and companion can also practice at a nearby shooting range independently, with their own guns, magazines, ammunition, course options and score. The implementation plan tracks the remaining combat, adventure and platform checks.

Protocol30 adds **NEXT LEG** at the stopped train, **V** on keyboard, and an entry in the controller action selector. It shows the host's actual food, water and coal cost. **Request departure** sends a temporary notice to the host; it does not spend supplies or leave the stop. The host can dismiss it or use the normal travel confirmation when ready. Repeated requests do not renew a pending notice, and requests close when the host changes the scene.

## Personal controls and journey views

The connected companion can open **Device settings** from Local Play to change audio, accessibility, keyboard/controller bindings and touch-control placement. These settings stay on that device. **Back** returns to Local Play without leaving the journey.

The companion's **MAP** and **JOURNAL** show visited stops and accepted objectives. They capture personal controls without progressing the host's story. Their scroll position stays private; a host scene change closes them. An open read-only view can remain through a brief movement update delay, while world movement and actions continue waiting for fresh host data.

**POSE** offers stand, sit, lay and use. The host checks and shares these personal poses; they do not change position, spend resources or progress the story. Remapped controls apply to guest actions and the original host controls. The controller's guest action selector provides the visible assistance buttons.

The personal controls first shipped in version31 development packages. Build31's phone map check passed, while its town POSES taps did not show a panel. Protocol30 repairs a separately reproduced defect where a valid snapshot refresh closed an already-open POSES menu. Pose submissions and presentation continue requiring fresh host data. The configured version32 candidate includes that repair and NEXT LEG; new-package physical verification remains pending.

## Shooting ranges

At a range in an ordinary stop the host has opened, either traveler can start practice independently. Approach the booth and use the interaction control; the companion also has a **Target Range** button. Each player chooses their own weapon, target material, motion, pattern, distance and course length. Aim, fire, reload, sights, monocular and fire-mode controls retain the original range mechanics.

The companion has a **Pause / Resume** button, **P** on keyboard and **START** on controller. This pauses their course without freezing the host. Opening Local Play or losing focus also pauses their controls and course. Each actor spends their own ammunition; buying ammunition uses shared scrap. Scores are separate, while the stop's high score and goodwill tier are shared and cannot be paid twice.

Leaving practice and reopening it resumes the saved session and partial magazine. Rejoining requires a fresh checked connection to the lane. If a critical save fails, both courses wait for the host's **Retry Save**; controls then reacquire the retained sessions with held fire cleared. Repeated temporary recovery failures show **RETURN to retry or E to leave**. Host story transitions can interrupt practice and preserve its saved state.

## Disconnects and saves

After a successful connection, transient interruptions can trigger up to six automatic reconnect attempts, with delays of 0, 1, 2, 4, 8 and 8 seconds. The saved credential identifies the same companion; reconnect does not import another inventory or create another starting kit. Rejected, incompatible or initially unsuccessful connections do not enter that automatic retry loop.

**Cancel reconnect** stops retries and holds automatic joining for the current search. Retry manually or select a connection mode/Refresh when you want to search again. If the host closes the game, the guest waits or returns to Local Play; another player does not become the host automatically.

The host must finish critical saves before an action is confirmed. A failed save uses the host's existing **Retry Save** flow; the guest waits for the durable result. Personal device settings remain local. Leaving Local Play does not copy the host's campaign onto the guest.

Current scope is local network play, including manual local-address connections. Internet connections and automatic host migration are outside this release.

See [the implementation plan](concepts/MOUSE_FRONTIER_COOP_PLAN.md) for current automated, connected and physical acceptance evidence.

Installed Android version31 uses protocol29. The configured next candidate is version32/protocol30, adding travel requests, pose-refresh retention and lazy scene/title asset loading. It requires a matching new Windows package. The old protocol28/build30 and protocol29/build31 pairs remain historical candidates; a different protocol or shared code identity cannot join. Physical memory stability and the remaining device matrix are still required. See [package instructions and candidate evidence](COOP_PACKAGING.md).
