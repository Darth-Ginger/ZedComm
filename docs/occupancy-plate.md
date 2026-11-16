# Occupancy plate

## Player behavior

**ZedComm Occupancy Plate** is a floor-placeable source with one `signal` port. It publishes the number of players and zombies on its tile as a held byte. An empty tile sends 0. Counts above 255 send 255. Animals, vehicles, and objects contribute zero in this chunk. The basic pressure plate still uses its configured occupied output.

Use native **Place** and **Pickup**, or the existing ZedComm context actions. With wire selected, click the plate and choose **Connect to occupancy plate**. The four-tread placeholder has an inventory icon, an empty socket, a centered same-tile lead, and four directional lead sprites. The visible lead follows the actual link.

## Wiring and persistence

1. The item registers through the existing placement system as `ZedComm.OccupancyPlate`.
2. Its source definition samples the tile's moving objects through the shared device runtime. The runtime distinguishes `IsoAnimal` from human players before the occupancy plate counts them. The basic plate preserves its previous behavior for the player class.
3. The existing sender publishes the byte to the connected run. The existing Byte Readout module shows that value on the numeric display. Cable loss leaves the attached display with no signal.
4. The registry saves endpoint identity and links with the existing save format. Reload samples the current occupants. Pickup recovers the same item type and leaves the run's wire in place. Reconnect after replacement to resume the count.

The pack adds frames 419 to 424 for the occupancy plate. The earlier 419 frames retain their IDs, origins, pixel regions, and tile properties.

## Build 42 singleplayer smoke test

Use the same disposable save after a full game restart with the updated development mod enabled. In the Lua debug console, add the test items if needed.

```lua
getPlayer():getInventory():AddItem("ZedComm.OccupancyPlate")
getPlayer():getInventory():AddItem("ZedComm.NumericDisplay")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 2)
```

1. Cycle to the occupancy plate in native **Place** and put it on a clear tile. Check the four-tread sprite draws under the player. Place a numeric display two tiles away and use the intervening tile for wire.
2. Start the wire at **Connect to occupancy plate**, lay the intervening segment, and click the display to connect. Check the lead points toward the actual wire. The display should read **0** with a clear plate.
3. Step on and off for **0 → 1 → 0**. Use a player and a zombie or two zombies to verify **0 → 1 → 2 → 1 → 0** as they enter and leave one at a time. Use the on-face reading or **Read numeric display**.
4. Pick up the plate with native **Pickup**. Confirm you receive an Occupancy Plate, the wire stays in place, and the display reports **no signal**. Replace and reconnect it. Verify the count resumes.
5. Save and reload with the run connected. Check the sprite and lead, then verify the count responds without reconnecting. Capture the console after the combined build-cycle smoke test.

## Offline checkpoint

472 Lua 5.1 checks passed, including the new definition, count saturation, animal and vehicle filtering, native placement and pickup, directional art selection, signal delivery, and reload. The sprite-pack comparison verified all 419 prior frames are preserved, and the installed Build 42 texture-pack reader opened all 425 frames. The Windows build passed.

## Build 42.22.2 live result

The plate counted one player, two with a dragged zombie, and responded to a live zombie in the follow-up. Placed crates and bookshelves left the actor count unchanged. Console capture: live-zombie-and-furniture-20261112-100529.txt.
