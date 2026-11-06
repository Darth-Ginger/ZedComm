# Changelog - ZedComm

## Unreleased

- ADR-306: cable runs are explicit chains (two ends per piece, no branching) with one source per network for the MVP. ADR-307: four network object roles, source, receiver, cable and infrastructure, with infrastructure kept out of the endpoint class. ADR-308: existing objects such as lamps join ZedComm by a skill-gated install action, keep the modification through pickup, and behave normally when no cable is attached.
- Network model (`shared/ZedComm/Network.lua`): cable pieces and endpoints with named ports, explicit links (adjacent squares only, never by adjacency alone), networks derived from the links, one source per network, `nil` for disconnected as distinct from a valid zero. It marks changed networks on the simulation and is its recompute step.
- Server registry (`server/ZedComm/Registry.lua`): saves every piece through the game's global object system, several pieces per square, and rebuilds the network from those records on load; drops records whose world object is gone and links only one side remembers.
- Cable spike (`client/ZedComm/CableSpike.lua`, singleplayer, temporary): right-click "ZedComm spike" places, shows and removes tagged test cables, and logs each one found as chunks load, to prove save and load in game.
- `tests/network_test.lua` and `tests/registry_test.lua`; `tests/run.sh` now runs every `*_test.lua`. The registry test loads the game's own wrapper classes from a local copy (`PZ_LUA`) and skips without one.

- Shared simulation entry point: `Simulation.markDirty` and a once-per-tick `Simulation.tick`, with `Local` and stub `Server` dispatch adapters, registered on `OnTick` in singleplayer and on a multiplayer server only.
- `tests/simulation_test.lua` and `tests/run.sh`: Lua 5.1 tests of the pass in singleplayer, server and client modes; CI on Linux runs them.
- ADR-305: the simulation marks changed networks and updates them once per `OnTick`; pausing freezes it.

- Repo scaffold: the Workshop item lives in `workshop/ZedComm/`, kept apart from docs, tests and tools (ADR-401).
- `tools/link-dev.ps1` links the game's Workshop folder to the repo for testing; `tools/build.ps1` checks and copies the item to `dist/`, with `-Zip` and `-Deploy`.
- Bash versions of both tools (`build.sh`, `link-dev.sh`, shared `lib.sh`) for Linux and Git Bash, plus `selftest.sh`.
- CI runs the PowerShell and Git Bash tools on Windows and the bash tools on Linux.
- `preview.png` for the Workshop, drawn by `tools/make-preview.py`.
