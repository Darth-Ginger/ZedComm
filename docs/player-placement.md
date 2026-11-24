# ZedComm Player Guide

ZedComm adds wired electronics to Project Zomboid Build 42 singleplayer. Craft parts under **Crafting > ZedComm**. [Recipes and Electrical requirements](recipes.md).

## Place and wire a circuit

For physical actions such as placing a device or fitting an adapter, your character walks to a reachable tile before starting work. If every approach is blocked, the action stops.

1. Use native **Place** and **Cycle through objects** to select a source and a receiver. For a first circuit, use a Pressure Plate and a Numeric Display.
2. Cycle to **Signal Wire**. Click a free device jack and choose **Connect to**. If the jack tile cannot take wire, choose a valid neighboring floor tile for the first segment.
3. Click neighboring tiles to extend the run. Click the receiver or another compatible free end and choose **Connect to**. Joining existing ends uses no spare wire. **Lay wire here** adds a segment when you have one.
4. To resume a run, right-click its end and choose **ZedComm > Select free end**. Your character walks within reach if needed, and native **Place** opens with Signal Wire selected. Right-click exits Place and keeps a reachable end selected for a context-menu connection. Walking out of reach clears that selection.
5. Use native **Pickup** to recover equipment or wire. A recovered device retains its settings and installed parts. External wires stay in the world, ready to reconnect.

On shared tiles, cycle through numbered wires or open a specific wire's submenu. Hover a choice to outline that segment in cyan. Up to five wire lanes can share a tile edge. Keep one source per run. Use a Splitter for one signal going to multiple independent runs.

## Mounts and passthroughs

- **Floor:** Place plates, displays and floor cabinets on clear tiles.
- **Tabletop:** Place or pick up a Tabletop Cabinet, display, or test byte source from the floor beside a clear table or counter. Their jacks can be wired from the adjacent floor.
- **Wall:** With a Network Switch or Wall Cabinet in Place, hold left-click and drag toward an eligible wall face, then release. Click a placed switch within reach to toggle it.
- **Wall passthrough:** At a solid wall, choose the wall's ZedComm submenu and **Drill passthrough** with a Hand Drill. Select a local free end, then use **Feed wire through** or **Connect to wire** to join an existing far-side end. A fitting carries up to five independent runs. Add a cover with a Screwdriver and a Plastic Tray or Scrap Metal. Free all crossings before sealing. The wall still blocks movement.

## Sources and readouts

| Device | What it sends or shows |
| --- | --- |
| Pressure Plate | A configured value from 1 to 255 when occupied, 1 by default. Players, zombies, animals, bodies, vehicles, loose items and qualifying floor furniture can trigger it. Clear sends 0. |
| Occupancy Plate | Number of players and zombies on the tile, capped at 255. Clear sends 0. |
| Weight Plate | Estimated load from actors, bodies, vehicles, loose items, floor furniture and contents. Basic uses rounded 10 kg steps, with a minimum of 1 for positive load and a cap of 255. An Advanced Sender, selectable in debug, sends estimated kilograms plus the Basic fallback. Seated actors add no separate body-weight reading. |
| Network Switch | 255 on and 0 off. |
| Door and Window Contact | 255 closed, 0 open. An unavailable host sends no signal. |
| Numeric Display | Shows the byte. Zero is a valid reading. A wired display with no live signal shows dashes. An unwired face is blank. |
| Advanced Display | Shows Basic bytes or the typed weight in kilograms. **Read full signal** gives the exact reading when the face rounds or shows **HI**. |

To change a Pressure Plate's occupied value, right-click it and choose **ZedComm > Plate > Set pressure plate output**. Use **Read numeric display** or **Read full signal** to inspect a receiver.

## Additional sensors

| Sensor | Use |
| --- | --- |
| Time-of-day | Choose **Set daily schedule** and enter two times as **HH:MM, HH:MM**. It sends 255 from the start up to the end. A schedule can cross midnight. Equal times leave it off. |
| Power | Sends 255 when the tile has grid or generator power, and 0 without it. A NOT module can signal a power cut. |
| Daylight and Rain Intensity | Place under open sky. They send outdoor light or rain strength as a byte. Sheltered conditions read zero. The rain sensor also reads zero in snow. |
| Storage | Fit to a supported crate or shelf, choose its compartment, and select **Fullness** or **Free capacity**. The reading follows the native inventory capacity scale. |
| Fluid Fill | Fit to a vanilla wooden Rain Collector to read its fill percentage as a byte. Native filling and draining control the contents. |
| IR proximity | Set the radius to 1-10 tiles and choose player, zombie, or both. Fixed sends a configured byte, Count sends the count, and Nearest increases as the nearest visible actor approaches. Walls and closed doors block detection. |

## Cabinets and local circuits

An **adapter** connects the fixture to the wire. A **module** processes a signal or adds a connection inside a board. Basic cabinets handle bytes. Advanced cabinets can handle full readings and let you configure each output's signal mode. Small and Tabletop cabinets use 6x6 boards with one fixed IN/OUT pair. Large and Wall use 8x8 with two pairs, and XL uses 10x10 with three.

Double-click a nearby cabinet, choose a carried module and drag it onto the grid. Rotate removable parts with **Rotate Building**. Port extensions and Splitters must sit at an edge with their external jacks facing out. Link an output contact to an input contact, and complete the path to a board output. Right-click a link to remove it. Right-click a part to configure or remove it. Fixed jacks stay in place. The board supplies internal links, while external connections use Signal Wire.

Threshold and Boolean logic emit 0 or 255. Use **Cache** to pass the original reading through when you need its precision. Use **Full Reading** on compatible Advanced arithmetic modules to operate on typed weight. A timed Wait or Timer shows seconds remaining in the editor. A placed Basic cabinet can be upgraded with an Advanced Adapter while retaining its board and runs.

## Retrofit a vanilla lamp

With a Screwdriver, fit a **Basic Adapter** at Electrical 1 or **Advanced Adapter** at Electrical 3 from the lamp's ZedComm submenu. An Advanced Adapter has a 3x3 local board. Use **Check lamp status** in the lamp's ZedComm submenu to check the bulb, power, and adapter status. A wired lamp follows the signal and switches off on signal loss. Unplug it or remove the adapter to restore manual control. Native pickup retains the installation but leaves the wire behind.

## Doors and contacts

Fit two matched Basic or Advanced Adapters to a supported native door. The shared 6x3 board has independent **Lock IN** and **Open IN** controls. Lock ON blocks new openings and waits if the door is already open. Open ON opens an unlocked door, and a valid 0 closes it when the door can move. Loss of signal unlocks a connected Lock input and releases Open to manual. Physically disconnecting Lock restores the original native lock state. Install a Door or Window Contact separately when you need the fixture's actual state as an output.

## Names, access and overlays

Rename fixtures and runs through their ZedComm submenus. Rename a jack by right-clicking it in the editor. Blank names restore the default. Hover a cable choice to identify it before joining or picking it up. **Options > Mods > ZedComm** controls fixture and wire labels and door status markers.

Use a vanilla Padlock on a cabinet or a door board. A matching key grants access. **Remember me** also grants access to the survivor who fitted it. Protected circuits keep running. Remove the lock before upgrading or picking up a cabinet or removing door adapters.

## Example circuits

- **Plate readout:** Pressure Plate -> Numeric Display. Expect the configured value while occupied and 0 when clear.
- **Vehicle-triggered lamp:** Weight Plate -> Threshold in an Advanced Lamp Adapter -> lamp. A threshold of 50 separated the tested 80 kg player (byte 8) from the sheriff car (byte 115). Measure both in your save before selecting a threshold.
- **Crate-key door:** Feed two Weight Plates through separate Threshold modules. Put a Pressure Plate under a crate and feed its signal through NOT. AND all three conditions, then wire the result to **Open IN** with Lock IN unwired. The door opens when both weight conditions pass and the crate is removed.
- **Timed door:** Pressure Plate -> Wait (2 seconds) -> Timer (10 seconds) -> **Open IN**. Steady pressure triggers a ten-second open request. Step off to rearm. This combines separately tested timing modules and still needs an end-to-end door check.
