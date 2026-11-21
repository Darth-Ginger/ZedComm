# ZedComm Adapter and Cabinet Build Plan

**Goal** Build a lamp-side threshold circuit first, then use the same circuit model and editor for the 6×6 cabinet.

**Architecture** The weight plate publishes its ordinary load byte. The lamp's Advanced Adapter runs the threshold and passes the resulting ON/OFF request to the existing lamp binding. A cabinet later uses the same internal evaluator with external ports at both boundaries.

**Target** Project Zomboid Build 42 singleplayer, Lua 5.1, and the linked Workshop development build.

Use the [combined Build 42 smoke test](../combined-smoke-test.md) for the staged build and console check-ins.

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

Use a fresh disposable singleplayer save in debug mode. Carry a Basic Adapter and fit an eligible powered vanilla lamp with **ZedComm → Lamp → Fit Basic Adapter**. Then choose **ZedComm → Lamp → Install test lamp threshold** to install the preset with threshold 50. The preset includes the fixed input and output, one Threshold, and both internal links. The adapter uses the existing relay housing for this prototype.

Wire a Basic weight plate to the lamp and compare the byte in **Inspect circuit** with the lamp. An 80 kg player should produce 8 and leave the lamp off. The tested sheriff car produced 115 and should turn it on. With a steady load above 50, use **ZedComm → Lamp → Set test lamp threshold** and choose a value above the current byte. The lamp should turn off while the byte on the wire stays steady. Set it back to 50 and expect it to turn on again.

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

1. At a modifiable powered vanilla lamp choose **ZedComm → Lamp → Fit Advanced Adapter**. This fits the inventory item directly to an unconverted lamp. Wire the weight plate to the lamp.
2. Open **ZedComm → Lamp → Open Advanced Adapter**. Check the two fixed parts and the right-hand **Carried modules** count. Drag a Threshold from that pane and drop it into the top two cells of the center column. The count should decrease by one. The wired lamp stays off until the internal path is connected.
3. Click a module's output contact and the next part's input contact to connect the path from **Fixed IN → Threshold → Fixed OUT**. Selecting the same pair again cuts that link. **Auto-connect** restores the single Threshold path. Check that the input continues to show the plate byte during an internal cut and that the lamp goes off.
4. Right-click the installed Threshold or use **ZedComm → Set threshold** at the lamp. Verify both edit the same saved setting. At threshold 50, the 80 kg player should leave the lamp off and the sheriff car should turn it on. Raise the threshold above the current byte to turn it off without changing the wire input.
5. Hold the Threshold by its body and press the game's **Rotate Building** key (R by default). Drag it into two adjacent cells of the bottom row and release when the preview turns green. The links should follow the rotated contacts and the lamp should keep its current state. Try dropping on a fixed part with a red preview, releasing outside the board, and right-clicking while held. Each should leave the module and links in place.
6. Reload the save with the circuit connected. Verify the selected threshold, rotation, and links. Pick up and replace the lamp with vanilla moveable tools and reconnect its external cable. Then remove the Threshold in the editor and confirm it returns to inventory and clears the internal links.
7. Run the pending [Phase C packet checks](maintained-signal-packets.md#phase-c---singleplayer-proof) in the same gameplay window.

**Live results, 2026-11-16.** Steps 1, 3 and 6 passed, including reload and an unplanned lamp relocation. In step 2 the lamp was already on because no plate was wired yet, which matches the native switch staying in control until a cable attaches. Step 4 passed on the editor side: both edit paths changed the same setting and the input read 8 for the player. The car check was skipped because the rig was indoors. Step 5 rotation could not be exercised on the 3×3 board, so it moves to the drag-and-R-rotate card (on281l2). Loose floor items on the weight plate read 0 by design; counting them is card 97c4izb. Phase C passed in the same save (see [maintained-signal-packets.md](maintained-signal-packets.md#phase-c---singleplayer-proof)). Console capture: `the shared test-log folderchunk2-phase-c-20261116-console.txt`.

**Follow-up change, not yet verified in game.** The editor now opens from up to two tiles away when the path is open (`PlayerPlacement.canView`), but every edit still needs the player next to the lamp. Out of reach, the buttons are disabled and the editor says "Step next to the lamp to make changes." The server-side reach check is unchanged. A legend shows blue output, green input and red selected contacts, and a selected contact is now drawn true red (it was pink or orange). The registry suite covers this with 7 new checks (389 pass). It did not load in the 2026-11-16 session because a save and reload did not pick up the edit. Verify after a full game restart: in the debug console, `print(ZedComm.PlayerPlacement.canView ~= nil)` must print `true` before testing.

**Placement follow-up.** Carried and installed modules use the same hold, drag, rotate and drop interaction. Preview and commit use the circuit validator, so a held part only changes inventory or saved layout when a valid drop commits. An installed module keeps its ID, settings and terminal links. The carried pane counts Threshold modules in the main inventory.

**Next.** Verify the editor range, legend, and drag-and-rotate checks together with the Small Cabinet circuit below. Before that session, confirm the linked Windows source has this build and fully restart PZ.

## Chunk 3 - Small Cabinet and external ports

**Implemented and verified offline.** The placeable Small Cabinet reuses the Advanced Adapter editor, the held-part preview, and the native Rotate Building key. Its fixed jacks occupy rows 1–2 of columns 1 and 6. The floor cabinet prototype supplies the world sprite. A craftable Network Switch provides the arm input. The Test Byte Source remains available for numeric diagnostics.

- [x] Add the 6×6 host, fixed ports, and rotatable input and output extensions. Reuse the circuit editor and extend the internal validator for modules with multiple terminals.
- [x] Extend the existing wire topology and delivery to route by port, then validate external and internal edits against the same feedback rule.
- [x] Add AND and prove the three-run circuit below with a player-operated Network Switch in the offline harness.
- [x] Run the combined in-game placement and cabinet verification. Darth-Ginger confirmed the six-checkpoint smoke test on Build 42.22.2 and the post-cleanup game check on 2026-11-17. See [the combined guide](../combined-smoke-test.md#verification) for evidence.

### Cabinet port rules

| Part | External connection | Internal terminal |
| --- | --- | --- |
| Fixed IN or Input Extension | Input. Reads the current signal on its cable run. | Output. Feeds one or more module inputs. |
| Fixed OUT or Output Extension | Output. Drives its cable run with the circuit result. | Input. Accepts one driver. |

1. **Grid and jacks.** Fixed IN and Fixed OUT occupy two cells each on opposite edges and stay in place. Each extension takes two cells (2×1 or 1×2 after rotation). The whole footprint must fit without overlap. Its jack must sit on an exterior edge and face out through that edge. Any edge can host an extension, including the top and bottom. The cabinet's world tile anchors all its jacks. Use the existing same-tile or cardinal-neighbor, same-level rule to reach a jack.
   Input Extensions start with their jack facing left. Output Extensions start facing right. Label a fixed jack or extension from the cabinet's world menu. The custom label follows the jack ID and appears in the editor and wiring choices.
2. **Identity and edits.** Identify a port by cabinet ID and a stable local port ID. Fixed ports have reserved IDs. An extension keeps its ID when moved or rotated, so both its external cable and internal links stay attached. Removing an extension deletes its port and internal links, frees its cable end in place, and returns the module item. A new installation creates a new port ID and requires an explicit connection. Reject invalid edits before changing layout, wiring, or inventory.
3. **Independent runs.** One cable end per jack. Each port is a separate node in the wire graph. The evaluator carries a value between ports only through a configured internal path. Count each attached output jack as a source on its own run, including while its value is unavailable. Reject a second source on that run, whether by attaching a source jack or joining two runs. Two outputs on one cabinet can drive separate runs.
4. **Signal values.** An input reads the current packet using the existing basic byte projection, including a valid advanced fallback of 0. Missing packets and packets without a usable byte are unavailable. Threshold outputs 255 at or above its setting and 0 below. AND outputs 255 when both valid inputs are nonzero and 0 when both are valid and either is 0. If either required input is unavailable, AND is unavailable, including when the other input is 0. An output jack publishes the resulting basic packet or clears its previous packet. A wired lamp requests OFF when its run is unavailable. Its native switch returns when its own cable is detached.
5. **Feedback.** For each complete directed path through a cabinet from an attached input jack to an attached output jack, add a dependency from the input run to the output run. Reject an edit if its proposed graph has a cycle, including one that crosses several cabinets or returns to the same run. A path counts even if a required signal is currently unavailable. Check both exterior cable attachments or run joins and interior link edits, since either can complete the loop. For example, a return run may be attached while its return input is unused. An internal link that closes the loop must then be rejected.
6. **Propagation.** Keep the existing per-tick dirty-run processing. Coalesce input changes received in one pass and evaluate each affected cabinet once after that pass, using the latest value for each input. Schedule changed output runs for the next pass. Repeat through downstream cabinets as needed. Equal outputs produce no new delivery. This gives a consistent result for changes delivered in the same pass, regardless of their order. Paths with different numbers of cabinet stages can settle on different ticks.
7. **Reload.** Persist cabinet and module IDs, placement, rotation, configuration, internal links, and external links to port IDs. Rebuild run membership and dependencies from those records, then resample upstream sources. Live inputs and outputs start unavailable and are rebuilt from the current world state. On topology changes, resolve each affected jack against the new graph and refresh or clear its cached input even when the upstream byte stays the same. Removing an output extension invalidates its downstream run on the next pass.

### Acceptance circuit

```text
Weight plate → Run A → Fixed IN → Threshold ≥ 50 → AND input A
Network switch → Run B → Input Extension ─────────→ AND input B
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

Use a Build 42 singleplayer debug save and a flat, clear area with a powered modifiable lamp nearby. Grant the cabinet parts in the Lua console.

```lua
getPlayer():getInventory():AddItem("ZedComm.SmallCabinet")
getPlayer():getInventory():AddItem("ZedComm.WeightPlate")
getPlayer():getInventory():AddItem("ZedComm.NetworkSwitch")
getPlayer():getInventory():AddItem("ZedComm.ThresholdModule")
getPlayer():getInventory():AddItem("ZedComm.AndModule")
getPlayer():getInventory():AddItem("ZedComm.InputExtension")
getPlayer():getInventory():AddItem("ZedComm.OutputExtension")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 12)
```

1. Verify the Advanced Adapter placement follow-up in the 3×3 editor. Check two-tile viewing over an open path, adjacent-only editing, and the contact legend. Drag a wired Threshold into the bottom row with **R** and verify both links follow. Try an overlapping drop and a right-click cancellation.
2. Place the cabinet and weight plate. Mount the Network Switch on a tile next to a wall using native **Place** or **ZedComm → Place network switch**. All four edges are eligible. At a corner, placement checks north, west, south, then east. The new switch starts OFF. Carry a Basic Adapter and use **ZedComm → Lamp → Fit Basic Adapter** on the cabinet's target lamp. Open **ZedComm → Cabinet → Open Small Cabinet**. Check the fixed two-cell parts and drag Threshold to column 2, row 1, and AND to column 4, row 3. Rotate an Input Extension 90° and place its top-left at column 3, row 1 so the jack faces out at the top. If installed in this order, its jack is **IN 3**. Set Threshold to 50 and connect the four internal links from the acceptance circuit.
3. Connect the weight plate to **IN**, the Network Switch to **IN 3**, and **OUT** to the relay lamp. Name the three runs. Use **ZedComm → Turn network switch on** and check the raised toggle sprite and `255` on **IN 3**. An 80 kg player should give `8` on the load jack, `0` on **OUT**, and an OFF lamp. A vehicle yielding at least 50 should turn it on. Keep the load steady and turn the switch OFF. The down sprite and `0` should return, and the lamp should go off while the load jack retains its reading.
4. Set arm back to 255. Use **Disconnect cabinet jack (IN 3)**, check for `--` on **OUT** and an OFF lamp, then reconnect and check that the lamp resumes with the held load. Move the wired extension to another edge and check its links. Remove it and confirm the cable stays in place with a free end, the item returns, and the lamp turns off. Reinstall the extension and explicitly reconnect its internal contact and new external jack.
5. Save and reload with the switch ON. Verify switch state and appearance, module settings, port connections, and run names restore. Confirm the lamp follows the currently present load and arm reading. Pick up the switch and remount it on a south wall and then an east wall. Use tiles with only the wall under test so the corner priority does not pick another edge. Check the preview and both toggle positions against the wall. Verify the latch follows the item, the old cable stays on the ground, and explicitly reconnecting restores the arm signal. Capture the game console before leaving the save.
6. In normal crafting, search **Make ZedComm Network Switch**. Verify one Electronics Scrap and one unit of Electric Wire produce the switch, with a screwdriver retained.
7. With the plate above the Threshold, install an Output Extension on a free edge. Link Threshold OUT to the extension and run a separate wire from that jack to a numeric display. Turn the arm switch OFF. The display should hold `255` while the fixed OUT and lamp go OFF. Disconnect the extension's wire and verify fixed OUT still responds to the arm switch.

Continue with the plate load, Adder and logic checks in Chunk 4 in the same game session. The Lua 5.1 suite passed 757 checks using the installed Build 42 Lua wrappers for placement, editor and registry coverage.

**Review checkpoint** A cabinet reads two independent runs and drives a third. An armed threshold turns the lamp on. Losing either required input clears the output and turns the lamp off.

### Built-in room lighting

Build 42's native `IsoLightSwitch` supports explicit on/off. In the installed build, the room-light path updates its room's light state and the other switches assigned to the same room. A future receiver binding could use that path for a selected vanilla room switch and preserve native power checks. For building-wide coverage, a cabinet could fan out to one receiver per room on separate output runs. Verify room identification, interaction with other native switches in the same room, power loss and recovery, and reload on a one-room prototype first. See the [official IsoLightSwitch API](https://projectzomboid.com/modding/zombie/iso/objects/IsoLightSwitch.html).

## Chunk 4 - Combined load and normal gameplay

- [x] Count world inventory items, animals, stationary corpses and floor-level props on the Basic and Weight Plates. A Basic plate sends its configured byte while occupied. The Weight Plate sums the detected mass before encoding.
- [x] Add a two-input Adder with a byte sum capped at 255. With either input unavailable, the sum is unavailable. A connected clear plate supplies a valid 0.
- [x] Prove two weight plates → Adder → Threshold → AND with arm switch → lamp in the offline game harness. At threshold 100, 60 or 55 alone gives OFF. Together they produce 115 and give ON while armed.
- [x] Add OR and XOR for the cabinet and NOT for both the cabinet and the single-input Advanced Adapter. Gates use nonzero as true and preserve unavailable inputs.
- [ ] Run the expanded live smoke checks below.
- [x] Add recipes for Basic and Advanced Adapters, both cabinet variants and the Splitter. The Basic cabinet can be upgraded in place and returns its removed adapter.
- [ ] Complete the non-debug crafting test. Darth-Ginger accepted the starting recipe balance, as recorded in the 2026-11-16 session handoff. All non-debug parts have recipes in [the generated table](../recipes.md). The cabinet upgrade and Splitter passed the combined smoke test. Normal lamp fitting and removal are implemented and await the [non-debug lamp check](../combined-smoke-test.md#non-debug-lamp-retrofit).

### Expanded smoke test

Grant any parts not already in the test inventory. Use the existing cabinet rig for the two-plate circuit, then a spare cabinet or a copy of the test board for comparing gates.

```lua
getPlayer():getInventory():AddItem("ZedComm.PressurePlate")
getPlayer():getInventory():AddItem("ZedComm.WeightPlate")
getPlayer():getInventory():AddItem("ZedComm.InputExtension")
getPlayer():getInventory():AddItem("ZedComm.AdderModule")
getPlayer():getInventory():AddItem("ZedComm.OrModule")
getPlayer():getInventory():AddItem("ZedComm.XorModule")
getPlayer():getInventory():AddItem("ZedComm.NotModule")
getPlayer():getInventory():AddItem("ZedComm.NumericDisplay")
getPlayer():getInventory():AddItems("Base.LeadPipe", 14)
```

1. **Dropped or placed items.** Wire a Basic Plate to a display and configure it to `155`. Drop a pipe or use native **Place Item** on the plate, then step away. Check for `155`, remove the item, and check for `0`. Repeat on a Weight Plate. One pipe should show `1`, and ten pipes totaling 15 should show `2`. Place a loaded bag and check that the reading increases. Remove both the pipes and bag, then verify `0`. Try an animal or stationary corpse when convenient. The occupancy variant still reports players and zombies.
2. **Combine two weight plates.** Keep the existing Threshold and AND-to-lamp path. Add an Input Extension at the bottom edge with its top-left at column 2, row 6, and an Adder at column 2, row 3. Wire the second Weight Plate to the new jack. Remove the Fixed IN to Threshold link, then connect the two weight inputs to Adder A and B and the Adder output to Threshold IN. Set Threshold to `2`. Turn the arm switch ON. Drop one Lead Pipe on each plate. Each plate sends the minimum positive Basic reading of `1`. Either pipe alone should leave the lamp OFF. Both together should turn it ON. Turn the arm switch OFF and ON, then unplug and reconnect one plate. An unplugged input should clear the output, and reconnecting should restore it. If verifying the overflow boundary, two test byte sources at `200` should give `255` on a display wired to the Adder output. An overlapping vehicle can contribute its full reading to both plates when it covers both tiles.
3. **Boolean modules.** Connect two runs to inputs A and B on OR or XOR and wire its output to a display. Use the Network Switch plus a Basic Plate as inputs, which gives you one latched input and one physical input. Try each row of the table. Keep both runs connected for the `0` cases. For NOT, use one input and expect `255` for `0`, `0` for any positive byte, and `--` when disconnected. A NOT module also fits on the 3×3 adapter and can be connected with **Auto-connect** when it is the sole module.
4. **Persistence.** Reload with a complete circuit. Check that the module layout, Threshold value, jacks and wire runs restore. Verify output follows the currently detected load and arm state.

| Input A | Input B | OR | XOR |
| --- | --- | --- | --- |
| 0 | 0 | 0 | 0 |
| Positive | 0 | 255 | 255 |
| 0 | Positive | 255 | 255 |
| Positive | Positive | 255 | 0 |
| Either input unavailable | | Unavailable | Unavailable |

**Review checkpoint** Players can build, save, reload, and repair the combined-load circuit using normal gameplay actions.

## Packet forwarding design

Boolean gates and Threshold publish basic control bytes of `0` or `255`. Missing required inputs produce an unavailable signal. A cabinet has one signal per external run. Additional Input and Output Extensions give it independent jacks without combining unrelated signals onto a cable. Bitwise operations are deferred.

### Cabinet tiers and splitter

Both cabinet tiers use the same 6×6 board. The Basic cabinet is the entry-level build. It receives a byte directly or an advanced packet's sender-supplied byte fallback. An advanced packet without a fallback is unavailable to a Basic cabinet. The Advanced cabinet can receive the full packet and supports Full Reading arithmetic and per-jack Advanced output. New output jacks start in Basic mode, and an Advanced cabinet can have a mix of Basic and Advanced outputs. Cabinets placed in the earlier playtest keep their Advanced capability.

Craft each adapter directly from scrap and wire. Cabinet recipes consume one sheet of metal and the corresponding adapter. All five recipes use a screwdriver and return it. The starting balance is:

| Craft | Electrical | Parts consumed |
| --- | --- | --- |
| Basic Adapter | 1 | 1 Electronics Scrap, 1 Electric Wire |
| Advanced Adapter | 3 | 3 Electronics Scrap, 2 Electric Wire |
| Basic Small Cabinet | 1 | 1 Sheet Metal, 1 Basic Adapter |
| Advanced Small Cabinet | 3 | 1 Sheet Metal, 1 Advanced Adapter |
| Splitter Module | 1 | 1 Electronics Scrap, 2 Electric Wire |

With an Advanced Adapter in your main inventory, choose **ZedComm → Cabinet → Upgrade cabinet with Advanced Adapter** on a Basic cabinet. Completing the timed action returns the Basic Adapter and preserves installed modules, internal links, and external runs. Use the cabinet editor to enable Advanced mode on any output that should send the full reading.

The 1×2 Splitter defaults to the right edge like the Output Extension. Mount it with its two external jacks facing out and its sole internal input facing in. One internal link drives both external runs, including a valid zero. Each jack has a stable label and its own output mode. Right-click the Splitter to rename either jack or change its mode. On an Advanced cabinet, selecting the Splitter and clicking Configure opens the same options. Losing the input clears both branches. Disconnecting one output leaves the other live. Normal one-source-per-run and feedback rules apply to each branch.

### Forwarding behavior

- **Cache** has a **Data** input and an **Enable** input. It uses the latest maintained Data packet. While enabled, it forwards that packet and updates as Data changes. A closed gate or missing input leaves the output unavailable. Re-enabling forwards the current reading.
- Keep full packets on internal connections and derive a byte when a Boolean module evaluates its input. A direct raw input-to-output connection publishes a Boolean control byte. An Adder produces a new numeric result and can publish it directly. Select **Always** on Cache to forward without an Enable connection.
- A basic output sends the sender-supplied fallback or a basic packet as received. An advanced output can send the full packet. An Advanced Receiver hands the endpoint the full typed reading or the original basic byte. A typed arithmetic module can generate a new full-precision result from compatible input types and compute a fallback for that result.

### Secret-door example

Use three input runs. A and B each feed a load threshold. C is a hidden basic plate under a crate. Invert C so removing the crate produces an ON condition. Combine the two thresholds and the inverted crate condition with AND. A missing condition clears the door output. Feed that condition to the door's Open input. The separate Lock input uses ON to lock, OFF or unavailable to unlock. Leave Lock unwired for an ordinary unlocked secret door. Weight thresholds respond to any qualifying load. A player-only requirement would need a player-specific source.

Use a separate output run for each result. The door receives the Boolean Open command. A separate Lock run can inhibit opening while requested. See [the door controls](../research/networked-door.md) for pending-lock and detach behavior. An advanced output can forward A's full weight through Cache, enabled by the unlock condition or set to Always for a continuous reading. Another output can send the crate-clear Boolean. Use one Output Extension per extra run.

The Advanced Display is the first Advanced Receiver. Its face shows the byte fallback. **Read full signal** shows a raw byte or the full typed reading and unit. In an Advanced cabinet, select a fixed output or Output Extension and choose **Configure** to switch between Basic and Advanced transmission for that jack.

## Arithmetic, timer and source modules

### Full-reading arithmetic

Keep Byte mode for existing circuits. It reads byte or fallback operands. Addition and multiplication cap at `255`, and subtraction floors at `0`. Two valid operands are required.

Full Reading mode reads the typed packet. For the first payload, kilograms, Adder and Subtractor accept two compatible weight readings and emit a weight packet. Subtractor computes A minus B with a floor of zero for weight. Multiplier has a **Reading** input and a **Factor** input. A weight multiplied by a unitless factor stays in kilograms. A byte is usable as a scalar at that explicitly labeled Factor input. An input port expecting a weight requires a weight packet.

Compute the fallback from the full result after validating that the result is finite. For example, `1,150 kg + 1,600 kg` publishes `2,750 kg` with fallback `255`. An advanced output and Advanced Receiver preserve the result in kilograms. A basic output sends the fallback. Select a math module and choose **Configure** to toggle Byte and Full Reading.

### Timer and Wait

Use a **Timer** with a configurable ON duration. A plate's transition from valid zero to a positive byte opens the window immediately. The timer outputs `255` for the configured duration even if the player steps off the plate. At expiry, it returns to `0` even if the plate is still occupied. Another valid zero-to-positive transition restarts the window. An unavailable input cancels the window and clears the signal.

Timer and Wait measure real seconds while the simulation runs. Pause stops the countdown. Fast-forward keeps the same real-second duration. Active timing state resets on reload or a circuit edit. The Timer rearms after a valid zero. Use a lamp or display for the smoke test. A future door receiver can use the timed output as its open or unlock command.

**Wait** delays publishing a positive input until it has held steady for the configured duration. It keeps the previous output while a positive reading is pending, with `0` as the initial output on a live input. A valid `0` publishes immediately and resets the countdown. An unavailable input cancels the wait and clears the output immediately. A two-second Wait opens a door after two seconds of steady pressure and closes it as soon as the player steps off. Add a ten-second Timer after Wait to open for ten seconds once the pressure qualifies.

### Tunable sources

A Source occupies one cell and publishes a configured integer from `1` through `255` while powered. The default is `255` for enable inputs. Loss of power clears its output. A source can also provide a numeric Factor to Multiplier.

**Mains Source** checks the host object with the game's appliance grid and generator query. Recovery republishes the configured byte. **Battery Source** accepts a replaceable Base.Battery from the player's main inventory and retains its charge through battery removal and reinstallation. For this prototype the installed battery keeps its charge. Battery drain is a balance decision. The cabinet evaluates its other modules independently of any Source's supply.

### Advanced packet and timing smoke check

Open a group in **Carried modules** to find its parts. Scroll the pane to reach additional groups.

```lua
getPlayer():getInventory():AddItem("ZedComm.AdvancedDisplay")
getPlayer():getInventory():AddItem("ZedComm.AdvancedSmallCabinet")
getPlayer():getInventory():AddItem("ZedComm.CacheModule")
getPlayer():getInventory():AddItem("ZedComm.SubtractorModule")
getPlayer():getInventory():AddItem("ZedComm.MultiplierModule")
getPlayer():getInventory():AddItem("ZedComm.TimerModule")
getPlayer():getInventory():AddItem("ZedComm.WaitModule")
getPlayer():getInventory():AddItem("ZedComm.MainsSourceModule")
getPlayer():getInventory():AddItem("ZedComm.BatterySourceModule")
getPlayer():getInventory():AddItem("Base.Battery")
```

1. **Advanced Receiver and Cache.** Set a Weight Plate to Advanced Sender via the Debug menu. Wire it directly to an Advanced Display and use **Read full signal** while a load is present. Move the reading through an Advanced cabinet with Fixed IN wired to Cache Data and Cache OUT wired to Fixed OUT. Set Cache to **Always**. Basic OUT shows only the fallback. Select Fixed OUT and configure it to Advanced. Read the display again and confirm the exact weight is back. Configure Cache to use Enable, wire an Input Extension to Enable, and run a switch to that jack. Check that OFF clears the reading and ON resumes the current load.
2. **Math.** Reuse the two-plate rig after upgrading its cabinet, or build it in an Advanced cabinet. Select the Adder and configure it to Full Reading. Use Advanced Sender on both plates. Wire Adder OUT directly to an Output Extension, configure that jack to Advanced, and run it to the Advanced Display. Verify the exact sum. Repeat with Subtractor in A minus B order. For Multiplier, feed a weight to Reading and a tuned Source at `4` to Factor. An 80 kg reading should give 320 kg with fallback `32`. Set the output to Basic and confirm the display reports only that byte.
3. **Wait and Timer.** Wire a plate through a 2-second Wait to a lamp or display. A quick step leaves the result OFF. Holding for two seconds turns it ON, and stepping off clears it immediately. Add a 10-second Timer after Wait. Once Wait qualifies, the output stays ON for the timer window after you step off. Check expiry with a quiet input and immediate signal loss on unplug. Try a reload with a timing window active and verify it has cleared.
4. **Sources.** Place a one-cell Mains Source, configure `37`, and wire its output to a display. Check grid or generator power, loss, and recovery. Replace it with a Battery Source. With the source selected, use **Insert or remove battery** to install a charged battery. Verify the configured byte, then remove the cell and confirm the display clears and the battery returns to inventory.

### Cabinet tiers and splitter smoke check

1. In Crafting, confirm the five recipes above use their listed adapter, skill and materials, and that each retains the screwdriver. Craft both cabinet variants or grant the parts below in a debug save.
2. Place a Basic Small Cabinet. Verify the Splitter rejects an interior drop and a drop with the jacks facing inward. Mount it with both jacks facing outward. Connect Fixed IN → Splitter IN and wire the Splitter jacks directly to two Advanced Displays. Connect an Advanced Weight Plate to Fixed IN and verify the displays agree on the fallback byte and show `0` when clear.
3. With the Splitter wired, complete **Upgrade cabinet with Advanced Adapter**. Verify the Basic Adapter returns and the named runs survive. Right-click the Splitter and set each jack to Advanced separately. Its display should switch from byte to kg, while the other branch keeps its own mode.
4. Unplug one output and check the other still reads the load. Reconnect, then unplug Fixed IN and check both readings clear. Reconnect and reload. Confirm both runs follow the current load and that the cabinet keeps its Advanced tier and output settings.

```lua
getPlayer():getInventory():AddItem("ZedComm.SmallCabinet")
getPlayer():getInventory():AddItem("ZedComm.AdvancedSmallCabinet")
getPlayer():getInventory():AddItem("ZedComm.AdvancedAdapter")
getPlayer():getInventory():AddItem("ZedComm.SplitterModule")
getPlayer():getInventory():AddItems("ZedComm.AdvancedDisplay", 2)
```

**Offline verification.** The Lua suite covers direct readout through the native receiver, Cache and output-mode reload, typed arithmetic, timer expiry, source power transitions, both cabinet tiers, swap inventory rollback, and independent splitter runs. Live Project Zomboid verification remains open.
