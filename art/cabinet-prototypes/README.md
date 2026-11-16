# Cabinet sprite prototypes

These transparent 128 × 256 PNGs use the same logical sprite cell and scaling method as the ZedComm Build 42 packer. The exports are closed-state placement trials.

| Variant | PNG | Visible art width | Nominal art placement |
| --- | --- | --- | --- |
| Wall | `network-cabinet-wall-frame.png` | 44 px | Center X 92, bottom Y 187, one provisional wall-facing anchor |
| Floor | `network-cabinet-floor-frame.png` | 66 px | Center X 64, bottom Y 239, centered ground footprint |
| Tabletop | `network-cabinet-tabletop-frame.png` | 70 px | Center X 64, bottom Y 234, base frame for a native furniture surface offset |

The tabletop source is `../first-release-concepts/network-cabinet-tabletop-v2.png`. The revised silhouette has its own bench footprint, rubber feet, and recessed front ports. The wall and floor trials use the original closed sources.

The preview shows the tabletop frame raised 30 px over a drawn table to illustrate placement. The export itself uses the unraised base anchor. Live placement needs to derive height from the actual furniture. The wall anchor, other orientations, port locations, occlusion, and pickup remain to be verified in Build 42. Cabinet interaction, tile registration, and wire leads belong to the cabinet implementation.

