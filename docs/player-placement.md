# Player placement and wiring

In singleplayer, the native **Place** tool cycles through ZedComm pressure plates, numeric displays, and signal wire alongside vanilla moveables. The native **Pickup** tool can recover both endpoints and individual wire segments. The **ZedComm** world context menu also places devices, selects wire ends, and joins runs. The items use the generated placeholder icons and world sprites. Wire sprites follow their explicit links, including bends and free ends. The display shows its reading on the casing and can also be read from its context menu. See the [on-face display and combined smoke test](numeric-display-face.md).

Right-click a pressure plate, numeric display, or signal wire in the main inventory and choose **Place with ZedComm cursor**. Click a valid tile to walk there and place that item. The placement action holds the exact selected inventory item and validates the target again on arrival. The world context menu also offers immediate placement within reach. A clear floor tile can hold one device and multiple independent wires. Wiring follows the existing saved registry. A placed piece consumes one item only after registration and any required link succeed. Picking up a device preserves its identity and durable state on the recovered item and leaves connected wire in the world. Pickup of wire returns one unit. Choose **Select free end** to open the native tile cursor for an existing run. Click a valid neighboring floor tile to walk there and lay one segment. The cursor advances to the new segment after the action finishes. Right-click exits placement and keeps the current end selected for an explicit connection or the existing **Lay wire here** action. Moving out of reach of that end clears the selection. To resume an unfinished run, select its free end again.

## Native Place and Pickup

Use the normal **Place** tool and its **Cycle through objects** control to select the plate, display, or wire. The cursor previews the selected piece on the floor and walks to the clicked tile. After placing a plate or display, stay in Place and cycle to the next item. Normal stock of each ZedComm type appears once in the cycle. Recovered endpoints with saved settings can be selected individually.

Cycling to wire and placing the first segment starts a run. On a tile with a free end, choose **Place wire loose** or **Connect to** the specific end. Starting from an existing cable requires a neighboring tile for the first new segment. Subsequent clicks extend the active end or open the connection choices when a compatible free end is present. Cycling to another item releases that end. Right-click exits the tool and keeps the last reachable end selected for an explicit connection.

Native **Pickup** recovers a pressure plate or display with its settings. Its wire stays in place with a free end. Place the device again and reconnect it to resume the circuit. To recover wire, use **Pickup** on its tile. On shared tiles, cycle through the numbered cables and use the cyan outline to identify the selected segment.

## Starting from a loose wire

Click an empty floor tile with the inventory wire cursor to place a standalone segment. On a tile with a free device or cable end, choose **Place wire loose** or **Connect to** the exact end. A device can connect on its own tile when the floor is clear. For an existing cable or a fixture on a blocked tile, select the end and then click a valid adjacent tile. The connected segment becomes the new end of the run.

## Joining from an active run

With the cursor still laying a run, click a compatible free cable end or endpoint port. Choose **Connect to** the exact target to finish the run without consuming a wire. Choose **Lay wire here** to continue on a valid tile when you have another segment. Cable-to-cable connections use neighboring tiles. A device port can also connect to a cable on its own tile. When there are multiple targets, hover a cable choice to outline that segment in cyan.

| Starting point | Click target | Connection |
| --- | --- | --- |
| Wire selected in Place | Free endpoint port | Lay the first wire on the port's tile or a valid neighbor |
| Wire selected in Place | Existing run's free cable end | Select the end and lay the first new wire on a neighbor |
| Active run | Existing run's free cable end | Join the two existing segments |
| Active run | Free endpoint port | Join the current segment to the device |

## Run names

Connected runs get a saved number such as **Run 1**. Unconnected segments show **Loose wire**. Look for the name in connection choices, the native Place and Pickup info panel, and **Inspect wire**. On a shared tile, open the individual wire submenu to inspect it or choose **Rename run**. Enter a custom name to show it alongside the run number, or submit a blank name to restore the default.

When runs join, a custom name takes precedence over a default. If both names are custom or both are defaults, the active run keeps its name. If a run is split, the connected part with the saved name anchor keeps the old name and other connected parts get new numbers. If the anchor is removed or becomes loose, a surviving connected part keeps the name.

## Multiple wires on one tile

Select the free end of the intended run and left-click an occupied wire tile with the placement cursor. If the connection menu opens, choose **Lay wire here**. The new piece consumes one wire and connects only to the selected run. The context menu also offers **Lay another wire here (N present)** after you exit the cursor. On a shared tile, open **ZedComm → Wire 1 of 2** (or the appropriate wire number). **Inspect**, **Select free end**, **Connect selected run**, and **Pick up** appear inside that wire’s submenu when applicable. Hover a wire’s submenu or one of its actions to outline that exact segment in cyan. Inspect a wire to see the direction of its links and how many ends are free. Numbering uses saved piece IDs, so load order does not change it while the same wires are present. Picking up a wire removes only that segment. Parallel runs use up to five separate lanes across shared tile edges. Wires that turn together follow nested curves. A device lead keeps its centered connection and passing cables use separate lanes. Use the exact-wire outline when inspecting or picking up a segment.

## Pressure plate output

Right-click a placed plate within reach and choose **ZedComm → Set pressure plate output**. The menu and dialog show the current setting. Enter a whole number from **1 to 255**. The basic plate sends that value while an actor, an overlapping vehicle, or qualifying floor-level furniture occupies the tile. Placed containers and solid moveable furniture qualify. Floor tiles, decorations, loose inventory items, wall fixtures, and tabletop objects leave the plate clear. The output returns to **0** when the last load leaves. Plates without a saved setting use **1**, including plates from older saves. The setting survives reload and pickup followed by replacement.

### Concealed basic plate check

1. Wire a basic pressure plate to a numeric display and set its occupied output to **155**. The clear plate reads **0**. Place a crate or bookshelf directly over it using the native moveables tool, then step away. Expect **155** with only the furniture on the plate.
2. Save and reload with the furniture in place. Expect **155** before touching the furniture or wire. Move the furniture to the neighboring tile and expect **0**. Confirm the plate and wire remain intact and a nearby container or floor decoration stays clear.
3. Repeat with a vehicle on a road tile. The configured byte should hold while its footprint overlaps, even with the center off the tile. Drive clear and expect **0**.

## Occupancy plate

The occupancy variant uses the same native placement, pickup, and wire tools. It sends a live player and zombie count from 0 to 255. See [occupancy plate behavior and smoke test](occupancy-plate.md).

## Weight plate

The weight variant uses the same placement, pickup, and wiring tools. It sends an estimated load from on-foot actors and an overlapping vehicle. See [weight plate calibration and smoke test](weight-plate.md).

## In-game check

Restart Project Zomboid with the linked development mod enabled and open a disposable singleplayer save. These prototype items can be added through the Lua debug console. Recipes and final art are later work.

```lua
getPlayer():getInventory():AddItem("ZedComm.PressurePlate")
getPlayer():getInventory():AddItem("ZedComm.NumericDisplay")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 8)
```

### Group 1 — live build, repair and pickup

1. Open the default **Place** tool and cycle through a vanilla moveable, the pressure plate, the numeric display, and wire. Place the plate and display on floor tiles several steps away. Confirm the character walks there and places each selected item while the tool stays active. Cancel one placement while walking and confirm it stays in inventory. Plan an L-shaped route between the devices.
2. Cycle to wire and click the pressure plate. Check **Place wire loose** and **Connect to pressure plate**. Use **Connect to pressure plate** to start the run. Click each neighboring tile along the route. Check that the character walks there, one wire is consumed per successful placement, and the cursor advances around the bend. A click two tiles from the current end should leave the run unchanged. Walk out of reach manually and confirm the cursor closes. Select the current free end again to resume.
3. Left-click the display tile with the run still active and choose **Connect to numeric display**. Check that **Lay wire here** is also offered when you have wire and the tile can take a new segment. You can connect even after using the last wire in inventory. Use **Read numeric display** and check **0 → 1 → 0** as you step onto and off the plate. Before the explicit connection the display should report unattached, even if a wire is beside it.
4. Use native **Pickup** on a wire in the middle. Expect one wire back in inventory and **no signal** at the display. Select a remaining free end, lay the recovered piece in the gap, then connect to the other free end. Check that the signal returns.
5. Use native **Pickup** on the pressure plate. The cable stays in place with a free end. Cycle to the recovered plate in **Place**, put it down again, reconnect that end to it, and check the reading.
6. Cycle to wire and place the first segment on a clear tile. Check that the next click can extend it and that a tile beyond its neighbor gets a bold red outline. Cycle away and back to wire, click the original tile, and choose **Place wire loose**. Both wires should be independent. Cycle away and back again, click that tile, and choose **Connect to wire 2 / Loose wire from an adjacent tile**. Click the neighboring tile and confirm that only wire 2 connects. Build two independent runs over the same tiles, with at least one straight stretch and one bend. Follow each cable across the tile boundaries and around the turn. Check that the routes stay visibly separate. Use native **Pickup** to cycle through the two outlined segments. Recover one and confirm that only its circuit breaks.
7. Create two runs with free ends on neighboring tiles. Rename one from a wire's **ZedComm → Rename run** option. With the other run still active in **Place**, left-click the named run's end. Verify the label and cyan outline identify the correct cable. Choose **Connect to** and confirm the runs join without using another wire. Inspect a segment from each side and confirm both show the custom name.
8. With a plate and display wired, confirm the occupied reading defaults to **1**. Use **Set pressure plate output** to set it to **255** and check **0 → 255 → 0**. Set an intermediate value such as **77** while standing on the plate and check that the display updates without a new step. Leave it set for the reload check.
9. Leave the working runs connected and pause for a pre-reload console snapshot.

### Group 2 — reload

1. Save and return to the menu. Reload the same save and check that the devices and wire are still in place. Repeat the empty/occupied/empty display checks without reconnecting. Inspect the renamed run and confirm it kept the name and number. Check that the configured plate still sends its saved value when occupied.
2. Leave the game running and capture the post-reload console. Review `[ZedComm placement]`, `[ZedComm] display`, and registry entries for duplicate pieces, errors, or unexpected changes.

## Offline verification

All 458 offline Lua checks passed. The native bridge checks exercise the installed game's Moveable cursor, tile-building event, and walk-action callbacks with a simulated world. Coverage includes vanilla delegation, endpoint placement and pickup, saved settings, cycling, starting and extending a run, shared tiles, exact connection choices, and run names through merges, splits, and reload. The plate tests cover the default, input validation, immediate delivery while occupied, the maximum byte, and persistence through reload and pickup. The Windows scratch build passed. The active-run join passed in-game. The player confirmed that joined runs retained their names and carried signal after reload. The post-reload console shows the default plate output changing between 0 and 1, a rejected entry, and a custom output of 155 reaching the display. The player confirmed the final configured-plate check with 155 while occupied and 0 when clear. Zombie activation also passed. This completes the current placement smoke test.
