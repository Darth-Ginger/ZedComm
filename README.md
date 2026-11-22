# ZedComm

A Project Zomboid Build 42 singleplayer mod for wired electronics. Connect pressure plates, switches and contacts to displays, powered lamps or doors, or route them through cabinets with logic, arithmetic and timing modules.

Requires Build 42.13.0 or later. Multiplayer support is outside the current release.

## Documentation

- [Player Guide](docs/player-placement.md)
- [Crafting Recipes](docs/recipes.md)
- [Architecture Reference](docs/architecture.md)
- [Developer Rain Gauge Probe](tools/probes/ZedCommRainGaugeProbe/README.md)

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


- The server clone is separate from the PC's test checkout. Pull the changes into the PC checkout or sync the files, then restart the game to load changed Lua.
- The server has no Lua 5.1. Run the suite in a container: `docker run --rm -v <repo>:/src:ro -v <pz-reference>:<pz-reference>:ro -w /src alpine:3.20 sh -c "apk add -q lua5.1 bash && ZEDCOMM_REQUIRE_LUA=1 bash tests/run.sh"`.
- Integration suites share fixtures in `tests/support/` and run independently. Without `PZ_LUA`, they use the two global-object stand-ins in `tests/support/pz`. The runner names `native_placement_test.lua` and `placement_cursor_test.lua` as skipped because they need the game's cursor classes.
- Set `PZ_LUA` to the installed game's `media/lua` and run `tests/run.sh`. Run one suite directly with `lua5.1 tests/cabinet_editor_test.lua`.
- Live test captures go in the shared test-log folder. Earlier PC captures are in `%USERPROFILE%\Zomboid\zedcomm-test-logs`.

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

## Decisions

