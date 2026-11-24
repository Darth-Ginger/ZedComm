# ZedComm placeholder sprite sources

Generated with the built-in imagegen tool with transparent backgrounds. The PNGs are the original source images. Run `python tools/pack-placeholder-sprites.py` from the checkout with Pillow installed to regenerate the Build 42 pack and tile definitions. Stable sprite IDs are `zedcomm_devices_01_0` (plate), `zedcomm_devices_01_1` (straight wire), and `zedcomm_devices_01_2` (display). The pack declares tile-definition ID 7637.

## Module housing

The packer draws the relay housing and lead at Build 42 tile scale. The module uses frames 14-19 for an unplugged socket, same-tile connection, and four adjacent wire directions in +X, +Y, -X, -Y order. The lamp renders the selected frame as an attached sprite. The frame follows the cable connected to the module port, including on tiles shared by multiple cables. Compact housing frames 26-31 share their pixels with mount variants 32-139. The mount is chosen from the lower edge of the lamp's texture, and the child sprite follows the furniture height. The compact lead indicates which side connects.

## pressure-plate

The packer fits the plate body inside the tile so its lead can reach the wire at the tile edge. Frames 20-25 are floor overlays for the empty socket, a same-tile connection, and adjacent connections in +X, +Y, -X, -Y order. The existing plate sprite and inventory icon remain in the pack.

The occupancy plate uses the [four-tread source](../first-release-concepts/occupancy-plate.png). Frames 419 to 424 use the same socket and lead sequence. The packer exports a separate 64 x 64 item icon.

The weight plate uses the [reinforced deck source](../first-release-concepts/weight-plate.png). Frames 425 to 430 use the same connection sequence, with the rear sockets aligned to the deck. It also has a separate 64 x 64 item icon.

Use case: stylized-concept. Asset type: a single placeholder 2D world sprite for a Project Zomboid Build 42 isometric mod set in rural Kentucky in 1993. Match classic grounded pixel-art game props with a 2:1 diamond floor grid projection, viewed from above at a three-quarter angle, neutral soft light from the upper left, crisp silhouettes and muted, slightly worn materials. Prioritize legibility at small sprite size. Center the isolated object with modest transparent margins. True transparent alpha background, no visible floor tile, no scene, no lettering or logos, no watermark, no sprite sheet or alternative views.
Primary request: a compact, low-profile square industrial pressure mat. Flat dark rubber tread inset into a thin scuffed gray metal rim, a small side-facing electrical terminal, and two small corner screws. Footprint reads as a square floor diamond, flush to the floor. Make the dark rubber and lighter rim distinct at low resolution.

## wire

Frames 184-418 define loose stubs and cable routes with lane positions at their tile edges. Both sprites on a cable link use the same boundary position. Paired turns use nested curves. A device lead keeps its centered attachment, and a nearby passing cable uses a separate lane. Earlier sprite IDs stay in the pack for saved worlds.

Use case: stylized-concept. Asset type: a single placeholder 2D world sprite for a Project Zomboid Build 42 isometric mod set in rural Kentucky in 1993. Match classic grounded pixel-art game props with a 2:1 diamond floor grid projection, viewed from above at a three-quarter angle, neutral soft light from the upper left, crisp silhouettes and muted, slightly worn materials. Prioritize legibility at small sprite size. Center the isolated object with modest transparent margins. True transparent alpha background, no visible floor tile, no scene, no lettering or logos, no watermark, no sprite sheet or alternative views.
Primary request: one straight length of salvaged floor-laid insulated signal cable, oriented along the isometric tile axis from lower left to upper right, with two plainly visible free ends. Dark muted red-brown jacket and tiny dull brass terminal tips. Keep it low to the floor and just thick enough to read at game scale. One straight uncoiled cable, no spool, no branching, no detached pieces.

## numeric-display

Use case: stylized-concept. Asset type: a single placeholder 2D world sprite for a Project Zomboid Build 42 isometric mod set in rural Kentucky in 1993. Match classic grounded pixel-art game props with a 2:1 diamond floor grid projection, viewed from above at a three-quarter angle, neutral soft light from the upper left, crisp silhouettes and muted, slightly worn materials. Prioritize legibility at small sprite size. Center the isolated object with modest transparent margins. True transparent alpha background, no visible floor tile, no scene, no lettering or logos, no watermark, no sprite sheet or alternative views.
Primary request: a compact freestanding industrial numeric readout in a scuffed dark gray metal enclosure. Low slanted front face with a wide unlit smoked-plastic three-digit seven-segment display window, a small unlit indicator and a side screw terminal. Use understated beige-gray 1993 electronics materials. The display has no lit digits or printed words so game code can overlay readings later.

The on-face build uses the [blank-face source](../first-release-concepts/numeric-display-blank-face.png). The packer projects a reusable glyph set onto three positions. Frame 431 is the casing, 432 to 464 are digits and dashes, and 465 is the indicator.
