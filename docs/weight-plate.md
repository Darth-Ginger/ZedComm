# Weight plate

## Player behavior

**ZedComm Weight Plate** is a floor-placeable source with one `signal` port. With Basic Sender, it sends an estimated load as a byte from 0 to 255. Native **Place** and **Pickup** and the existing ZedComm context actions work with the new item. With wire selected, click the plate and choose **Connect to weight plate**.

The reinforced deck has its own icon, an empty socket, a centered lead for a same-tile connection, and four directional lead sprites. The lead follows the linked wire.

## Provisional calibration

The plate totals the load on its tile, then rounds to the nearest 10 kg step. A positive load sends at least 1. The byte caps at 255 and an empty plate sends 0.

| Load | Example output |
| --- | --- |
| Clear tile | 0 |
| Standard crate, pickup weight 7.5 | 1 |
| Standard crate with 20 units of stored weight | 3 |
| Floor-standing shelf, pickup weight 20 | 2 |
| 80 kg on-foot player | 8 |
| One zombie, estimated at 75 kg | 8 |
| Both of the above, summed before rounding | 16 |
| 1,200 kg vehicle | 120 |

The runtime reads player body weight from the game's nutrition API. It uses 75 kg for each zombie and as the player fallback if nutrition data is unavailable. The first pass measures the vehicle reported by Build 42's square overlap lookup and uses its full reported mass while its footprint overlaps the plate. This models vehicle presence and relative load at the tile level. A driver or passenger contributes no separate on-foot weight. Qualifying floor-level furniture contributes its empty pickup weight plus the weight of items stored in its compartments. The runtime reads the tile's explicit PickUpWeight property and divides by 10, following the native Moveables conversion. It adds Build 42's contents weight for each compartment, which includes the contents of stored bags. For furniture without a pickup weight, the estimate uses the contents alone. Animals and loose floor items contribute zero.

A future threshold receiver could trip at a byte such as 50 if the live vehicle and pedestrian readings bracket it. Confirm the readings with the numeric display in the target game before choosing the calibration for release.

## Debug sender selection

On a placed weight plate choose **ZedComm → Debug → Weight plate sender → Advanced Sender**. The plate sends its full estimated load in kg with the scaled byte as a fallback. The existing numeric display reads the fallback. Open **Inspect circuit** on the plate, wire, or display to compare the packet type, weight, fallback, and receiver reading. Choose **Basic Sender** in the same menu to restore the default.

The selected sender follows the plate through pickup and reload. Reconnect after replacement. See the [maintained signal packets plan](plans/maintained-signal-packets.md#phase-c---singleplayer-proof) for the fresh-save test.

## Wiring and persistence

1. Placement registers `ZedComm.WeightPlate` in the saved endpoint registry and exposes its `signal` port.
2. The runtime combines the on-foot actor estimate with `square:getVehicleContainer():getMass()` when a vehicle overlaps, plus qualifying furniture pickup weight and stored contents. The selected sender encodes the combined load and applies the byte conversion.
3. The wire carries the packet. The existing display reads the basic byte or the advanced sender's fallback through Byte Readout.
4. Reload restores the endpoint and links, then samples the current load. Pickup returns the weight plate and leaves the wire in place. Reconnect after replacement to resume the reading.

Frames 425 to 430 add the weight plate to the current pack. The earlier 425 frames keep their IDs, origins, pixels, and tile properties.

## Build 42 singleplayer smoke test

Restart PZ with the linked mod enabled. Use a clear stretch of road in the disposable save with room to park without touching the plate on the first pass. Add the items in the Lua debug console if needed.

```lua
getPlayer():getInventory():AddItem("ZedComm.WeightPlate")
getPlayer():getInventory():AddItem("ZedComm.NumericDisplay")
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 2)
```

1. Place the weight plate through native **Place**. Wire it to a display you can see from the road. Verify the plate renders on the road under the player and its lead points toward the connected wire. The clear reading is **0**.
2. Walk onto and off the plate. Record the occupied byte. A player weighing 80 kg should show **8**. If a zombie crosses the plate in a safe setup, its estimated contribution is also **8** alone.
3. Drive past without overlapping the plate. The reading should remain **0**. Drive across it slowly and park with the vehicle overlapping the plate. Try a position where the vehicle center is on another tile. The occupied byte should be substantially higher than the on-foot reading and stay high while parked.
4. Step clear of the plate with the car still parked, then drive away. Confirm the reading stays high with the car alone and clears to **0** when its footprint leaves. Use these observed bytes to confirm a threshold can separate the car from one pedestrian.
5. Pick up and replace the plate, reconnect it, then save and reload with the run connected. Confirm the reading responds without rewiring after reload. Keep the console for the combined build-cycle capture.

## Offline checkpoint

492 Lua 5.1 checks passed. Coverage includes rounding and saturation, player and zombie load, simulated vehicle overlap and departure, excluding the seated player as a separate load, native placement and pickup, reconnect, and reload. The installed Build 42 pack reader opened all 431 frames. The Windows build passed. The Build 42.22.2 road test observed 8 for the 80 kg pedestrian, 115 for the sheriff car, 123 combined, and 0 after departure. Furniture has separate offline coverage. Darth-Ginger confirmed the loaded-crate test in-game, and the startup console recorded 3 on the weight display. Console capture: furniture-plate-live-20261112-105033.txt.

## Furniture smoke test

Place a standard crate directly over a clear wired weight plate using native Moveables. Step away and expect **1**. Add about 20 units of items to the crate and expect **3** after stepping clear. Empty it and expect **1** again. Move it to the neighboring tile and expect **0**. A floor-standing shelf with a pickup weight of 20 should read **2**. Use the [basic plate check](player-placement.md#concealed-basic-plate-check) to verify a configured fixed output under furniture.
