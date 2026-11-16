# ZedComm first-release art inventory

Planning estimate for a Project Zomboid Build 42 singleplayer release. The first group covers the current devices and the next build cycle. The second group is a procurement estimate for designs discussed so far. Order those assets once their gameplay and release scope are settled.

## Current build and next cycle

| Asset family | Art to procure | Implementation notes |
| --- | --- | --- |
| Basic, occupancy and weight pressure plates | Three recognizable floor bodies and inventory icons. Give the basic plate a slim mat, the occupancy plate a distinct tread pattern and the weight plate a reinforced load-pad silhouette. | Match the floor anchor and cable socket. Plan for idle and active appearance if the final art uses a visible state. Share terminal artwork where dimensions permit. |
| Numeric display | Casing with a blank screen face, inventory icon, a readable 0–9 glyph set, and artwork for unavailable input and the indicator. | Keep the casing separate from the live digit layer. Supply three slot positions or a face rectangle for each supported orientation. A zero reading and an unavailable input must look distinct. |
| Signal wire | Floor cable stroke and material palette, visible cap/plug, device terminal and inventory icon. | Generate straight runs, bends, lane offsets and perpendicular crossovers from shared art and geometry. Every linked edge needs the same lane position on both sides. Test five parallel lanes and stacked crossings. |
| Clip-on relay | Mounted housing and inventory icon if the relay becomes a player item. Supply unplugged socket, centered lead and directional lead treatment. | Reuse the native lamp body. Verify standing, tabletop and moved lamps before finalizing mount positions. |

## Discussed candidates

| Asset family | Art to budget | Design decision that affects the order |
| --- | --- | --- |
| Manual network switch and momentary button | Switch and button bodies and icons, with clear on/off and released/pressed states. | Choose wall versus floor placement and orientation coverage. |
| Tripwire | Anchor and terminal art, line material and inventory icon. | Set placement height, allowed span and armed/triggered visual treatment. |
| PIR sensor | Housing with a recognizably ribbed lens, wall orientations, terminal and inventory icon. | Set mounting and detection direction, and decide whether an armed indicator is visible. |
| Noisemaker, TV and compatible lamps | Connector or receiver housing plus fixture-specific mount art where needed. | Use the existing game devices. Scope the Noisemaker and TV adapters before requesting attachment variants. |
| Doors, windows and ladders | A mounted contact sensor, actuator or lock housing where the adapter calls for one. | Reuse native fixtures. Set the supported actuation and sensing for each. The hidden-plate door lock only needs new visual art if it has a visible actuator. |
| Sender, receiver, comparator and logic modules | A shared module housing family, distinguishable icon or face marks, and port overlays. | Define port count and per-module layout for AND, OR, XOR, thresholds and any byte-specific modules before commissioning separate designs. |
| Hubs, repeaters, network switches and cabinets | Shared enclosure vocabulary, ports, cabinet states, and slot/module icons if there is a cabinet UI. | Budget wall-mount, freestanding floor, and sideways tabletop cabinet bodies. Set anchors, terminal positions, and which forms ship before ordering state and orientation variants. |

## Artist handoff

- Use the current Build 42 pack's 128 × 256 logical tile cell as the world-art reference. Deliver transparent layered masters and PNG exports with documented pixel bounds, floor or wall anchors, and cable port positions. Supply a separately readable inventory icon where the asset is a player item.
- Match the grounded isometric view and muted 1993 electronics style. Check silhouettes and display digits at native scale and through the in-game zoom range.
- Keep visual state changes on separate layers where feasible. The display housing needs one blank screen and a digit layer. Wire bends and offsets need a consistent stroke and endpoints. This keeps replacement art manageable.
- Confirm final wall/floor/surface mounts, alternate orientations and state counts in a Build 42 prototype before commissioning the full variant set.

Generated placeholder sources go in `art/first-release-concepts/`. The existing basic plate, wire and display source art stays in `art/placeholders/`. The new source images need scale, anchor and in-game checks before packing.


## Connection and activation variants

| Asset | Connection states | Activation states |
| --- | --- | --- |
| Pressure plates | Empty socket and attached lead. Follow the cable on its actual tile edge; include the centered same-tile lead. | Idle and occupied or depressed. Keep the footprint and socket aligned across states. The weight plate may use a small status indicator if the deck barely moves. |
| Manual network switch | Shared terminal art with direction chosen by the connected cable. | Toggle up/down with a clear silhouette at native scale. |
| Momentary button | Shared terminal art with direction chosen by the connected cable. | Released and pressed with a steady lit tell for the active pulse. A flash can alternate the same lit and unlit indicator frames in code. |
| Tripwire | Separate anchor, terminal, and visible span. Snap both ends to their anchor positions. | The span can have taut and interrupted states if gameplay needs a visible tell. |
| PIR sensor | Empty socket and mounted lead, with orientations matching the chosen wall face. | Unlit and lit status LED; use the same frames if gameplay chooses a flash. |
| Numeric display | Empty socket and attached lead. | Distinct unavailable appearance, valid zero, and live digits. The face uses a shared digit layer. |
| Clip-on relay and other modules | Empty socket, centered lead, and connected leads facing each supported tile edge. | Add an indicator only where it communicates a distinct module state. |
| Cabinet | Closed, open, and connected port overlays after the terminal layout is decided. | Show per-port or per-module activity if the cabinet UI or world sprite needs it. |

Keep device state, cable direction, and any light animation independently composable. This avoids commissioning one sprite for every combination. Use the existing plate lead and relay attachments as placement references.
