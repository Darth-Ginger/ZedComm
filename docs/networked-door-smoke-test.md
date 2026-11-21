# Networked door smoke test

Use [the compact results sheet](door-smoke-results.md) to record each check and console capture. Offline results are recorded in [door controls and API research](research/networked-door.md). Run on Build 42.22.2 in singleplayer with ZedComm enabled. Fully restart PZ after loading this build. Do not use a double door or garage door.

## Setup and grants

Choose a single-panel map door with clear access on both sides. Also build an ordinary single-panel wooden door for the second native class. Use disposable test doors for destruction. In the fresh-save combined run, build these rigs on the new save. Keep one working door outside the destruction tests for the concealed pressure plate check.

Use the debug character/skills editor to set Electrical to 3. Basic installation requires Electrical 1 and Advanced requires Electrical 3. Both require a screwdriver and two matching adapters in the main inventory. Instant timed actions may be enabled for setup, then disabled for the interruption check.

Paste the grants separately into the Lua console as needed.

```lua
getPlayer():getInventory():AddItem("Base.Screwdriver")
getPlayer():getInventory():AddItems("ZedComm.BasicAdapter", 4)
getPlayer():getInventory():AddItems("ZedComm.AdvancedAdapter", 4)
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 30)
getPlayer():getInventory():AddItems("ZedComm.DebugByteSource", 2)
getPlayer():getInventory():AddItems("ZedComm.DoorContact", 3)
getPlayer():getInventory():AddItem("ZedComm.NumericDisplay")
getPlayer():getInventory():AddItems("ZedComm.WaitModule", 1)
getPlayer():getInventory():AddItems("ZedComm.NotModule", 2)
getPlayer():getInventory():AddItems("ZedComm.AndModule", 3)
getPlayer():getInventory():AddItems("ZedComm.ThresholdModule", 2)
getPlayer():getInventory():AddItems("ZedComm.WeightPlate", 2)
getPlayer():getInventory():AddItem("ZedComm.PressurePlate")
getPlayer():getInventory():AddItem("ZedComm.SmallCabinet")
getPlayer():getInventory():AddItems("ZedComm.InputExtension", 2)
getPlayer():getInventory():AddItems("Base.LeadPipe", 2)
```

Verify the loaded code before starting.

```lua
print("ZedComm door loaded", ZedComm.Door ~= nil, ZedComm.DoorInstallation ~= nil)
```

Expect both values to be `true`. If either is false, stop and check the Workshop package before testing behavior.

## Checkpoint 1 - independent actuators

1. With instant actions disabled, right-click the map door and choose **ZedComm > Door > Install two Basic Adapters**. Interrupt by walking away. The door must stay unmodified and both adapters must remain. Retry and finish. Expect two adapters consumed and the screwdriver retained.
2. Place two Test Byte Sources on separate nearby tiles. Right-click each under **ZedComm > Source > Set test byte** and set both to `0`. Run one separate wire from each source to the door. Choose **Lock IN** for one and **Open IN** for the other. Label the runs Lock and Open. They must remain separate networks.
3. Check the attached maglock housing on both north, west, south and east mounting faces. It must stay aligned through opening/closing, preserve the original door sprite, and show independent Lock/Open cable tells. Its amber indicator follows the actual native lock, so an unlocked door with a pending lock stays unlit. Remove the adapters and confirm the housing disappears. Refit for the remaining checks. Open **ZedComm > Door > Open Door Board**. Expect a 6x3 board, two fixed inputs and two local action outputs with direct links. Basic is read-only. The top line shows actual open/closed and locked/unlocked state. Hover each action for application or pending status.
4. Set Open to `255` and keep Lock `0`. The door opens. Leave the signal steady and confirm no repeated toggling. Try to close it manually. While controlled it should reopen to the held request. Set Open to `0`. It closes.
5. With the door closed, set Lock to `255`, then Open to `255`. It stays closed and locked. Try normal manual interaction from both sides, including with a matching key if available. It must not remain open or allow passage. Record any flicker, unexpected sounds or animation.
6. Set Lock to `0` while Open remains `255`. It unlocks and opens. Set Lock back to `255` while already open. It must stay open with **Lock pending until the door closes**. Then set Open `0`. It closes and locks. The Lock input alone must never initiate that closure.
7. Keep Lock cable connected to the door, but disconnect its source. Expect unlock. This differs from physically unwiring the Lock jack, which restores the native lock flags from before installation. With the Lock request off, set Open to 0 and confirm the door closes. Disconnect the Open source while its door cable stays attached and verify manual operation returns at the current position. Physically unwiring Open IN also restores that action's native control.
8. Repeat steps 4-7 on the player-built single-panel door. The two native door classes must behave the same. Test an obstruction and, separately, a barricade while a request would move the door. It must remain pending, then reconcile the latest request once the blockage is removed. Check that the sprite, lighting and walkable path agree with actual state.

**Pause for console capture before reloading.** Report the door classes, both-side result and any blocked-action result. Keep the rig in place.

## Checkpoint 1 retest - interaction and visibility

1. On the Basic rig from Checkpoint 1, set each Test Byte Source to a different byte. Confirm the source face shows its configured value even when unwired. Change one to `255` and then `0`.
2. Rename a source and a fitted door. Use **Show name label** in each fixture's submenu, then **Hide name label** on one. After reload, verify both settings persist.
3. In **Options > Mods > ZedComm**, toggle **Show fixture name labels** and **Show door status markers** independently and apply. Turn both off, then on. Check that both settings persist across a game restart and that only fixtures with individual labels enabled regain their labels.
4. Enable **Enable double-click configuration** on a Test Byte Source. Double-click it while nearby and verify the menu can set its byte or rename it. Disable the option and verify a double-click no longer opens the menu.
5. With the door closed, set Lock to `255` and Open to `255`. Try opening by mouse from both sides. Repeat with Lock and Open both `0` to test the held Close request. In both cases the mouse action should be blocked before it animates. Check the native context key separately and record any flicker or sound.
6. With Lock at `0`, drive Open from `255` to `0`. Verify silent closure and check the sprite, lighting and passage. From both sides of a north-facing door, verify the maglock marker shows the actual lock and door state.
7. If the barricade is still in place, keep Open at `255` and remove the barricade. Verify the held request opens the door after clearance.

## Checkpoint 2 - shared Advanced board

1. Unwire or set both sources to `0`. Bring two Advanced Adapters and the screwdriver. Remove the Basic door adapters through its Door submenu. Expect two Basic Adapters returned and the native door retained. Fit two Advanced Adapters, then reconnect the Lock and Open runs to their matching inputs.
2. Open the Door Board. The fixed Lock IN occupies column 1 rows 1-2. Open IN occupies columns 2-3 of row 3. Lock actuator occupies column 6 rows 1-2. Open actuator occupies columns 4-5 of row 3. None can be moved or rotated. The Advanced palette should offer logic, arithmetic, Cache, timing and power parts, with no extra input/output extensions or external Splitter.
3. Drag Wait into column 2 row 1, NOT into column 3 row 1 and AND into column 4 row 1, all vertical. Set Wait to `1` second. Verify the ghost sprite and contacts rotate with the normal rotate binding, then leave the three modules in the listed positions. A module extending below row 3 or overlapping a fixed part must be refused without consuming it.
4. Remove the direct Open IN-to-Open action link by right-clicking it. Keep Lock IN-to-Lock action. Add these five links. Lock IN OUT to Wait IN. Wait OUT to NOT IN. NOT OUT to AND B. Open IN OUT to AND A. AND OUT to Open action IN. Lock IN now fans out internally without a Splitter.
5. With Lock `0` and Open `255`, expect an open door. Set Lock to `255`. It must initially remain open with a pending lock and a visible Wait countdown. After roughly one real second of unpaused simulation, Open action goes OFF, the door closes and Lock applies. Pause must stop the countdown. Set Lock `0` with Open still `255` and expect it to reopen.
6. Rename the door and each physical input jack through the context menus. Reopen the board and confirm names, links and ports still identify the correct functions. Hover action outputs for their actual application status. They must not offer external wire connections or an Advanced transmission toggle.
7. Try adapter removal with a full main inventory. Expect refusal, complete board and wires retained, and no partial item return. With room available, remove successfully. Expect both Advanced Adapters and all three modules back. Refit and reconstruct the rig for the reload check. A direct two-adapter upgrade action is outside this implementation, so use removal and refitting to change tier.

**Pause for console capture before reloading.** Report countdown accuracy, delayed closure and editor layout issues.

## Checkpoint 3 - reload, destruction and secret door

1. Leave the fitted door and named runs in place with the Advanced circuit saved. Exit to menu and reload. Verify the adapter tier, layout, labels and both independent connections. Source readings must be sampled again. A pending Wait restarts rather than continuing a saved countdown. Repeat the delayed-close sequence.
2. Destroy a disposable fitted map door, then a fitted player-built door. Their cables must remain placed with free ends. The removed door must disappear from the network and fixture menus. Place a new door at the same location and confirm it starts unmodified. Check the console for stale-object errors.
3. Build the secret-door cabinet. Connect two Weight Plates to separate cabinet input jacks and the basic Pressure Plate to a third jack, using the two Input Extensions. Use one Threshold on each weight input, both set to `1`. NOT the basic plate. AND the two threshold results, then AND that with the inverted basic plate. Connect the final AND to the cabinet output and run that output to the door's Open IN. Leave Lock unwired and ensure the native door is unlocked.
4. Put one Lead Pipe on each Weight Plate and a crate on the basic plate. The door stays closed. Remove the crate and expect the door to open. Remove either pipe and expect closure. Replace it and expect opening. Replace the crate and expect closure. A valid OFF closes the door. Loss of the cabinet output releases Open IN to manual control while its cable stays attached. This tests qualifying loads, not a player-only identity rule.
5. Reload with the secret-door layout saved and repeat the condition changes. Confirm native manual control returns when Open IN is physically disconnected. The cabinet and the door remain separate boards and networks. The door emits no contact-sensor feedback packet.


## Checkpoint 4 - independent contact source

1. Grant a contact with `getPlayer():getInventory():AddItem("ZedComm.DoorContact")`, or craft one under ZedComm using one Basic Adapter, one Electronics Scrap and one Electric Wire/roll-wire unit with a screwdriver and Electrical 1. Stand beside an unmodified single-panel door and select **ZedComm > Door > Install contact sensor only**. The native door must retain normal manual operation and have no actuator board.
2. Select the **Door Contact** fixture's free end and wire it directly to a Numeric Display. Expect closed `255` and open `0`, including manual operation. Locking a closed door must leave the reading at `255`. Check its dedicated sensor/magnet housing, hinge-jamb riser and separate floor lead. The two pieces show closed/open position without replacing the native door sprite.
3. Fit two actuator adapters to that same door. Keep the contact output on its own run. Open/close it through the receiver and verify that Contact follows actual position, not the requested value. An obstructed movement must leave Contact at the actual position. It needs no internal board links.
4. Remove the actuator adapters. Contact and its run must keep working. Refit inputs, then remove Contact. Both actuator input connections and the saved board must remain intact. Full main inventory must refuse removal without losing the fixture or its wire.
5. On a fresh door, bring the required matched adapter pair and a crafted contact. Verify **Install Basic inputs and contact** or **Install Advanced inputs and contact**, including interruption before completion. Successful fitting consumes the matching pair plus contact, retains the screwdriver and creates two independent named fixture menus.
6. Rename Contact and its run. Save/reload and confirm names, the separate connection and actual readings. Destroy a disposable fitted door and verify both source and receiver disappear while their wires remain as free ends. Repeat on a player-built door.

Pause for console capture at the end of this checkpoint. Native contact placement, save/reload and destruction remain unverified until these results are recorded.


## Window Contact follow-up

```lua
getPlayer():getInventory():AddItem("ZedComm.WindowContact")
getPlayer():getInventory():AddItem("Base.Screwdriver")
getPlayer():getInventory():AddItem("ZedComm.NumericDisplay")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 6)
```

1. At Electrical 1, stand next to an intact single native window. Choose **ZedComm > Window > Install window contact**. Interrupt once, then finish. The contact item is consumed on completion and the screwdriver is kept. The window should still work normally.
2. Wire **Window Contact** to the Numeric Display. Open and close the window. Expect valid `0` when open and `255` when closed. Check alignment and wire routing from both sides on north- and west-aligned windows.
3. Reload with the working circuit in place. Verify that the contact and its run persist and that the display reflects the loaded sash position.
4. Smash a fitted window. Expect the display to show no signal. Use **Remove window contact** to recover the sensor and free the wire end. A smashed or glassless window must refuse new fitting.
5. Remove the native host on a disposable second fixture. Verify that the registry clears the contact and leaves the wire run disconnected.
