# ZedComm combined Build 42 smoke test

Use this guide for the staged singleplayer build. Run the checkpoints in one disposable debug save and keep the working rigs until the last checkpoint. The first rig uses a Basic Small Cabinet. Later checks add a powered lamp, a Network Switch, two Weight Plates, and an Advanced cabinet.

## Setup and check-ins

- Fully restart Project Zomboid in debug mode, enable **ZedComm** for the save, and load in.
- Find five clear floor tiles in a row for Checkpoint 1. For later checks, use a site with a powered vanilla lamp with a bulb, a wall for the Network Switch, and enough clear space for two parallel runs. A nearby clear road makes vehicle testing easier.
- Use the Lua command console for the item grants. Put items and modules in your main inventory. Prepare each checkpoint as you get to it. Open **Next** and **Previous** in the cabinet editor to find carried modules on its second page.
- At each check-in, report PASS or the step and observed result. Include a screenshot for a placement or visual issue if it helps. Pause while still in the save at Checkpoints 1 and 5 for a console capture. Capture again at Checkpoint 6 after reload. The active log is `%USERPROFILE%/Zomboid/console.txt`.
- A connected `0` is a valid signal. An unavailable signal reads as dashes or **no signal**. **Unattached** means the display itself needs a cable.

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
5. While the plate is clear, use **Disconnect cabinet jack (IN)**. The display should show no signal. Reconnect that wire to **IN** and check that `0` returns. Leave the rig built.

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
2. Reuse the Basic cabinet. Wire two Weight Plates to **Fixed IN** and a new Input Extension. Route both inputs to **Adder A/B** and connect **Adder OUT → Threshold IN** in place of the old direct input. Leave **Threshold OUT → AND A**, **Arm → AND B**, and **AND OUT → Fixed OUT**. Set Threshold to `2`. Put seven Lead Pipes on each plate and stand clear. Each pile should read `1` alone. The output turns ON only when both are present and the switch is armed. Unplugging either weight run clears the output. Replugging it restores the held result.
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
getPlayer():getInventory():AddItem("ZedComm.OutputExtension")
getPlayer():getInventory():AddItems("ZedComm.AdvancedDisplay", 2)
getPlayer():getInventory():AddItem("ZedComm.CacheModule")
getPlayer():getInventory():AddItem("ZedComm.SubtractorModule")
getPlayer():getInventory():AddItem("ZedComm.MultiplierModule")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 12)
```

1. In normal Electrical crafting, find **Make ZedComm Basic Adapter**, **Advanced Adapter**, **Basic Small Cabinet**, **Advanced Small Cabinet**, **Splitter Module**, and **Network Switch**. Verify that Basic and Splitter need Electrical 1 and Advanced needs 3. Confirm that a cabinet consumes the corresponding Adapter and a sheet of metal, and that tools are retained. Craft both tiers in this save if possible. See the [recipe table](plans/adapter-and-cabinet.md#cabinet-tiers-and-splitter).
2. Place a new Basic Small Cabinet. Try dropping a Splitter in the middle and then at a free edge with its outputs facing outward. Verify both previews reject the drop and leave the item carried. Rotate it so both outputs face into the board and install it flush to the edge. A test layout is the left edge at column 1, row 3 with no rotation. Add an Output Extension on another edge. Wire **Fixed IN → Splitter IN**, **Out A → Fixed OUT**, and **Out B → extension IN**.
3. Wire each output jack to its own Advanced Display. Name the runs **Branch A** and **Branch B**. On a Weight Plate choose **ZedComm → Debug → Weight plate sender → Advanced Sender**. Wire it to Fixed IN, hold a steady load, and use **Read full signal** on both displays. Both should report the same fallback byte. Clearing the plate should show `0` on both.
4. While the rig is wired, choose **Upgrade cabinet with Advanced Adapter** on the cabinet. Confirm the Basic Adapter returns to inventory and the board and named runs stay in place. Select Fixed OUT and **Configure** it to Advanced. Verify the first display returns weight in kg and the second still returns the byte. Switch the extension to Advanced and verify both return the same kg. Unplug one output and watch the other stay live. Unplug Fixed IN and check that both clear, then reconnect them for reload.
5. On the Advanced cabinet, route the plate through **Cache Data → Cache OUT → an Advanced output**. Use **Configure** to select **Always**, then check the full readout follows the held load. Switch Cache to its enabled mode. Wire a switch to **Enable** using an Input Extension. OFF clears its output and ON forwards the current full reading. A direct wire from the Advanced Weight Plate to an Advanced Display also reports the full reading. Compare a small change in weight that leaves the byte the same.
6. On a two-input Advanced cabinet circuit, use two Weight Plates in Advanced Sender mode. Feed them into Adder and use **Configure** to select **Full Reading**. Route the module's OUT straight to an Advanced jack and display. Check the displayed sum against the two observed kg readings. Replace it with Subtractor and test A minus B, including an order that yields `0`. Replace it with Multiplier. Feed the weight into **Reading** and a byte source set to `4` into **Factor**. An 80 kg input should give `320 kg` and fallback `32`. Switch its output jack to Basic and verify the display reports `32`.

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

1. Reload the same save. Verify the cabinet tier, Threshold value, module positions and rotations, names, and splitter output modes survived. Change a load or arm switch and confirm the wired outputs follow without any rewiring. A Timer window from the old session should clear and rearm after a valid zero.
2. Use native **Pickup** on the upgraded cabinet. Verify it returns as an Advanced Small Cabinet and the old runs are left with free ends. Place it back and explicitly reconnect. Its board and output modes should still be present. Pick up and replace the vanilla lamp with the normal moveable tools. Reattach its run and check that the saved adapter circuit resumes.
3. Route two independent circuits across a shared tile using normal placement. Include a bend if there is room. Hover the numbered wires to check that the cyan outline follows the exact segment. Use native **Pickup** to remove one wire. Expect one item back and only that route to lose signal. Use an active run to reconnect a compatible existing free end, and confirm an attempted join between two driven runs is rejected. Verify name and reading when the repaired run is inspected.
4. Leave the game running for the final console capture. Report reload, selective pickup, and any unresolved error, visual issue, or skipped case.

## Verification baseline

The Windows package contains 51 files. All 832 offline Lua checks passed using installed Build 42 Lua wrappers with simulated game objects. The six checkpoints above cover native crafting, live placement, graphics, power, and save reload in Project Zomboid.
