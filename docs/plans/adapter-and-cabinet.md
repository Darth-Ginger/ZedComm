# ZedComm Adapter and Cabinet Build Plan

**Goal** Build a lamp-side threshold circuit first, then use the same circuit model and editor for the 6×6 cabinet.

**Architecture** The weight plate publishes its ordinary load byte. The lamp's Advanced Adapter runs the threshold and passes the resulting ON/OFF request to the existing lamp binding. A cabinet later uses the same internal evaluator with external ports at both boundaries.

**Target** Project Zomboid Build 42 singleplayer, Lua 5.1, and the linked Workshop development build.

**Design references** [Terminology and player workflows](../terminology-and-player-workflows.md) and [ADR-309](../adr/ADR-309-maintained-signal-packets__zedcomm.md).

## First playable circuit

```text
Weight plate + Basic Adapter
  → wire carries the load byte
  → lamp Advanced Adapter: fixed input → Threshold ≥ 50 → fixed output
  → existing lamp binding receives ON or OFF
```

Start with one Threshold in a 3×3 lamp adapter. Reserve column 1, rows 1–2 for the fixed wire input, and column 3, rows 1–2 for the fixed fixture output. A vertical 1×2 Threshold fits between them. Removable modules rotate by 90° with their terminals. The port layout and remaining cells determine fit. The fixed parts keep their position and orientation.

## Chunk 1 - Internal circuit and lamp binding

**Files** Add a shared circuit evaluator under `shared/ZedComm/`. Integrate through `server/ZedComm/DeviceRuntime.lua` and `shared/ZedComm/Devices/RelayLamp.lua`. Reuse the registry's `setDeviceState` and vanilla moveable marker. Extend the lamp runtime tests in `tests/registry_test.lua` and add focused circuit cases.

- [x] Model the host's two fixed parts, installed module instances, and directed terminal links. Save a module's stable ID, kind, cell, rotation and threshold setting. Save links by module and terminal ID. Derive fit from footprints and evaluation order from the graph. Keep live readings and wire routing geometry out of the saved state.
- [x] Validate footprint bounds and overlap, source-to-input terminal direction, one driver per input, and cycles. Permit saving an unfinished layout. An incomplete path produces unavailable output. Keep valid zero distinct.
- [x] Evaluate Threshold from a byte and a configured integer threshold from 0 through 255. Output 255 for a valid byte at or above the threshold, 0 below it, and unavailable for missing input. Use a debug preset to attach the circuit to an eligible lamp for this chunk.
- [x] Project the incoming packet to the current basic byte, evaluate the lamp's internal circuit, and pass the result to its existing ON/OFF binding. An attached circuit with unavailable output requests OFF. Detaching the exterior cable restores native control. When settings or links change, schedule reevaluation even if the input byte stayed steady. Use the current result when power returns.
- [x] Verify input 8 → OFF, 50 → ON, 115 → ON at threshold 50. Verify changing the threshold to 120 turns the lamp off while the wire remains at 115. Check missing input, broken internal link, steady input, power recovery, same-build reload and pickup. Confirm the installed parts and links travel with the lamp and its external wire stays placed.

**Review checkpoint** The existing lamp can follow a real saved internal threshold circuit driven by an unmodified load byte. Review the circuit and persistence before building the editor.

Chunk 1 passed 614 offline Lua 5.1 checks and the Windows Workshop build. Live gameplay verification remains open.

### Chunk 1 debug walkthrough

Use a fresh disposable singleplayer save in debug mode. Fit an eligible powered vanilla lamp with **ZedComm → Install test relay**. Then choose **ZedComm → Debug → Install test lamp threshold** to install the preset with threshold 50. The preset includes the fixed input and output, one Threshold, and both internal links. The adapter uses the existing relay housing for this prototype.

Wire a Basic weight plate to the lamp and compare the byte in **Inspect circuit** with the lamp. An 80 kg player should produce 8 and leave the lamp off. The tested sheriff car produced 115 and should turn it on. With a steady load above 50, use **ZedComm → Debug → Set test lamp threshold** and choose a value above the current byte. The lamp should turn off while the byte on the wire stays steady. Set it back to 50 and expect it to turn on again.

Disconnect the source side and expect the lamp to go off. Reconnect and check that it responds to the current load. Disconnect at the lamp and confirm its manual switch works. Reconnect, reload the same build, and confirm the setting and wiring persist. Pick up and replace the lamp with vanilla moveable tools and verify that its circuit follows it. Reconnect its exterior cable to resume network control.

The Lua suite covers incomplete internal links, rotation fit, invalid circuits, and same-tick power recovery. The editable grid and player-built internal links are Chunk 2.

## Chunk 2 - Playable 3×3 editor

**Files** Add the client editor alongside `client/ZedComm/PlacementMenu.lua`. Use the placement menu for opening the editor and the world shortcut. Route committed edits through the same validated circuit update used in Chunk 1.

- [x] Show the fixed two-cell parts, installed module sprites and terminals, and carried modules in a right-hand inventory pane. Use debug-granted adapter and module items for the first pass.
- [x] Allow placing, moving, rotating, and removing the Threshold. Reject overlap and out-of-bounds moves. Rotation keeps links attached to the same terminal identities. A removed module releases its links. Inventory and installed state change together on successful install or removal.
- [x] Let the player select two compatible terminals to make a link and select a link to remove it. Draw the route from the terminal positions. Offer automatic connection when a single module gives one clear input-to-output path. Show current input and output with a distinct unavailable state.
- [x] Edit the same saved threshold from the module visual or **ZedComm → Set threshold** on the lamp. When a host has several thresholds later, the world action must identify the module to edit.
- [x] Run the Lua suite and Workshop build.
- [x] Run the in-game checklist below and the pending Phase C packet checks in the same gameplay window. Passed 2026-11-16; see the live results below.

**Review checkpoint** A player can assemble and troubleshoot the lamp circuit without console configuration after receiving the debug items.

### Chunk 2 in-game checklist

Start in a fresh disposable Build 42 singleplayer save with debug enabled. Grant the prototype parts from the Lua console.

```lua
getPlayer():getInventory():AddItem("ZedComm.AdvancedAdapter")
getPlayer():getInventory():AddItem("ZedComm.ThresholdModule")
getPlayer():getInventory():AddItem("ZedComm.WeightPlate")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 4)
```

1. At a modifiable powered vanilla lamp choose **ZedComm → Install Advanced Adapter**. This fits the inventory item directly to an unconverted lamp. Wire the weight plate to the lamp.
2. Open **ZedComm → Open Advanced Adapter**. Check the two fixed parts and the right-hand **Carried modules** count. Choose **Install Threshold** and click the center column's top cell. The count should decrease by one. The lamp stays off until the internal path is connected.
3. Click a module's output contact and the next part's input contact to connect the path from **Fixed IN → Threshold → Fixed OUT**. Selecting the same pair again cuts that link. **Auto-connect** restores the single Threshold path. Check that the input continues to show the plate byte during an internal cut and that the lamp goes off.
4. Right-click the installed Threshold or use **ZedComm → Set threshold** at the lamp. Verify both edit the same saved setting. At threshold 50, the 80 kg player should leave the lamp off and the sheriff car should turn it on. Raise the threshold above the current byte to turn it off without changing the wire input.
5. Select the Threshold and choose **Move**, then **Rotate**, then the bottom-left cell. Check that the rotated part fits the bottom row and the two links follow its contacts. Try a position that overlaps a fixed part and verify the previous layout stays intact. Right-click an empty cell to cancel a placement or link selection.
6. Reload the save with the circuit connected. Verify the selected threshold, rotation, and links. Pick up and replace the lamp with vanilla moveable tools and reconnect its external cable. Then remove the Threshold in the editor and confirm it returns to inventory and clears the internal links.
7. Run the pending [Phase C packet checks](maintained-signal-packets.md#phase-c---singleplayer-proof) in the same gameplay window.

**Live results, 2026-11-16.** Steps 1, 3 and 6 passed, including reload and an unplanned lamp relocation. In step 2 the lamp was already on because no plate was wired yet, which matches the native switch staying in control until a cable attaches. Step 4 passed on the editor side: both edit paths changed the same setting and the input read 8 for the player. The car check was skipped because the rig was indoors. Step 5 rotation could not be exercised on the 3×3 board, so it moves to the drag-and-R-rotate card (on281l2). Loose floor items on the weight plate read 0 by design; counting them is card 97c4izb. Phase C passed in the same save (see [maintained-signal-packets.md](maintained-signal-packets.md#phase-c---singleplayer-proof)). Console capture: `the shared test-log folderchunk2-phase-c-20261116-console.txt`.

**Follow-up change, not yet verified in game.** The editor now opens from up to two tiles away when the path is open (`PlayerPlacement.canView`), but every edit still needs the player next to the lamp. Out of reach, the buttons are disabled and the editor says "Step next to the lamp to make changes." The server-side reach check is unchanged. A legend shows blue output, green input and red selected contacts, and a selected contact is now drawn true red (it was pink or orange). The registry suite covers this with 7 new checks (389 pass). It did not load in the 2026-11-16 session because a save and reload did not pick up the edit. Verify after a full game restart: in the debug console, `print(ZedComm.PlayerPlacement.canView ~= nil)` must print `true` before testing.

**Next.** Verify the range and legend change, then review the Chunk 3 draft below together with the drag-and-R-rotate request, since the cabinet editor should reuse that interaction.

The carried-module pane currently counts Threshold modules in the main inventory. Chunk 2 uses click-to-place and contact selection. The sprites are placeholders. The Workshop build and 628 offline Lua checks passed, including editor callback and inventory failure cases. Live PZ verification is open.

## Chunk 3 - Small Cabinet and external ports

**Draft for review after the 3×3 editor smoke test.** The port rules and acceptance cases below specify the cabinet build. The editor test will inform the layout and interaction details.

- [ ] Add the 6×6 host, fixed ports, and rotatable input and output extensions. Reuse the circuit editor and extend the internal validator for modules with multiple terminals.
- [ ] Extend the existing wire topology and delivery to route by port, then validate external and internal edits against the same feedback rule.
- [ ] Add AND and prove the three-run circuit below with a debug byte source as the arm switch. Run the offline cases before the in-game walkthrough.

### Cabinet port rules

| Part | External connection | Internal terminal |
| --- | --- | --- |
| Fixed IN or Input Extension | Input. Reads the current signal on its cable run. | Output. Feeds one or more module inputs. |
| Fixed OUT or Output Extension | Output. Drives its cable run with the circuit result. | Input. Accepts one driver. |

1. **Grid and jacks.** Fixed IN and Fixed OUT occupy two cells each on opposite edges and stay in place. Each extension takes two cells (2×1 or 1×2 after rotation). The whole footprint must fit without overlap. Its jack must sit on an exterior edge and face out through that edge. Any edge can host an extension, including the top and bottom. The cabinet's world tile anchors all its jacks. Use the existing same-tile or cardinal-neighbor, same-level rule to reach a jack.
2. **Identity and edits.** Identify a port by cabinet ID and a stable local port ID. Fixed ports have reserved IDs. An extension keeps its ID when moved or rotated, so both its external cable and internal links stay attached. Removing an extension deletes its port and internal links, frees its cable end in place, and returns the module item. A new installation creates a new port ID and requires an explicit connection. Reject invalid edits before changing layout, wiring, or inventory.
3. **Independent runs.** One cable end per jack. Each port is a separate node in the wire graph. The evaluator carries a value between ports only through a configured internal path. Count each attached output jack as a source on its own run, including while its value is unavailable. Reject a second source on that run, whether by attaching a source jack or joining two runs. Two outputs on one cabinet can drive separate runs.
4. **Signal values.** An input reads the current packet using the existing basic byte projection, including a valid advanced fallback of 0. Missing packets and packets without a usable byte are unavailable. Threshold outputs 255 at or above its setting and 0 below. AND outputs 255 when both valid inputs are nonzero and 0 when both are valid and either is 0. If either required input is unavailable, AND is unavailable, including when the other input is 0. An output jack publishes the resulting basic packet or clears its previous packet. A wired lamp requests OFF when its run is unavailable. Its native switch returns when its own cable is detached.
5. **Feedback.** For each complete directed path through a cabinet from an attached input jack to an attached output jack, add a dependency from the input run to the output run. Reject an edit if its proposed graph has a cycle, including one that crosses several cabinets or returns to the same run. A path counts even if a required signal is currently unavailable. Check both exterior cable attachments or run joins and interior link edits, since either can complete the loop. For example, a return run may be attached while its return input is unused. An internal link that closes the loop must then be rejected.
6. **Propagation.** Keep the existing per-tick dirty-run processing. Coalesce input changes received in one pass and evaluate each affected cabinet once after that pass, using the latest value for each input. Schedule changed output runs for the next pass. Repeat through downstream cabinets as needed. Equal outputs produce no new delivery. This gives a consistent result for changes delivered in the same pass, regardless of their order. Paths with different numbers of cabinet stages can settle on different ticks.
7. **Reload.** Persist cabinet and module IDs, placement, rotation, configuration, internal links, and external links to port IDs. Rebuild run membership and dependencies from those records, then resample upstream sources. Live inputs and outputs start unavailable and are rebuilt from the current world state. On topology changes, resolve each affected jack against the new graph and refresh or clear its cached input even when the upstream byte stays the same. Removing an output extension invalidates its downstream run on the next pass.

### Acceptance circuit

```text
Weight plate → Run A → Fixed IN → Threshold ≥ 50 → AND input A
Debug source → Run B → Input Extension ───────────→ AND input B
AND output → Fixed OUT → Run C → Powered lamp
```

| Weight byte | Arm byte | Cabinet output | Wired lamp |
| --- | --- | --- | --- |
| 8 or 49 | 255 | 0 | OFF |
| 50 or 115 | 255 | 255 | ON |
| 115 | 0 | 0 | OFF |
| 0 | 255 | 0 | OFF |
| 115 | Unavailable | Unavailable | OFF |
| Unavailable | 255 | Unavailable | OFF |
| Unavailable | 0 | Unavailable | OFF |

### Offline test cases

| Area | Exercise | Expected result |
| --- | --- | --- |
| Layout and rotation | Install and rotate extensions to face each edge. Attempt inward-facing, overlapping, and out-of-bounds placements. Attempt to move a fixed part. | Valid placements succeed. Rejected edits preserve inventory, layout, and links. |
| Port identity | Move a wired extension to another legal edge, remove it, then install another extension in its old cell. | The move preserves its ID and both link types. Removal frees the existing cable in place, clears internal links, and returns one item. The replacement has a different ID and is disconnected. |
| Topology | Build the acceptance circuit, then add a second output on a fourth run. Attempt to fill an occupied jack, drive an already-driven run, and join two driven runs. Include an unavailable driver. | Each input and output is tracked by its own port. The four runs stay distinct. Occupied-jack and source-conflict attempts leave prior links and readings intact. |
| Internal validation | Try input-to-input wiring and adding a second driver to one AND input. Wire one valid internal output to two distinct inputs. | Wrong direction and duplicate drivers are rejected. Fan-out to distinct inputs is valid. |
| Signal values | Run every row above. Use arm byte 1 as another valid ON. Send an advanced packet with fallback 0, then one without a fallback. | The byte rules match the table. An advanced fallback of 0 counts as a valid 0. Missing fallback clears the live input. |
| Clearing and recovery | Start at 115 and 255. Cut and restore Run B, then break and restore the internal link to AND B. Remove a wired Output Extension from a separate active circuit. | Each cut clears the affected output. Restoring a path uses the existing upstream reading without another source change. Removing the output frees the cable and clears the downstream reading. |
| Feedback rejection | Try a same-run feedback attachment and a two-cabinet loop. Try to close a loop by joining free run ends, then separately by adding the final internal link. Include a currently unavailable source. | Each edit that closes a directed cycle is rejected, with prior wiring and signals intact. An acyclic two-cabinet chain and a return cable with no internal return path are accepted. |
| Pass order and settling | In one pass, change weight and arm from 8/255 to 115/0. Repeat with reversed delivery order. Send an unchanged pair. Then test a two-cabinet chain. | Output stays 0 without an intermediate 255. The unchanged pair creates no downstream update. The chain reaches the same final output in both orders and the dirty queue drains. |
| Reload | Save an armed, active circuit. Rebuild it with a current plate byte of 8, then change the byte to 115. | IDs, layout and links restore. The lamp does not replay the saved session's 255. The current samples give 0 and then 255. |

### In-game acceptance

1. Place a cabinet, a weight plate, a debug byte source, and a powered lamp with a Basic Adapter. Open the 6×6 editor. Check the fixed input and output footprints. Install an Input Extension on the top or bottom edge, then install Threshold and AND. Set Threshold to 50 and connect the internal path shown above.
2. Wire and name the three runs so they can be inspected individually. With the arm source at 255, an 80 kg player should leave the lamp off at byte 8. A vehicle that yields 50 or more should turn it on. Keep the vehicle in place, set the arm to 0, and verify the lamp goes off while Run A retains its load byte.
3. Set the arm back to 255. Disconnect its run at the cabinet and check for unavailable output and an OFF lamp. Reconnect it and verify the lamp turns on with the existing load. Move or rotate that wired extension to another legal edge and confirm its connections follow. Remove it and verify the wire stays in place with a free end, the module returns to inventory, and the lamp turns off.
4. Reinstall and reconnect the extension. Save and reload. Verify module settings, port connections, and run names restore. Check that the lamp agrees with the currently present load and arm reading after sampling resumes.

**Review checkpoint** A cabinet reads two independent runs and drives a third. An armed threshold turns the lamp on. Losing either required input clears the output and turns the lamp off.

## Chunk 4 - Combined load and normal gameplay

- [ ] Add an Adder and define overflow before using it in a circuit. Proposed first rule is a byte sum capped at 255. With either input unavailable, the sum is unavailable. A connected clear plate supplies a valid 0.
- [ ] Prove two weight plates → Adder → Threshold → AND with arm switch → lamp. At threshold 100, 60 or 55 alone gives OFF. Together they produce 115 and give ON while armed. These are summed sensor readings. A vehicle overlapping both tiles can contribute to both under the current plate model.
- [ ] Add the real arm switch and recipes for Basic and Advanced Adapters and the selected modules. Exercise native endpoint crafting, vanilla lamp conversion and Basic-to-Advanced upgrade through normal gameplay. Scope ingredient counts and adapter recovery or reconnection during upgrade when the interaction is ready to test.

**Review checkpoint** Players can build, save, reload, and repair the combined-load circuit using normal gameplay actions.
