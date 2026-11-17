# ZedComm combined Build 42 smoke test

Use this guide for the staged singleplayer build. Run the checkpoints in one disposable debug save and keep the working rigs until the last checkpoint. The first rig uses a Basic Small Cabinet. Later checks add a powered lamp, a Network Switch, two Weight Plates, and an Advanced cabinet.

## Setup and check-ins

- Fully restart Project Zomboid in debug mode, enable **ZedComm** for the save, and load in.
- Find five clear floor tiles in a row for Checkpoint 1. For later checks, use a site with a powered vanilla lamp with a bulb, a wall for the Network Switch, and enough clear space for two parallel runs. A nearby clear road makes vehicle testing easier.
- Use the Lua command console for the item grants. Put items and modules in your main inventory. Prepare each checkpoint as you get to it. Open **Next** and **Previous** in the cabinet editor to find carried modules on its second page.
- At each check-in, report PASS or the step and observed result. Include a screenshot for a placement or visual issue if it helps. Pause while still in the save at Checkpoints 1 and 5 for a console capture. Capture again at Checkpoint 6 after reload. The active log is `%USERPROFILE%/Zomboid/console.txt`.
- A connected `0` is a valid signal. An unavailable signal reads as dashes or **no signal**. **Unattached** means the display itself needs a cable.

## Resume here - Fresh Advanced arithmetic rig

After restarting on the updated Workshop package, build this rig on clear tiles. You can use the same save. If your save still has a Splitter with old internal Out A or Out B links, remove that module on the older build before updating, or use a fresh debug save. Checkpoints 1 through 3 are already recorded. Run the arithmetic below first, then the changed Splitter, timed upgrade, and display checks in Checkpoint 4.

```lua
getPlayer():getInventory():AddItem("ZedComm.AdvancedSmallCabinet")
getPlayer():getInventory():AddItems("ZedComm.WeightPlate", 2)
getPlayer():getInventory():AddItem("ZedComm.AdvancedDisplay")
getPlayer():getInventory():AddItem("ZedComm.InputExtension")
getPlayer():getInventory():AddItem("ZedComm.AdderModule")
getPlayer():getInventory():AddItem("ZedComm.SubtractorModule")
getPlayer():getInventory():AddItem("ZedComm.MultiplierModule")
getPlayer():getInventory():AddItem("ZedComm.DebugByteSource")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 18)
```

1. Set both Weight Plates to **Advanced Sender** with the Debug menu. Give them different steady loads. Use **Debug → Inspect circuit** on each plate and record its kg value. Wire plate A to Fixed IN and plate B to an Input Extension. Wire Fixed OUT to the Advanced Display. In the editor, configure Fixed OUT to Advanced.
2. Install Adder and select **Full Reading** under **Configure**. Link **Fixed IN → Adder A**, **Input Extension → Adder B**, and **Adder OUT → Fixed OUT**. Expect the sum on the face. Use **Read full signal** for the exact kg. Disconnect either input to check for no signal, then reconnect.
3. Right-click Adder and choose **Remove module**. Verify it returns to inventory and its internal links clear. Install Subtractor, select **Full Reading**, and reconnect the same three links to its A, B, and OUT. Expect A minus B, floored at zero. Swap the inputs to check both orders.
4. Replace Subtractor with Multiplier and select **Full Reading**. Feed a Weight Plate into **Reading**. Disconnect the other plate from the Input Extension and wire a **Test Byte Source** set to `4` to that jack. Link it to **Factor**. With an `80 kg` load, expect `320` on the display face and `320 kg` under **Read full signal**. Set the output jack to Basic and expect `32`, then set it back to Advanced.
5. Pause for an arithmetic console capture before moving on to the Checkpoint 4 retest. Record the two input loads, the three operation results, and any difference between the rounded face and the exact readout.

## Checkpoint 1 - One plate, Basic cabinet, display

```lua
getPlayer():getInventory():AddItem("ZedComm.PressurePlate")
getPlayer():getInventory():AddItem("ZedComm.SmallCabinet")
getPlayer():getInventory():AddItem("ZedComm.ThresholdModule")
getPlayer():getInventory():AddItem("ZedComm.NumericDisplay")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 6)
```

1. Place these in a straight line with one clear wire tile between each device: **Pressure Plate → wire → Basic Small Cabinet → wire → Numeric Display**. Use the ZedComm world menu or native **Place**.
2. Route the first run from the plate into the cabinet's **IN**. Select the plate's free end, lay one segment in the gap, then click the cabinet and choose the **IN** connection. Start a separate run from cabinet **OUT**, lay a segment in the second gap, and connect it to the display. Right-click a wire and use **Inspect wire** if you need to confirm which run you selected.
3. Choose **ZedComm → Open Small Cabinet**. Check the editor title says **Basic Small Cabinet** and the board is 6×6. Drag **Threshold** from **Carried modules** to column 2, row 1. Select it and use **Configure** to set `50`. Click the matching contacts to make **Fixed IN → Threshold IN**, then **Threshold OUT → Fixed OUT**. Each pair is a separate link.
4. Set the plate output to `155` via **ZedComm → Set pressure plate output**. Check the display reads `0 → 255 → 0` as you step on and off. **Read numeric display** should match the digits. Inspect the incoming wire to confirm it carries `155` while occupied.
5. While the plate is clear, use **Disconnect cabinet jack (IN)**. The display should show no signal. Reconnect that wire to **IN** and check that `0` returns. With a wire on the display's own tile, check that it goes under the housing and leaves the digits visible. Leave the rig built.

**Check-in 1.** Pause in the save for a console snapshot. Report whether placement, `0 → 255 → 0`, and disconnect/reconnect passed.

## Checkpoint 2 - Arming, lamp adapter and editor

```lua
getPlayer():getInventory():AddItem("ZedComm.NetworkSwitch")
getPlayer():getInventory():AddItem("ZedComm.InputExtension")
getPlayer():getInventory():AddItem("ZedComm.OutputExtension")
getPlayer():getInventory():AddItem("ZedComm.AndModule")
getPlayer():getInventory():AddItem("ZedComm.AdvancedAdapter")
getPlayer():getInventory():AddItem("ZedComm.ThresholdModule")
getPlayer():getInventory():AddItem("ZedComm.WeightPlate")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 12)
```

1. Mount the Network Switch on a wall and open the Basic cabinet. Add AND at column 4, row 3. Drag Input Extension to the top edge at column 3, row 1 and use **Rotate Building** (R by default) until its jack faces out. Try a board-interior drop first. It should stay in inventory. Use the displayed number for the new IN jack.
2. Click the existing Threshold OUT and Fixed OUT contacts again to cut their link. Connect **Threshold OUT → AND A**, **Input Extension OUT → AND B**, and **AND OUT → Fixed OUT**. Wire the Network Switch to the new IN jack. Name this run **Arm** using **Rename run** on its cable. For a steady load, drop a pipe on the Basic Plate and step clear. Switch ON and OFF. The switch sprite should change, and the display should show `255` when armed, `0` when disarmed, and no signal if the Arm input is unplugged. Reconnecting while the switch is ON should restore `255`.
3. Add an Output Extension to a free edge and connect **Threshold OUT → extension IN**. Wire it to a separate display if you have one, or move the existing display run to that jack temporarily. With the load steady and the arm OFF, the extension should send `255` while Fixed OUT sends `0`. Rotate or move the connected extension to another valid edge and check its links follow. Remove it, then check the item returns and the old wire has a free end. Reinstall and reconnect it if you want to leave the branch built for reload.
4. At a separate, unconverted powered vanilla lamp with a bulb, choose **ZedComm → Install Advanced Adapter**. Wire a Weight Plate straight to the lamp. Open the 3×3 editor, drag in Threshold, and select **Auto-connect**. Set the threshold to `1`; step onto and off the plate and verify the lamp follows. Increase the setting above the occupied byte via **Set threshold** on the lamp, then put it back via the editor. The lamp should follow the new setting while the input stays steady.
5. Drag that Threshold with the rotate key to two cells on the bottom row. The internal links should follow. Try an overlapping drop and cancel a drag with right-click. From two tiles away along an open path, verify the board can be viewed. Move adjacent to edit.
6. Keep the lamp wired and occupied. Try the native switch and check the wire keeps control. With a battery or bulb that can be reached while a loose item holds the plate, remove power or the bulb. Restore it with the plate occupied and check the lamp comes back on. Repeat with the plate clear and check the lamp stays off. Record the method you used. Disconnect the lamp's cable and verify manual control returns, then reconnect. Leave the lamp and its circuit built.

**Check-in 2.** Report the arm behavior, lamp editor and power results, and any problems with extension placement. If convenient, test switch pickup and remount on south and east walls without a corner tile. Check the saved latch and both sprite positions.

### Checkpoint 2 follow-up - Wall switches and jack labels

1. In native **Place**, select a Network Switch and hold left-click on a tile that borders two walls. Drag toward each wall and then toward the open edge. The preview should stay on the original tile and only face eligible walls. Release with the second wall selected and verify the switch matches its preview. Walk between the camera and the switch to check character layering.
2. Connect a cable from an adjacent tile to a switch above wood flooring. With no debug selector active, verify the lead runs down the wall and across the floor to meet the cable. Left-click within reach and confirm the switch sends `255` or `0`. Click with the placement cursor active and confirm the tool handles the click. Verify the entire lead returns once after reload, then disconnect the cable and confirm the lead disappears. Try a same-tile connection if practical.
3. Right-click Fixed IN in the cabinet editor and choose **Rename jack**. Label it **Load**. Label the switch input **Arm** and name an output jack too. **ZedComm → Label cabinet jack** in the world menu edits the same labels. Confirm they appear in both the editor and connection menu and that the runs keep their names and signals. Clear a label with a blank entry, then leave a label for the reload check.
4. Drag a fresh Input Extension to the left edge and a fresh Output Extension to the right edge without rotating. The gold jack marks should face out. Verify their internal terminals face the board. Previously installed extensions keep their rotations.

## Checkpoint 3 - Plate loads, arithmetic and Boolean controls

```lua
getPlayer():getInventory():AddItem("ZedComm.WeightPlate")
getPlayer():getInventory():AddItem("ZedComm.OccupancyPlate")
getPlayer():getInventory():AddItems("ZedComm.NumericDisplay", 2)
getPlayer():getInventory():AddItem("ZedComm.InputExtension")
getPlayer():getInventory():AddItem("ZedComm.AdderModule")
getPlayer():getInventory():AddItem("ZedComm.OrModule")
getPlayer():getInventory():AddItem("ZedComm.XorModule")
getPlayer():getInventory():AddItem("ZedComm.NotModule")
getPlayer():getInventory():AddItem("ZedComm.DebugByteSource")
getPlayer():getInventory():AddItems("Base.LeadPipe", 14)
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 12)
```

1. Check the Basic Plate at `155` with a loose pipe while you stand clear. Removing the item should clear the reading. On both Basic and Weight Plates, check a floor container on the plate and then one tile away. Adding contents should increase the Weight Plate reading and leave Basic at `155` for either loaded or empty furniture. A direct Weight Plate display should read `1` for one pipe and `2` for ten Lead Pipes weighing about 15 in total. A safe vehicle overlap should raise the reading while parked and clear when driven off. An Occupancy Plate should count a lone player as `1`; a live zombie adds one if safely available. Check that a loose pipe does not raise the occupancy count.
2. Reuse the Basic cabinet. Wire two Weight Plates to **Fixed IN** and a new Input Extension. Route both inputs to **Adder A/B** and connect **Adder OUT → Threshold IN** in place of the old direct input. Leave **Threshold OUT → AND A**, **Arm → AND B**, and **AND OUT → Fixed OUT**. Set Threshold to `2`. Drop one Lead Pipe on each plate and stand clear. Each loaded plate sends `1` because any positive load sends at least `1` in Basic mode. With Arm ON, expect `0` with either pipe alone and `255` with both. With both pipes down, switch Arm OFF and back ON. Unplugging either weight run should clear the output. Reconnecting it should restore `255`.
3. For OR and XOR, use two independently settable byte inputs such as a switch and a settable plate or **ZedComm → Debug → Set test byte** on a manually placed **Test Byte Source**. Connect the selected gate output to a display. Check the four rows below. Then connect either of the inputs to NOT. Verify `0` produces `255`, any positive byte produces `0`, and an unplugged input clears the output. Unplug a required input for OR and XOR as well.

| Input A | Input B | OR | XOR |
| --- | --- | --- | --- |
| 0 | 0 | 0 | 0 |
| Positive | 0 | 255 | 255 |
| 0 | Positive | 255 | 255 |
| Positive | Positive | 255 | 0 |
| Unavailable | Connected | Unavailable | Unavailable |

**Check-in 3.** Report the plate readings and gate results. Note any optional animal, zombie, or vehicle case you skipped.

## Checkpoint 4 - Cabinet upgrade, edge-mounted Splitter and full readings

```lua
getPlayer():getInventory():AddItem("ZedComm.SmallCabinet")
getPlayer():getInventory():AddItem("ZedComm.AdvancedAdapter")
getPlayer():getInventory():AddItem("ZedComm.SplitterModule")
getPlayer():getInventory():AddItem("ZedComm.InputExtension")
getPlayer():getInventory():AddItems("ZedComm.AdvancedDisplay", 2)
getPlayer():getInventory():AddItem("ZedComm.CacheModule")
getPlayer():getInventory():AddItem("ZedComm.SubtractorModule")
getPlayer():getInventory():AddItem("ZedComm.MultiplierModule")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 12)
```

1. In Crafting, find **Make ZedComm Basic Adapter**, **Advanced Adapter**, **Basic Small Cabinet**, **Advanced Small Cabinet**, **Splitter Module**, and **Network Switch**. Verify that Basic and Splitter need Electrical 1 and Advanced needs 3. Confirm that a cabinet consumes the corresponding Adapter and a sheet of metal, and that tools are retained. Craft both tiers in this save if possible. See the [recipe table](plans/adapter-and-cabinet.md#cabinet-tiers-and-splitter).
2. Place a fresh Basic Small Cabinet. Try dropping the Splitter in the middle and then on an edge with its jacks facing inward. Both drops should leave it in inventory. Install it at column 1, row 3 without rotating, with the two gold jacks facing out. Make the single internal link **Fixed IN → Splitter IN**. Right-click the Splitter to confirm **Rename SPL-1** and **Rename SPL-2** exist.
3. Wire **SPL-1** and **SPL-2** directly to separate Advanced Displays. Name the cable runs **Branch A** and **Branch B**. Wire an Advanced Weight Plate to Fixed IN. With an 80 kg load, both outputs from the Basic cabinet should send `8`. Clearing the plate should give `0` on both.
4. With instant timed actions off, start **Upgrade cabinet with Advanced Adapter** and interrupt it by walking away. Check that the adapter stays in inventory and the cabinet stays Basic. Retry and wait for the swap. Verify the Basic Adapter returns and the board and named runs survive. Right-click the Splitter and choose **Set SPL-1 to Advanced**. Expect the first display to show `80` on the face and `80 kg` under **Read full signal**, and the second to show byte `8`. Set SPL-2 to Advanced and verify both agree. Unplug one output and watch the other stay live. Unplug Fixed IN and check both clear, then reconnect for reload.
5. On the Advanced cabinet, route the plate through **Cache Data → Cache OUT → an Advanced output**. Use **Configure** to select **Always**, then check the full readout follows the held load. Switch Cache to its enabled mode. Wire a switch to **Enable** using an Input Extension. OFF clears its output and ON forwards the current full reading. A direct wire from the Advanced Weight Plate to an Advanced Display also reports the full reading. Compare a small change in weight that leaves the byte the same.
6. For full-reading Adder, Subtractor, and Multiplier, use the [fresh arithmetic rig](#resume-here---fresh-advanced-arithmetic-rig) above. If you already passed that rig, carry those results forward.

**Check-in 4.** Report the crafting checks, rejected and accepted Splitter placements, adapter swap, independent runs, and typed readouts. Leave the Splitter rig wired for reload if possible.

## Checkpoint 5 - Timing, power and pre-reload capture

```lua
getPlayer():getInventory():AddItem("ZedComm.TimerModule")
getPlayer():getInventory():AddItem("ZedComm.WaitModule")
getPlayer():getInventory():AddItem("ZedComm.MainsSourceModule")
getPlayer():getInventory():AddItem("ZedComm.BatterySourceModule")
getPlayer():getInventory():AddItem("Base.Battery")
```

1. In either cabinet tier, route a Basic Plate through **Wait → display**. Set Wait to 2 seconds. A quick step leaves the output at `0`; hold pressure for two seconds and expect the configured plate byte. Stepping off immediately returns it to `0`.
2. Insert a 10-second Timer after Wait. Start with the plate clear to arm the Timer. Hold the plate for two seconds to qualify Wait and observe `255`. Step off and the signal should stay ON until the Timer expires. Confirm expiry with quiet input. Trigger again and unplug the input. The output should clear immediately. If you check fast-forward or pause, the duration follows real seconds while the simulation runs.
3. Wire a one-cell Mains Source to a display, configure `37`, and check `37` when the host has grid or generator power. Shut off the actual power source and look for no signal. Restore it and check `37` returns. If you cannot interrupt mains power, record that case as pending.
4. Replace the Mains Source with a Battery Source and set `37`. Check no signal with an empty slot. With a charged battery in your main inventory, select the module and use **Insert or remove battery**. Confirm the display reads `37`. Remove the battery and check the reading clears and the battery returns.
5. Re-establish a timed run for the reload check. Leave the cabinets, a named Splitter branch, switch, and lamp connected. Trigger the Timer if verifying expiration state across reload.

**Check-in 5.** Pause in the save for the pre-reload console capture. After the capture, save and quit to the main menu once.

## Checkpoint 6 - Reload, wiring regression and final capture

1. Reload the same save. Verify the cabinet tier, Threshold value, module positions and rotations, jack labels, run names, switch wall and lead, and splitter output modes survived. Change a load or arm switch and confirm the wired outputs follow without any rewiring. A Timer window from the old session should clear and rearm after a valid zero.
2. Use native **Pickup** on the upgraded cabinet. Verify it returns as an Advanced Small Cabinet and the old runs are left with free ends. Place it back and explicitly reconnect. Its board and output modes should still be present. Pick up and replace the vanilla lamp with the normal moveable tools. Reattach its run and check that the saved adapter circuit resumes.
3. Route two independent circuits across a shared tile using normal placement. Include a bend if there is room. Hover the numbered wires to check that the cyan outline follows the exact segment. Use native **Pickup** to remove one wire. Expect one item back and only that route to lose signal. Use an active run to reconnect a compatible existing free end, and confirm an attempted join between two driven runs is rejected. Verify name and reading when the repaired run is inspected.
4. Leave the game running for the final console capture. Report reload, selective pickup, and any unresolved error, visual issue, or skipped case.

## Verification baseline

The Windows package contains 51 files. All 835 offline Lua checks passed on `6432816` with the wire draw-order fix, using installed Build 42 Lua wrappers with simulated game objects. The six checkpoints above cover native crafting, live placement, graphics, power, and save reload in Project Zomboid.
