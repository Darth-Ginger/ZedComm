# Changelog - ZedComm

## Unreleased

- A connected door's Open input releases manual movement when its signal is unavailable. A valid zero still commands Close.

- Fixture names and separate lock and door status icons sit closer to their fixtures and below game windows. A door sprite that catches a right-click exposes the menu for reachable fixtures behind it.

- Wall passthroughs carry up to five independent wire runs across one solid wall edge. Drill an opening or fit a plastic or metal cover. The wall retains movement collision.

- Steady device ticks reuse loaded fixture bindings and routing tables. Unchanged source readings skip signal encoding and publication.

- Circuit validation, lamp byte evaluation, and packet evaluation have separate entry points. Placement timed actions share one command table.

- Vanilla lamp fitting is available in normal singleplayer. It uses one matching adapter and requires Electrical 1 for Basic or 3 for Advanced. Removal returns the installed parts, leaves the cable with a free end, and restores the native switch.

- Door boards, fitting, and fixture cable ends can be reached from either face of single-panel doors. Door and contact housings use the native edge orientation and choose the face toward the player. Native E can play a brief opening animation while passage remains blocked. In-game rendering still needs sign-off.

- Added a craftable Window Contact with its own sash art and inventory icon. A fitted intact window sends 255 closed or 0 open over one output.

- Electrical assembly recipes grant 2 to 8 Electrical XP per craft. Cutting signal wire grants 1 Electrical XP per craft.

- Added 8×8 Large and 10×10 XL floor cabinets, a 6×6 Tabletop Cabinet and an 8×8 Wall Cabinet. Every form comes in Basic and Advanced tiers.

- Native Place previews and places Tabletop Cabinets at the furniture's surface height from adjacent floor. Connected Wall Cabinet leads follow the saved wall face down to the floor and toward each linked cable.

- Cabinets and door retrofit boards can use vanilla padlocks. A matching key or a remembered installer can service the locked board. Both padlock modes keep signals flowing.

- Two Mod Options independently control fixture name labels and floating door status markers across saves.


- Door Contacts are independent crafted source fixtures. Contact-only, input-only and combined fitting use their associated materials. Actual closed sends 255, open sends 0, and unavailable hosts send no signal. Either installation can be removed without disabling the other. Native gameplay checks remain pending.

- Networked doors have a placeholder attached maglock housing with four mounting faces and both hinge layouts, separate hinge-side risers, floor-overlay leads and an actual-lock light. Native door sprites are retained. Visual alignment awaits gameplay verification.


- Registry integration checks are split into independent persistence, runtime, placement, rendering, lamp, plate, debug-menu and editor suites with shared fixtures. The Lua runner reports total checks and names suites skipped without installed game Lua.

- Debug-rig wires use the standard Signal Wire item tag and rendering path. Removed the route-sprite flag and cleanup for retired switch-floor attachments. Older development rigs and floor attachments are not migrated.

- Editor refresh reuses one circuit snapshot for its layout and geometry. Fixture menus share name formatting, and circuit contact coordinates are reused.

- ZedComm items have a dedicated inventory category and recipes appear under ZedComm in Crafting. Native Place groups candidates by registered source, receiver, cabinet, and wire tags. These tags require Build 42.13 or later.
- Wires draw beneath same-tile devices that use the game's floor overlay layer.
- Network Switches use native drag-to-rotate placement at corners. The grounded section of a connected switch lead draws on the finished floor.
- Right-click a jack in the cabinet editor to rename it. Right-click an installed module in either editor to remove it or open its settings.
- Double-click a placed cabinet to open its editor. Advanced cabinet jacks show weight while they carry an Advanced weight packet.
- Right-click a drawn link in either circuit editor to remove it.
- Placed fixtures have device-specific rename actions. Names appear in wiring choices and editor titles.
- The carried-module pane groups parts by function, drag previews show contacts, and terminal hints appear below the board. Cache inputs sit below its mode label.
- Splitters default to right-facing output jacks. Configure opens their independent jack modes on an Advanced cabinet.
- Grounded switch leads use the cable's tile origin and extend to the wall base.
- Wait and Timer show their active countdown below the configured duration in the editor.
- Placed fixtures have their own named submenus under ZedComm.
- The edge-mounted Splitter takes one board input and supplies two independently named external jacks.
- Swapping a cabinet to an Advanced Adapter takes a timed action.
- The Advanced Display face shows weight from Advanced packets and shows bytes from Basic packets.
- Roll wire (`Base.Wire`, 10 units a roll) can be used in place of Electric Wire, one unit for one, in every recipe. A whole roll makes 50 Signal Wire in one craft.
- Every device, wire and module has a recipe except the debug test source. `tools/make-recipes.py` holds the one recipe table and writes the game script, the recipe names and `docs/recipes.md`; CI fails if they drift. The balance is a first proposal and has not been tried in game.
- `tests/registry_test.lua` runs in CI. Stand-ins for the game's two global-object classes live in `tests/support/pz`; the cursor checks still need the game's own Lua (`PZ_LUA`).
- A cabinet is Basic unless it carries an Advanced Adapter; `Circuit.cabinetAdapter` is gone.
- Receiver definitions require `receiverModule` and `bindFixture`. The earlier `receive` and `onUnavailable` callbacks are removed.
- Saves made with development builds before 0.0.1 are not migrated. A display keeps any digit sprites attached by the first renderer, an endpoint whose tag names no definition is refused with a log line, and debug test rigs placed earlier lose their link toggle (the tag field is now `rigWire`).
- Cabinet jacks can be given a label. The Network Switch mounts on a chosen wall, shows a lead toward its wire and toggles on a click. Output Extensions face right by default.
- Small Cabinet: a placed 6×6 circuit board with its own input and output jacks, in Basic and Advanced tiers, with an in-place upgrade that returns the Basic Adapter. A cabinet circuit that would feed back into itself through the external wiring is refused.
- Circuit modules: AND, OR, XOR, NOT, Adder, Subtractor, Multiplier, Cache, Splitter, Timer, Wait, Mains Source, Battery Source, and Input and Output Extensions. Arithmetic modules can work on the full reading in an Advanced cabinet.
- Network Switch and Advanced Display. Recipes for both adapters, both cabinets, the Splitter and the switch.
- Adapter editor: opens from up to two tiles away over an open path, edits only from an adjacent tile, and shows a legend for the contact colours.
- Device definitions (`shared/ZedComm/DeviceDefinitions.lua`) and the device runtime (`server/ZedComm/DeviceRuntime.lua`): pressure, occupancy and weight plates, the numeric display, and a relay fitted to vanilla lamps.
- Maintained signal packets (ADR-309): a basic byte, or an advanced reading with a byte fallback. Sender and receiver modules in `shared/ZedComm/SignalModules.lua`.
- Internal circuits (`shared/ZedComm/InternalCircuit.lua`) and the Advanced Adapter's 3×3 editor, starting with a Threshold module.
- Player placement: context-menu and cursor placement, wire runs with explicit joins, pickup, and named runs. Wires sharing a tile are drawn in separate lanes.
- Placeholder sprite pack built by `tools/pack-placeholder-sprites.py`.
- Tests for the definitions, modules and circuits, and registry tests covering the runtime, placement, menus and editor against the game's own Lua.
- `client/ZedComm/CableSpike.lua` is now `client/ZedComm/DebugCircuits.lua`; it holds the debug menu.

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
