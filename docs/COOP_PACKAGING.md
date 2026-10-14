# Local Play package verification

Windows and Android ship the same Lua game. The Local Play build identity hashes every `game/*.lua` path and its exact bytes, plus the save schema and protocol. Image resizing and Android audio conversion do not change this identity. Both friends must use matching builds.

This document describes build and acceptance commands. A successful archive or binary inspection does not establish that packaged networking, physical Wi-Fi, tethering or Android lifecycle behavior has passed. Record those results separately against the exact checksums.

## Windows portable candidate

From the project folder, run `BUILD_WINDOWS.ps1 -LoveRoot 'C:\Program Files\LOVE'`. `-PythonPath` selects Python 3 with Pillow if the bundled runtime is unavailable. The builder requires the x64 LÖVE runtime and its DLLs, includes the runtime license, and creates:

- `output/windows/game.love`: original runtime assets/audio and the exact shared Lua source.
- `output/windows/portable/MouseFrontier.exe`: LÖVE fused with that archive.
- `output/windows/portable/lovec.exe`: the original console engine for isolated validation harnesses.
- `output/windows/portable/package-audit.json`: code identity, source provenance, runtime hashes and binary evidence.
- `output/windows/MouseFrontier-Windows-<build-prefix>.zip` and `build-report.json`.

Only generated files under `output/windows/portable` are reset. No saves are read, reset or packaged. The ZIP includes all required DLLs beside the executable; distribute and extract the whole folder.

After the source gates pass, run the fused entry point with isolated smoke saves:

```powershell
.\tools\run_smoke.ps1 -LovePath .\output\windows\portable\MouseFrontier.exe -ReportPath .\.stabilization\windows-fused-smoke.rpt
```

For connected package tests, extract the audited archive into a generated directory, then run the same LAN fixtures with the included engine and that directory:

```powershell
python -m zipfile -e output/windows/game.love output/windows/game-stage
.\tools\run_lan_smoke.ps1 -Application -Discovery -GameRoot .\output\windows\game-stage -LovePath .\output\windows\portable\lovec.exe -ReportDirectory .\.stabilization\windows-package-discovery
.\tools\run_lan_smoke.ps1 -Application -Range -TimeoutSeconds 180 -GameRoot .\output\windows\game-stage -LovePath .\output\windows\portable\lovec.exe -ReportDirectory .\.stabilization\windows-package-range
```

Record the fused executable and ZIP hashes with these reports. The extracted-asset harness proves packaged gameplay modules and art; the fused smoke separately proves the embedded entry point. Neither substitutes for two physical devices.

## Android candidate

The configured next checkpoint is Android **0.7.0-mobile.32**, schema44/protocol30, shared Lua identity **84299bd835311b3fb5a0dcc48d94221daa68bf964b676a923cef423bd6a2d021**. It includes NEXT LEG inspection/requests, retained POSES menus through checked snapshot refreshes, and lazy/bounded scene/title images. Build matching Windows files in `output/windows/coop-protocol30-candidate` and Android files through the commands below after Source validation and the clean checkpoint commit. Generated build/APK/co-op reports record their actual hashes and source commit; `.stabilization/coop-protocol30-package-provenance.json` is the local consolidated evidence when generated. This configured candidate is not a claim of installation or physical memory stability.

Version31 was subsequently installed and physically tested in the bounded case recorded at `.stabilization/android-coop-device/build31-report.json`. Nearby discovery, AUTO joining, host approval, independent movement, event/town/return transitions and private map passed. Memory remained high; ADB lost the device before a completed30-minute observation. The desktop host stopped afterward, while the final phone-app state is unknown. This did not prove a new memory kill. Preserve build30's recorded LOW_MEMORY failure separately. Version31 is protocol29 and cannot join the new protocol30 candidate.

`BUILD_ANDROID.ps1` retains its existing packaged mobile/Last Stand checks before the APK build. The mobile archive now records the Local Play identity and verifies every staged Lua file. The APK builder rejects a missing or stale identity before downloading or building dependencies.

Use `BUILD_ANDROID.ps1 -SkipDeviceProbe` for a package-only device-independent build, or pass `-SkipDeviceProbe` directly to `tools/build_android_apk.ps1`. This invokes no ADB commands and records `connectedAndroidDevices: null` and `deviceProbeStatus: not_probed`. It cannot be combined with `-Install`. The physical audit rejects an unprobed device count; unknown is not recorded as zero devices or a verified launch.

After assembly, the APK audit checks its actual `assets/game.love` checksum, every shared Lua module, each required engine architecture (`arm64-v8a`, `armeabi-v7a`, `x86_64`), ENet binding markers, LuaSocket and LuaJIT/FFI entry-point names, and the final merged `aapt dump permissions` output. Unconditional `android.permission.INTERNET` is required for ENet and UDP discovery. No multicast or extra Wi-Fi permissions are added: discovery uses broadcast/unicast UDP.

Generated `package-coop-audit.json`, `apk-coop-audit.json`, `apk-permissions.txt` and `apk-report.json` distinguish binary evidence from runtime module loading and physical networking. The pinned LÖVE 11.5 Android source includes ENet/LuaSocket and static LuaJIT; that source observation alone is insufficient to certify an APK. Binary names/markers indicate compiled binding presence, not successful module loading or socket access.

The automatic adapter detector uses Windows `GetAdaptersAddresses` or POSIX `getifaddrs` through FFI. Android availability and interface naming depend on the device/OS; failed enumeration retains address/manual join fallbacks. USB mode means a network adapter provided by tethering, not ADB transport. Credentials use OS entropy, not gameplay randomness. Internet hosting and The Picture Shop's optional gateway/native-provider features remain deferred.

Inspect an already built candidate without starting it:

```powershell
python tools/audit_coop_package.py --package output/mobile/mouse-frontier-<version>.love --apk output/mobile/MouseFrontier-<version>-debug.apk --permissions-file output/mobile/apk-permissions.txt --report .stabilization/apk-coop-recheck.json
```

## Acceptance record

Before advertising packaged co-op, record the exact source revision and dirty flag, code identity/schema/protocol, game archive hash, executable/APK hash, runtime/ABI evidence, signing result, and topology. Use a new Android version code for a new distributed APK. Final release provenance follows `FINAL_PARITY_AUDIT.md` and requires clean source.

Run Windows host/Android guest, Android host/Windows guest and Android host/Android guest on matching packages. Cover Wi-Fi, hotspot/tether, automatic discovery/search/join, blocked discovery with manual join, approval, reconnect/address change, host restart, focus/background suspension, save failures, and repeated join/leave. Exercise every advertised assistance domain and verify the host's saved campaign after reload. Perform the plan's 30-minute physical session on the slowest supported device, recording frame time, memory, packet sizes and save time. Preserve host story/save ownership throughout.

All generated packages and reports stay under ignored `output/` and `.stabilization/`. Keep normal saves, credentials and the reference project out of release archives.

## October 13 first candidate evidence (superseded)

These earlier candidates used schema **44**, protocol **28**, and shared build identity `1728a8ad346ca347412ada1fc3588a573dc87698c39ce39cf857468067513824`. All **304** shared Lua files (302 under `game/`, plus entry/config) matched that frozen source. Source revision was `bcd24af2317031c65382e08468b3aff26d11d341` with local changes. The later candidates below replace generated artifacts at the same output paths; the following checksums and native reports remain historical evidence for this earlier build.

Windows artifacts are under `output/windows/coop-candidate`. The fused executable passed the **109-checkpoint** isolated smoke (`.stabilization/coop-windows-fused-smoke.rpt`, run `663c35bf4aa642638441aa88d7b63403`). The pinned engine's `boot.lua` selects its embedded archive before parsing a supplied game argument. Actual packaged modules/assets plus the bundled `lovec.exe` passed discovery, automatic join and automatic reconnect (`.stabilization/coop-windows-package-discovery/summary.rpt`, run `504d98056b26440d890f424bf2e68a21`). Packaged simulated-touch normal tactical actions, failed heal save/retry, actual host process replacement and host-only retreat also passed (`.stabilization/coop-windows-battle-actions-touch/summary.rpt`, run `a6b2146c153f4ca488a302e608175bbd`); that run's return screenshot predates the later movement-readiness strengthening. Neither run proves separate physical devices.

| Artifact | SHA-256 |
| --- | --- |
| Windows `game.love` | `3a23086aeb59e7c2fb097f5610b3f42cded4d3534cab025893aa633a68191b60` |
| Fused `MouseFrontier.exe` | `bba3ba0bcce81647b2aaac52b01add84280e38b6606945b9ef76f1fbfcc50f4c` |
| Windows portable ZIP | `8ca7dc6645528dd5d6e0c9addca168ad906eaab1887fd7317ed1a0c37e955a0b` |
| Mobile `.love`, version 30 | `34eb061a293cbe2f63bec4b280f765149ad0ba4c914a4db22ed941844a46034f` |
| Signed debug APK, version 30 | `b33d787c82832bcffb1cf6d7f7edcf92f8fc469549fefa3a2febea93380f0598` |

`output/mobile/apk-report.json` records the successful build, signing, exact embedded game, unconditional INTERNET permission and actual ENet/LuaSocket/LuaJIT/FFI binding evidence for arm64-v8a, armeabi-v7a and x86_64. The builder found **0 connected Android devices**. Device launch, Android runtime module loading and physical networking remain unverified. Generated construction reports intentionally retain false runtime/physical flags; the native reports above are separate evidence, without changing the hashed artifacts.

The same frozen gameplay source passed all seven source gates (`.stabilization/coop-battle-ambush-packaging-validation/validation-summary.rpt`): **1,595** regression cases, desktop, simulated mobile, full route and the Last Stand, zoom and pickup specialists. The complete co-op adventure and physical matrix remain separate release requirements.

Final stronger packaged Windows touch battle return passes **27dbc0861a084da1a7f2ab3c206774d4** (`.stabilization/coop-windows-battle-actions-touch-return-ready/summary.rpt`): fresh ordinary motion acknowledgement, **17.531 px** authoritative guest movement, unchanged host pose and owned state. Its final train screenshot was inspected. Resized mobile-stage simulated-touch natural ambush/retry/rejoin/host restart/host continuation/guest return movement passes **b27e09e8e155421a9bf4ac5c7a40305e** (`.stabilization/coop-mobile-package-ambush-natural-restart/summary.rpt`). It runs on Windows LÖVE with the exact mobile assets/code; it does not establish Android OS/device execution.

## October 13 updated candidate evidence

The build 30 candidates include the guest ambush distant-shot and terminal-feedback changes. Shared identity is `025c9e62116fb843b5d21793d71e23c0170f1e4bb33358b367d2e80412bfd073`, schema **44**, protocol **28**. All **304** shared Lua files matched the source at packaging in both audited archives and extracted GameRoots. Source was dirty at `bcd24af2317031c65382e08468b3aff26d11d341`; these are development candidates. Version 30 was subsequently installed for the physical tests recorded below. New development Source differs from these archives.

| Artifact | SHA-256 |
| --- | --- |
| Windows `game.love` | `13165e7837e0890b0a6b6fd0220df6b671dd3c314c90f8133106c2b2132c3e80` |
| Fused `MouseFrontier.exe` | `69c0efec2c772fa22b0afda728f2f02945f3461895ca66a19f71cac920b8177a` |
| Windows portable ZIP | `30b1bed819e2dcf31e49829e436c59c6d2277f5cc946e2cbca9e25d40068db8c` |
| Mobile `.love`, version 30 | `ea6f26582e476901f6e92532b5ea13474a7c3957ffc87021d6ad6e1785fe4bce` |
| Signed debug APK, version 30 | `2a83a1130e74a1e2993946b8bb5a1f50859f97f522eca52c99d6754fbdc5d438` |

Successful build reports, independent archive audits and extracted-stage identity evidence are retained under `.stabilization/coop-ambush-audio-*`. Windows remains under `output/windows/coop-candidate`, with extracted GameRoot `output/windows/coop-candidate/game-stage`; the mobile GameRoot is `output/mobile/stage`. APK signing, exact embedded mobile archive, unconditional INTERNET permission and native binding presence pass for all three ABIs. The APK is **325,042,680 bytes**. No installation or Android launch occurred; there are **0 connected Android devices**. Cached Android SDK repair and network preflight failures are recorded separately from the successful final build.

Current-source native ambush acceptance passes on desktop **01a4219c36bf49ce8689f0aabc11af5a** and simulated touch **1a3ff4ed195b49c2ba7c0aede9b5e7c6**. Each records two actual distant audio dispatches on the guest, original enemy timing, failed save/retry, exact retained gun state, host process replacement, host-only continuation and fresh returned movement. Inspected result PNGs show the correct host-waiting status. This is source runtime evidence on Windows loopback, not yet current-package fused/discovery/adventure acceptance or physical audibility.

The frozen updated source passes all seven required gates, terminal exit **0**, **7 passed / 0 failed** (`.stabilization/coop-ambush-audio-validation/validation-summary.rpt`): **1,620** regression cases in **268.228 seconds** (driver **268.86**), desktop **31.59**, simulated mobile **32.94**, full route **43.86**, Last Stand **6.42**, zoom **8.42**, pickup **4.14**.

The exact current fused Windows executable passes **109** isolated checkpoints (`.stabilization/coop-ambush-audio-windows-fused.rpt`, **71c327b80ee448f4ae7bb5cbdc940081**). Packaged discovery, automatic joining and automatic reconnect pass **79f9d381b98449b8a53896e553e4453d** (`.stabilization/coop-ambush-audio-windows-discovery/summary.rpt`). The packaged desktop adventure passes **c8c7b59dbab2421da611a5be81c29a42** (`.stabilization/coop-adventure-windows-ordinary-offer/summary.rpt`): actual navigation/cache consumption, natural original battle victory with both players attacking, one-time rewards, guest trade, host-only original Last Stand Not Now choice, physical contextual train boarding, exact original slingshot storage, fresh host process/saved companion and exact item retrieval after reload. All 12 saved desktop PNGs were inspected; item identity is verified by real saved-state assertions, while storage/retrieval images show the resulting train and status. This is a representative Stop 6 adventure, not every route/boss.

The mobile-stage adventure remains diagnostic: **6c5decbcf32e4c1ab91fb24b6e6b9a91** hit the original ordinary command rate limit; paced **621031c2bc6c4e06a95ef4887d62777d** completed cache work but stalled at host expedition touch movement. Production rate limits are preserved. Later touch recovery **d1114573860b4721b16c5db746e6023f** completed natural battle victory but encountered the original Last Stand offer during guest trade (`modal_scene`). The fixture must resolve that host-owned offer before trading; complete mobile adventure acceptance remains pending.

The representative original Stop 35 boss passes on packaged Windows **5dd1623ebfab42a0b6e6d55aea771dd8** and simulated mobile stage **8310a30fb9bd402a9cbf95780f452724**. Both retain the original 43 HP boss, attacks and incoming damage, healing by both actors, original one-time rewards, failed save and Retry, a fresh host process, exact saved companion, host-only continuation and fresh guest movement. These are Windows engine tests, including mobile assets/touch simulation; they do not establish Android device execution.

## October 13 physical Android installation

The signed version **30** APK above was installed successfully with `adb install -r` on Samsung **SM-S938U**, serial **R5CY92V6L6B**, Android **17**. The installed package reports version code **30**, name **0.7.0-mobile.30**; the APK hash was independently rechecked before installing. The phone has Wi-Fi **192.168.1.138/24**, and the desktop Ethernet address is **192.168.1.239/24**. ADB is used to operate and observe the device; it is not the game connection.

After the user unlocked the phone, first-frame and physical Windows-host/Android-guest networking were observed. AUTO and WI-FI discovery, manual address entry/join, actual host approval, guest touch movement with the host stationary, durable inventory swap preserving gear identity `i4` and host-owned state, maintenance completion (condition 100%, five oil), leaving and automatic reconnect passed. Host event choice and continuation were shown read-only on the guest. A cold phone reconnect to a fresh desktop process reloaded the saved companion and kit, and fresh guest town movement was observed. Evidence is in `.stabilization/android-coop-device/device-report.json`, actual phone PNGs, command logs, saved-state assertions and `resume-checkpoint.json`. The original build-time APK report remains unchanged; this device report records later physical execution. No manual save reset or backup was performed.

The long session was **not a stability pass**: Android terminated PID **26000** at **19:50:32** during host event-to-town progression with exit reason **3 (LOW_MEMORY)**, RSS **882 MB**. Cold reconnect recovered the journey, but title-only PSS was approximately **860 MB**, and town RSS reached approximately **1.1 GB**. The memory issue requires a fix and repeat acceptance. Android hosting, a second Android peer, actual tether/hotspot, and the full physical gameplay matrix remain pending.

Pair this phone build with the immutable `output/windows/coop-candidate/game-stage` and bundled `output/windows/coop-candidate/portable/lovec.exe`, both using build identity **025c9e62116fb843b5d21793d71e23c0170f1e4bb33358b367d2e80412bfd073**. Current development Source includes guest settings, remapped controls, map/journal, poses and memory changes on protocol29. It is not this installed build, and needs new matching packages plus physical acceptance.

The host-only physical-test fixture `tools/android-coop-device-test/start_host.ps1` started one actual packaged desktop application, isolated APPDATA/normal slot 1, in run **2253d27f8e60473886c400f7fe145e54** (PID **36248**, fresh resume PID **25976**). It creates no synthetic guest. Actual wildcard UDP endpoints **22124** (ENet) and **22125** (discovery), host approval and physical guest commands were observed. `-ResumeRoot` reuses the actual isolated saved journey, verifies the exact companion kit and does not create a replacement campaign. At the user's disconnect request, the phone app was force-stopped, its temporary screenshot removed, and both desktop processes were confirmed stopped after actual quit actions. The installed APK and reconnect information remain on the phone.


## October 14 version 31 development candidates

The new Windows/mobile candidates share code identity **bd8e4292a2e65e06fd61a256371c31a2f3fda9f24d266e6c078aa071e360b76f**, schema **44**, protocol **29**, and all **311** entry/config/game Lua files. They include guest device settings/remaps, private map/journal, checked shared poses, train-only upgrade guards and asset-retention changes. Source remains dirty at `bcd24af2317031c65382e08468b3aff26d11d341`; these are development packages, not the final clean-source release.

| Artifact | SHA-256 |
| --- | --- |
| Windows `output/windows/coop-protocol29-candidate/game.love` | `6adc479f2dd47734c04d8027fbf2f394732296b68929c147f0722578395d14c9` |
| Fused Windows `portable/MouseFrontier.exe` | `e5824c6e6dc2319475949050bc279b48ada17d6d70c7b1b3460667059aa1c153` |
| Windows `MouseFrontier-Windows-bd8e4292a2e6.zip` | `1e229ca567e76e569d13b323fbba3a8dbb43268719c6d9550237b9c7123d8024` |
| Mobile `output/mobile/mouse-frontier-0.7.0-mobile.31.love` | `60255aca56d9fa49ddaf6ab66e4347c317aff05c6f949d4bd45249f77ddaba4f` |
| Signed `output/mobile/MouseFrontier-0.7.0-mobile.31-debug.apk` | `3240bd137d8bd5a6222d552d5faed664b12999c1deca7e47965233f8b75c3b3c` |

The APK is **325,069,460 bytes**, version code **31**, name **0.7.0-mobile.31**. Signing, actual embedded mobile archive, merged INTERNET permission and native binding presence pass for arm64-v8a, armeabi-v7a and x86_64. The build used `-SkipDeviceProbe`: **no ADB command or installation occurred**, device count is `null`, and probe status is `not_probed`. Runtime loading, physical networking and memory stability flags remain unverified. The skip/probe/report/parity paths pass **15** focused tests (.stabilization/coop-android-no-device-probe-focused.log), including zero fake-ADB invocations when skipped and rejection of Install plus Skip.

The actual fused Windows executable passes **109** isolated checkpoints (.stabilization/coop-protocol29-windows-fused.rpt). Exact packaged Windows discovery/automatic join/reconnect passes **3f5bfff6c2c64894a8952e35250c9ca3**. Exact packaged controls pass Windows **a8082717e6b24429b6f5a10e67bcd732** and mobile-stage simulated touch **8b1be9a749794771a7ac8047c07348b4**. These cover persisted private options/bindings/layout, map/journal, shared poses, host-only story and leaving. Root reviewed the mobile pose/menu, map, journal, audio/layout and backpack images: primary controls are legible; the layout preview retains a small USE/PACK-box overlap, which does not establish a gameplay hitbox problem. The actual mobile archive passes **116** startup/gameplay checkpoints (.stabilization/coop-protocol29-mobile31-package-smoke.rpt) and the existing Last Stand specialist's **1,591** checks / **108** saves / **180-second** defense (.stabilization/coop-protocol29-mobile31-last-stand.rpt).

Exact mobile-stage natural boss acceptance **0821e56eb6424c959de9f3e0ca90a48b** passes with original Stop **35** boss/AI, independent actions/heals and incoming damage, original rewards once, failed victory write/Retry, real host restart, same saved companion, host-only Continue and fresh ordinary return movement. Root reviewed guest victory/rejoined/returned images; they show actual rewards and the host-waiting message, while item identity/RNG/conservation are established by saved-state assertions. Exact mobile-stage adventure **f4115abc30974efbacbc63f63cbf8259** passes exploration/cache help, natural combat, trade, host-owned original Not Now, boarding, exact slingshot storage/retrieval and host process restart. These are Windows-engine tests with mobile art/touch callbacks, not Android-device execution.

The earlier adventure **77916d7a972e41e599bd58798f19a7a7** rejected a cache request as out_of_reach. The pilot relied only on disposable predicted position for arrival. Its corrected readiness also requires the current checked host motion position and original collision/reach; **33** focused tests reproduce the mismatch with production prediction/authority and preserve the host's original rejection. The passing rerun traces show checked guest distance **46.952** and actual host-authority distance **36.616**, both with canReach=true inside the unchanged **64-pixel** radius. Game Source and package hashes remained unchanged during this fixture correction; no blind rejected-command retries or relaxed reach checks were introduced.

Detailed provenance is .stabilization/coop-protocol29-package-provenance.json. Windows GameRoot is `output/windows/coop-protocol29-candidate/game-stage`; mobile GameRoot is `output/mobile/stage`. The phone remains on build **30** / protocol **28**. Its old matching Windows `output/windows/coop-candidate/game-stage` and engine are still present and their actual code identity was verified as **025c9**. Build **31** needs a matching protocol **29** host and a later explicit device-testing session. Android LOW_MEMORY stability acceptance, Android-host/second-Android/tether/controller/soak/full physical checks and clean release provenance remain pending.
