# Changelog - ZedComm

## Unreleased

- Shared simulation entry point: `Simulation.markDirty` and a once-per-tick `Simulation.tick`, with `Local` and stub `Server` dispatch adapters, registered on `OnTick` in singleplayer and on a multiplayer server only.
- `tests/simulation_test.lua` and `tests/run.sh`: Lua 5.1 tests of the pass in singleplayer, server and client modes; CI on Linux runs them.
- ADR-305: the simulation marks changed networks and updates them once per `OnTick`; pausing freezes it.

- Repo scaffold: the Workshop item lives in `workshop/ZedComm/`, kept apart from docs, tests and tools (ADR-401).
- `tools/link-dev.ps1` links the game's Workshop folder to the repo for testing; `tools/build.ps1` checks and copies the item to `dist/`, with `-Zip` and `-Deploy`.
- Bash versions of both tools (`build.sh`, `link-dev.sh`, shared `lib.sh`) for Linux and Git Bash, plus `selftest.sh`.
- CI runs the PowerShell and Git Bash tools on Windows and the bash tools on Linux.
- `preview.png` for the Workshop, drawn by `tools/make-preview.py`.
