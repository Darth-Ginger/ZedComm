# Cabinet sprite prototypes

The Small, Wall and Tabletop prototypes are transparent 128 × 256 PNGs. The Large and XL sources are transparent high-resolution renders. The Build 42 packer scales each source to its world frame and inventory icon.

| Variant | PNG | Visible art width | Nominal art placement |
| --- | --- | --- | --- |
| Wall | `network-cabinet-wall-frame.png` | 44 px | Center X 92, bottom Y 187, one provisional wall-facing anchor |
| Floor | `network-cabinet-floor-frame.png` | 66 px | Center X 64, bottom Y 239, centered ground footprint |
| Large | `network-cabinet-large.png` | 88 px | Wide double-door cabinet with two visible cable sockets |
| XL | `network-cabinet-xl.png` | 68 px | Tall vented rack with three visible cable sockets |
| Tabletop | `network-cabinet-tabletop-frame.png` | 70 px | Center X 64, bottom Y 234, base frame for a native furniture surface offset |

The tabletop source is `../first-release-concepts/network-cabinet-tabletop-v2.png`. The revised silhouette has its own bench footprint, rubber feet, and recessed front ports. The wall and floor trials use the original closed sources.

The preview shows the tabletop frame raised 30 px over a drawn table to illustrate placement. The export itself uses the unraised base anchor. Live placement needs to derive height from the actual furniture. The wall anchor, other orientations, port locations, occlusion, and pickup remain to be verified in Build 42. Cabinet interaction, tile registration, and wire leads belong to the cabinet implementation.



## Large and XL art prompts

Both sprites were generated with built-in ImageGen using the floor cabinet sprite as the style and camera reference.

Shared prompt. Create a single standalone isometric 2D world sprite for an early-1990s DIY industrial cabinet in an isometric survival game. Use the attached ZedComm Small Cabinet only as a style and camera reference. Match the orthographic 2:1 pixel isometric top, front facing toward lower-left and right side toward lower-right, restrained beige/grey palette, small dark plinth and edge-lit pixel-art look. Center a close-cropped complete object with ample transparent margins, alpha background. Clean visible silhouette readable at 80px wide, low-frequency detail. No background, floor plane, lettering, logos, wires, or detached objects.

Large variant. Make the Large cabinet a broad waist-high unit, dark charcoal frame, two side-by-side warm grey access doors with center seam, recessed catches and a pair of clearly visible dark cable sockets low on its right face. Body is wide and squat.

XL variant. Make the XL cabinet a tall floor-standing electrical rack with a single broad lower door in muted slate-grey, three horizontal vent bays stacked high, a raised base and a column of three recessed black cable sockets low on its right face. Distinct tall stepped silhouette, pale cool grey top cap.
