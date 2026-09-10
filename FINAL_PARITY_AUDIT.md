# Final Desktop/Android Parity Audit

Mouse Frontier treats Windows and Android as two presentations of one tracked Lua game. The source and sideload package audit is separate from physical-device acceptance:

1. Install `tools/requirements-test.txt` in the test environment, then run `python tools/run_tests.py`. Missing dependencies or skipped behavior tests fail this full-audit runner. `LUA_RUNTIME_PYTHONPATH` can point to a separate Lupa installation; an existing `.stabilization/python-deps` installation is also detected.
2. Run `tools/run_smoke.ps1 -ReportPath .stabilization/final-parity-desktop.rpt`.
3. Run `tools/run_smoke.ps1 -Full -ReportPath .stabilization/final-parity-route.rpt`.
4. Run `tools/run_last_stand_smoke.ps1 -CaptureScreenshots` and `tools/expedition-integration-preview/run.ps1 -Mode both` for the newest quest/combat paths. The quest harness uses its own save identity; expedition previews use unslotted fixtures.
5. Commit all source, runtime assets, tests and documentation. Generated packages, local save data, image-generation staging and test reports stay outside Git.
6. Run `BUILD_ANDROID.ps1` from clean `HEAD`. It packages shared source, runs the mobile watchdog checks, signs the APK, and verifies the exact embedded archive, identity/version and architectures.
7. Run `python tools/audit_platform_parity.py`. This verifies desktop/mobile checkpoint parity, stop 50, clean-commit provenance, full archive checksums and APK contents. It does not require a connected phone.
8. For physical-device acceptance, connect one Android device and run `BUILD_ANDROID.ps1 -Install`, followed by `python tools/audit_platform_parity.py --require-device`. Complete the touch/save/performance checklist in `ANDROID_PORT.md` on that exact APK.

The final audit rejects a mobile report that omits any desktop gameplay checkpoint. It also requires the reviewed mobile-only touch checks for movement and running, action press/release, menus, exiting homes, settlement help, and pinch zoom. The route must reach stop 50. The package must be built from clean `HEAD`, the APK must contain that exact package and match its recorded checksum, and its signature must be valid. Physical-device acceptance additionally requires the installed game to reach its startup marker; an offline pass does not claim device testing.

Generated reports and packages remain under `.stabilization/` and `output/mobile/`; these are reproducible local artifacts and are intentionally excluded from Git.
