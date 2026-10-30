# ZedComm

A Project Zomboid (Build 42) mod for modular wired electronics and simulated digital signals: redstone-style on/off signaling, with a path toward counters, addressed communication and player-built networks.

Status: scaffold only. No gameplay code yet. The first goal is a pressure sensor sending a value through placed, connected cable to a numeric display (ADR-102).

## Layout

```
docs/adr/              decision records (canonical copy, see ADR-401)
tests/                 tests of the simulation core, run outside the game
tools/link-dev.ps1|sh  links the game's Workshop folder to workshop/ZedComm
tools/build.ps1|sh     checks and copies workshop/ZedComm into dist/
tools/selftest.sh      exercises the bash tools against a scratch Workshop folder
tools/make-preview.py  redraws workshop/ZedComm/preview.png
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

Every tool exists for PowerShell (`.ps1`) and bash (`.sh`); they do the same thing. The bash versions run on Linux and in Git Bash on Windows, where they make a directory junction rather than a symlink. Bash options are spelled `--zip`, `--deploy`, `--remove` and `--workshop-dir <dir>`; the PowerShell ones `-Zip`, `-Deploy`, `-Remove` and `-WorkshopDir <dir>`. The bash build runs `tests/run.sh`, the PowerShell build `tests\run.ps1`.

## Testing in the game (Windows)

Once, from the repo root in PowerShell (or `tools/link-dev.sh` in Git Bash):

```powershell
.\tools\link-dev.ps1
```

That creates a junction `%USERPROFILE%\Zomboid\Workshop\ZedComm` pointing at `workshop\ZedComm`. Enable ZedComm in the game's Mods menu; edits load on the next game or Lua reload, with no build step. `.\tools\link-dev.ps1 -Remove` deletes the link only.

## Building a release

```powershell
.\tools\build.ps1          # checks, then copies to dist\ZedComm
.\tools\build.ps1 -Zip     # also dist\ZedComm-<modversion>.zip
.\tools\build.ps1 -Deploy  # also copies into the game's Workshop folder
```

`-Deploy` refuses while the dev link exists, because copying through it would overwrite the repo. Run `.\tools\link-dev.ps1 -Remove` first. To upload, point the in-game Workshop uploader at the deployed copy.

The build stops if `mod.info` lacks `name`, `id` or `versionMin`, if a stray file type is in the item, or if `tests\run.ps1` exists and fails.

CI (`.github/workflows/build.yml`) runs both tool sets on every push: PowerShell and Git Bash on Windows, bash on Linux, each checking the link, the deploy guard and the stray-file check.

`preview.png` is drawn by `tools/make-preview.py` (plain Python, no libraries): a pressure plate sending 0x5A over eight lines to a display. Edit and rerun it to change the image.

## Simulation updates

One pass per game tick on `Events.OnTick` (ADR-305). Events only mark a network as needing an update; the pass recomputes each marked network once, samples loaded sensors and delivers values in the same tick. `OnTick` does not run while the game is paused, so the simulation freezes with the game. In singleplayer the pass runs in the game process; in multiplayer it will run on the server tick (validated after the MVP).

The pass lives in `shared/ZedComm/Simulation.lua` (`markDirty` from event handlers, `tick` once per tick) and sends each recomputed value through an adapter in `shared/ZedComm/Dispatch.lua`: `Local` in singleplayer, `Server` on a multiplayer server (a stub until multiplayer is validated). `server/ZedComm/SimulationRunner.lua` registers it on `OnTick` in singleplayer and on a multiplayer server, never on a multiplayer client, and logs `[ZedComm] simulation pass running (singleplayer)` to console.txt on the first tick.

`tests/run.sh` runs the simulation tests with a Lua 5.1 interpreter (`lua5.1`, `luajit` or `lua`); the bash build calls it and skips the tests with a warning when none is installed. CI on Linux installs Lua 5.1 and fails if the tests cannot run.

## Decisions

