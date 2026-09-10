# Expedition full-application preview

On Windows, run `tools/expedition-integration-preview/run.ps1` for both layouts, or pass `-Mode desktop` / `-Mode mobile`. The runner creates a temporary preview directory with read-only asset access through directory junctions. This avoids LÖVE 11.5's restrictions on mounting arbitrary external folders. The application uses 1280×720 for the touch layout and 960×720 for desktop.

For other hosts, run this LÖVE project with `EXPEDITION_PREVIEW_ROOT` pointing to the repository, `EXPEDITION_PREVIEW_OUTPUT` pointing to an existing capture directory, and project `assets`/`sounds` accessible in the preview source. Set `MOUSE_FRONTIER_MOBILE=1` for touch controls.

The harness mounts the project assets, creates the real application composition, and captures fourteen feature states. It exercises local-map closing, menu pause, cache opening, the boss challenge, carried health, real battle win/loss completion, exact victory return, and valid train placement on defeat. Tests use a fresh unslotted in-memory journey and the separate `mouse-frontier-expedition-integration-qa` identity. No existing player saves are loaded.

Screenshots and an assertion report are written to the configured output directory. It exits nonzero on an integration error. Combat outcomes are deliberately accelerated by setting unit health before advancing the normal battle turn; these checks verify transitions and rendering, not combat balance.
