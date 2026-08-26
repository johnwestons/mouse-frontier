# Final Desktop/Android Parity Audit

Mouse Frontier treats Windows and Android as two presentations of one tracked Lua game. A release candidate is ready only when all of these checks pass:

1. Run the Python test suite in `tools/tests`.
2. Run the normal desktop smoke playthrough and write `.stabilization/final-parity-desktop.rpt`.
3. Run the full-route desktop playthrough and write `.stabilization/final-parity-route.rpt`.
4. Run `BUILD_ANDROID.ps1 -Install`. This packages the current clean commit, runs the packaged-mobile smoke playthrough, signs the APK, installs it on the single connected Android device, launches it, and waits for the game startup marker.
5. Run `python tools/audit_platform_parity.py --require-device`.

The final audit rejects a mobile report that omits any desktop gameplay checkpoint. It also requires the reviewed mobile-only touch checks for movement and running, action press/release, menus, exiting homes, settlement help, and pinch zoom. The route must reach stop 50. The package must be built from clean `HEAD`, the APK must contain that exact package and match its recorded checksum, its signature must be valid, and the installed game must reach the startup marker on a connected device.

Generated reports and packages remain under `.stabilization/` and `output/mobile/`; these are reproducible local artifacts and are intentionally excluded from Git.
