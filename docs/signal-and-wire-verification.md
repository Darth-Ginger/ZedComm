# Signal simulation and wire shapes

The pressure plate publishes occupancy without acknowledgments. It sends 0 when empty and its configured byte when occupied, with a default of 1. In debug singleplayer, the byte test rig uses a separate source that accepts any whole decimal byte from 0 to 255. Its configured byte persists in the registry. **Inspect circuit** reports connectivity, the current source byte and the actual receiver reading together. Valid zero and no signal remain distinct. The definition's optional `onUnavailable` handler can override the default OFF path. The unloaded-source policy is recorded in ADR-303.

Wire shapes are derived from explicit saved links. A segment draws toward each linked neighboring tile, with matching ends on the shared tile edge. A pair of opposite directions forms a straight, a pair of perpendicular directions forms a bend, and a single direction leaves a capped end. A piece with no linked neighbor draws as a short stub. A connection to a device on the same tile has no directional leg. Adjacency alone leaves the two sprites separate. Cutting, repairing and loading a square refresh the shape. The first three sprite IDs are unchanged for existing saves.

## Offline verification

All 271 Lua 5.1 checks passed with `next = nil`. The 16 added checks cover byte delivery and the circuit inspector, no-signal fallback and recovery, and wire shape changes on disconnect, reconnect, square load and save/reload. The installed Build 42 pack reader opened all 14 sprite entries and the mod packaged successfully. A further 18 checks bring the total to 289. These cover shared-tile placement, per-wire actions, hover and cleanup, isolation, pickup and reload. World alignment, the debug menu and shared-tile actions await in-game verification.

## In-game check

Fully restart PZ in debug mode with ZedComm enabled. Use a disposable singleplayer save or the previous test save.

### Group 1 — mixed bytes and signal loss

1. On three clear tiles in a row along increasing X, choose **ZedComm → Debug → Place wired byte test rig** on the first tile. The source, wire and display occupy those tiles in order.
2. On the source choose **Set test byte**. Try **85** (0x55), **170** (0xAA), and **0**. The live display should show the same numbers. **Inspect circuit** on the display or wire should show the source and receiver values together. Check that 0 is a valid reading.
3. Set the byte to 170 again. Use **Toggle test source link** on the source. The display should show **---** and the inspector should report no signal. Reconnect without changing the configured byte. Expect 170 again.
4. Leave the game running for the first console snapshot.

### Group 2 — wire shapes and persistence

1. Inspect the existing player-built circuit or make a run with a straight and a bend. Check that the shapes meet at tile boundaries, the corner follows the route and loose ends are visible.
2. Cut one wire and check that the neighboring sprites end at the cut. Repair it and check that the connected shapes return. Place or route an unconnected wire beside the circuit to verify that proximity alone does not join the artwork or the signal.
3. Save and reload. Check that the shapes rebuild, the circuit works, and the byte rig still reads 170 if left connected. Leave the game running for the final console snapshot.

### Group 3 — two circuits on one tile

1. Find five clear tiles in a plus shape. Place pressure plates west and north of the center, and displays east and south. Start the west run and lay its wire in the center. Connect that wire to the east display.
2. Start the north run and choose **Lay another wire here (1 present)** on the center tile. Connect this wire to the south display. Under **ZedComm**, hover each numbered wire submenu and its actions. Only that wire should tint, and the tint should clear when the menu closes. Use **Inspect** to distinguish the east–west and north–south links.
3. Step on each plate separately. Only its own display should show the plate’s occupied output (1 by default). Save and reload with both connected, then repeat the check. The numbered entries should still point to the same routes.
4. Inspect the center wires, then choose **Pick up** inside the east–west wire’s submenu. Confirm it returns one inventory unit, the east display is now unattached, and the north plate still drives the south display. Leave the game running for a console snapshot.

The two sprites may overlap. Use the numbered menu and link directions to identify the wire for this test.
