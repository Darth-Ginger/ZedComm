# ZedComm combined singleplayer smoke test

Use this for the module integration, shared-tile wiring and lamp retrofit. The earlier floor-layer and overhead-display fixes already passed in-game. This run checks the new behavior and reloads once.

## Setup

Fully restart PZ in debug mode with the linked ZedComm mod enabled. Use a disposable singleplayer save or a copy of the prior test save. Use separate nearby areas for the byte rig, the crossing and the lamp. Grant prototype items as needed from the Lua debug console:

```lua
getPlayer():getInventory():AddItems("ZedComm.PressurePlate", 3)
getPlayer():getInventory():AddItems("ZedComm.NumericDisplay", 2)
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 12)
```

For the lamp test, find a powered vanilla table or floor lamp with a bulb and a clear adjacent tile. A battery-powered lamp makes the power interruption easy to repeat using the native battery actions.

## Checkpoint 1 — mixed bytes and shared wires

1. **Byte readout.** On the first of three clear tiles along increasing X, choose **ZedComm → Debug → Place wired byte test rig**. At the source use **Set test byte** to send 85, 170, and 0. The live display should show each exact value. **Inspect circuit** should show matching source and receiver values. A valid 0 is a reading.
2. **Loss and recovery.** Set 170 again, choose **Toggle test source link**, and expect no signal in the inspector and `---` on the display. Reconnect without changing the configured byte. Expect 170 to return. Leave it connected at 170 for reload.
3. **Shared tile.** Make a plus shape on five clear tiles. Put plates west and north and displays east and south. Build west → center → east first. Start the north run and choose **Lay another wire here (1 present)** on the center tile, then connect south. The two center wires should remain independent.
4. **Wire shape and selection.** Verify that the two straight routes meet their neighbors at tile edges. If an existing bent run is nearby, inspect its corners and capped free ends. On the crossing tile hover **Wire 1 of 2**, **Wire 2 of 2**, and their child actions. The appropriate segment should show a bright cyan outline. Move between the numbered wires and their child actions, then close the menu. The outline should follow the hovered wire and clear when the menu closes. Check for hover errors in the console capture. Use **Inspect** to distinguish directions. Each pressure plate’s terminal should face its own cable. Walk over a plate and confirm it draws below your character. Overlapping art may still obscure parts of a wire.
5. **Isolation.** Step on each plate separately and confirm only its own display reads the plate’s occupied output (1 by default). Leave both circuits connected for reload.
6. Pause with the game running for a console snapshot.

## Checkpoint 2 — relay lamp before reload

1. **Install and wire.** At a modifiable powered lamp choose **ZedComm → Install test relay**. Put a pressure plate on an adjacent tile. Start the wire from the plate and lay one segment on the plate tile if the floor is clear. Connect the free end to the relay lamp. This arrangement lets you stand on the plate while reaching the lamp. Check that the relay housing appears on the lamp and the lead points toward the wire. If the wire shares the lamp tile, look for a short lead instead.
2. **Wire authority.** Step onto the plate. The lamp should turn on once and stay on. Try the native switch while the wire is attached. It should have no effect. Step off and expect the lamp to turn off. If the native menu still shows the switch, that is expected for this prototype. The action is guarded.
3. **No source.** Pick up the pressure plate while the lamp remains connected to the wire. The lamp should go off and remain under wire control. Put the plate back and check for an empty socket. Reconnect it and verify the current input works again. For a same-tile cable, the plate should show a short lead. If you reconnect it to a neighboring cable on another side, check that the terminal follows the new connection.
4. **Power recovery.** On a battery-powered lamp remove its battery, stand on the plate and then restore a charged battery while the plate remains occupied. The lamp should follow the held ON without a new input. Repeat with the plate vacant before restoring power. It should stay off. If only a grid lamp is available, remove and reinstall its bulb to exercise the same availability transition. Report that as a bulb test, since it does not verify actual power interruption.
5. **Detach.** Use **Disconnect relay wire**. The native switch should work again and the relay housing should show an empty socket. Reconnect the wire so the relay is attached for reload. If you have a free wire on a different side, use it briefly to verify that the lead follows the new connection.
6. Pause with the game running for the pre-reload snapshot. Then save and quit to the menu when the snapshot is captured.

## Checkpoint 3 — one reload, then selective pickup

1. Reload the same save. Check that the byte rig still shows 170 and each crossing plate drives only its own display. The wire shapes and numbered submenus should still match the two routes. Both plate terminals should face their saved wire connections.
2. On the crossing tile use **Inspect**, then **Pick up** inside just one numbered wire submenu. Confirm one wire item returns, its display becomes unattached, its plate shows an empty socket, and the other circuit still works.
3. Check the relay lamp still follows the plate with no new installation or reconnection. Its housing should show one lead in the saved direction. Pick it up with the normal PZ moveable pickup. Its cable should remain with a free end. Place the lamp again within reach of that wire. The relay lamp should offer a free end without a new install. Reconnect and verify switching again.
4. Leave the game running for the final console snapshot. Note whether the power recovery test used a battery, another real power source, or a bulb.

## Offline baseline

All 379 Lua 5.1 checks passed, including the relay behavior checks, 10 module housing checks, and nine pressure plate visual checks. A scratch mod build passed. The tests use installed PZ Lua wrappers and simulated lamp and inventory objects. Actual PZ lamp behavior, rendering, and moveable pickup are covered by the checkpoints above.
