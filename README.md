# ZedComm

A Project Zomboid (Build 42) mod for modular wired electronics and simulated digital signals: redstone-style on/off signaling, with a path toward counters, addressed communication and player-built networks.

Status: playable singleplayer prototype on Build 42. Pressure, occupancy and weight plates and a wall-mounted network switch send values over placed signal wire to numeric displays, to lamps fitted with an adapter, and through network cabinets that hold circuits up to 10×10 of logic, arithmetic and timing modules. The [recipe table](docs/recipes.md) lists the craftable parts. The latest recipe changes await in-game verification. In singleplayer, fit a Basic Adapter to a modifiable lamp at Electrical 1 or an Advanced Adapter at Electrical 3. See the [lamp setup and removal steps](docs/player-placement.md#retrofit-a-vanilla-lamp). Multiplayer is not supported. The build plan and the in-game results recorded so far are in [docs/plans/adapter-and-cabinet.md](docs/plans/adapter-and-cabinet.md).

Small, Tabletop, Large, Wall and XL Cabinets come in Basic and Advanced tiers. Tabletop cabinets mount to a clear table or countertop. Wall cabinets mount to any eligible wall face. Large and XL floor cabinets have extra built-in jack pairs.

With a vanilla padlock in your main inventory, use **ZedComm > Cabinet > Padlock cabinet**. A locked cabinet keeps running and protects its existing jack connections. Use **Remove padlock** with a matching key to regain board access, upgrade or pick it up. The action returns the padlock and folds one key back into it, following the native item exchange.

Doors also accept an independent crafted Contact source that reports actual open/closed state without an actuator board. Fit inputs only, contact only, or both with the associated materials.

A **Window Contact** fits to an intact native window at Electrical 1 with a screwdriver. Wire its source jack to a display or receiver. Closed sends 255, open sends 0, and a broken or missing window sends no signal.

The networked door build is undergoing its [gameplay smoke test](docs/networked-door-smoke-test.md). Its [control policy and installed API research](docs/research/networked-door.md) describe the shared 6x3 board and fail-open Lock behavior.

Under **Options > Mods > ZedComm**, **Show fixture name labels** and **Show door status markers** independently control the two world overlays. Both default to on. Fixtures keep their individual label settings. Door boards and mounted maglock hardware stay visible.

Use the [contributor rules](AGENTS.md) when changing code, tests, or documentation.

ZedComm requires Build 42.13 or later for custom item tags. Its items have a **ZedComm** inventory category and its recipes appear under **ZedComm** in Crafting.

## Layout

```
docs/adr/              decision records (canonical copy, see ADR-401)
tests/                 tests of the simulation core, network model and registry, run outside the game
tools/link-dev.ps1|sh  links the game's Workshop folder to workshop/ZedComm
tools/build.ps1|sh     checks and copies workshop/ZedComm into dist/
tools/selftest.sh      exercises the bash tools against a scratch Workshop folder
tools/make-preview.py  redraws workshop/ZedComm/preview.png
tools/make-recipes.py  writes the recipes, their names and docs/recipes.md from one table
workshop/ZedComm/      the Workshop item: the only folder the game and the uploader see
  workshop.txt  preview.png
  Contents/mods/ZedComm/
    common/
    42/  mod.info  media/lua/{shared,client,server}/ZedComm/
dist/                  build output (gitignored)
```

Everything that ships lives under `workshop/ZedComm/`. Keep docs, notes and scripts out of it; the build stops on any file type the game does not use.

Keep all Lua under a `ZedComm/` subfolder of `shared`, `client` and `server`. Files at the same path in two mods overwrite each other. Never change `id=ZedComm` in `mod.info`.

## Two sets of tools

The build and link tools have PowerShell (`.ps1`) and bash (`.sh`) versions. The bash scripts run on Linux and in Git Bash on Windows. Both link tools use a directory junction on Windows. Bash options are `--zip`, `--deploy`, `--remove` and `--workshop-dir <dir>`. PowerShell options are `-Zip`, `-Deploy`, `-Remove` and `-WorkshopDir <dir>`.

## Testing in the game (Windows)

Once, from the repo root in PowerShell (or `tools/link-dev.sh` in Git Bash):

```powershell
.\tools\link-dev.ps1
```

That creates a junction `%USERPROFILE%\Zomboid\Workshop\ZedComm` pointing at `workshop\ZedComm`. Enable ZedComm in the game's Mods menu; edits load on the next game or Lua reload, with no build step. `.\tools\link-dev.ps1 -Remove` deletes the link only.


- The server has no Lua 5.1. Run the suite in a container: `docker run --rm -v <repo>:/src:ro -v <pz-reference>:<pz-reference>:ro -w /src alpine:3.20 sh -c "apk add -q lua5.1 bash && ZEDCOMM_REQUIRE_LUA=1 bash tests/run.sh"`.
- Integration suites share fixtures in `tests/support/` and run independently. Without `PZ_LUA`, they use the two global-object stand-ins in `tests/support/pz`. The runner names `native_placement_test.lua` and `placement_cursor_test.lua` as skipped because they need the game's cursor classes. This mode runs 960 checks across 31 suites.
- Set `PZ_LUA` to the installed game's `media/lua` before a full run. All 1021 checks across 33 suites pass with Build 42.22.2 wrappers. For example, from Git Bash run `PZ_LUA='<ProjectZomboid>/media/lua' tests/run.sh`. Run one suite directly with `lua5.1 tests/cabinet_editor_test.lua`.

## Building a release

```powershell
.\tools\build.ps1          # checks, then copies to dist\ZedComm
.\tools\build.ps1 -Zip     # also dist\ZedComm-<modversion>.zip
.\tools\build.ps1 -Deploy  # also copies into the game's Workshop folder
```

`-Deploy` refuses while the dev link exists, because copying through it would overwrite the repo. Run `.\tools\link-dev.ps1 -Remove` first. To upload, point the in-game Workshop uploader at the deployed copy.

The build stops if `mod.info` lacks `name`, `id` or `versionMin`, or if a stray file type is in the item. The bash build also runs the Lua suite. Run `tests/run.sh` separately when building with PowerShell.

CI (`.github/workflows/build.yml`) runs both tool sets on every push: PowerShell and Git Bash on Windows, bash on Linux, each checking the link, the deploy guard and the stray-file check.

`preview.png` is drawn by `tools/make-preview.py` (plain Python, no libraries): a pressure plate sending 0x5A over eight lines to a display. Edit and rerun it to change the image.

## Simulation updates

One pass per game tick on `Events.OnTick` (ADR-305). Events only mark a network as needing an update; the pass recomputes each marked network once, samples loaded sensors and delivers values in the same tick. `OnTick` does not run while the game is paused, so the simulation freezes with the game. In singleplayer the pass runs in the game process; in multiplayer it will run on the server tick (validated after the MVP).

The pass lives in `shared/ZedComm/Simulation.lua` (`markDirty` from event handlers, `tick` once per tick) and sends each recomputed value through an adapter in `shared/ZedComm/Dispatch.lua`: `Local` in singleplayer, `Server` on a multiplayer server (a stub until multiplayer is validated). `server/ZedComm/SimulationRunner.lua` registers it on `OnTick` in singleplayer and on a multiplayer server, never on a multiplayer client, and logs `[ZedComm] simulation pass running (singleplayer)` to console.txt on the first tick.

`tests/run.sh` runs every `tests/*_test.lua` with a Lua 5.1 interpreter (`lua5.1`, `luajit` or `lua`); the bash build calls it and skips the tests with a warning when none is installed. CI on Linux installs Lua 5.1 and fails if the tests cannot run.

## Decisions

