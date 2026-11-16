# On-face numeric display

## Player behavior

The current Numeric Display shows the live byte on the casing. Values from **0 to 255** are right-aligned, with no leading zeros. The small yellow indicator is lit for nonzero input. An attached display with no live source shows red **---**, while an unattached display has a blank face. **Read numeric display** remains available for an exact diagnostic reading.

Placed displays and debug-rig displays use the same casing. A saved display with the old casing picks up the current sprite as its square loads.

## Integration and artwork

1. The Byte Readout receiver provides the live value. The client selects a precomposed floor sprite containing the casing, digits, and indicator, so they share position, height, and occlusion.
2. The renderer keeps the same sprite while the reading is steady. Saved displays migrate on load and clear the previous glyph and indicator attachments. Any unrelated attachments stay on the object.
3. The registry saves the device and circuit as before. The face follows the current reading after the receiver rebinds. A picked-up display starts with a blank face until reconnected.

The packer uses `art/first-release-concepts/numeric-display-blank-face.png` and the `DISPLAY_*` art constants in `tools/pack-placeholder-sprites.py`. The casing is 70 px wide in a 128 × 256 logical tile cell. The face origin, right edge, bottom edge, and indicator center are coordinates in the resized casing. To replace the placeholder, supply a blank casing, adjust the face and indicator anchors, and regenerate the pack. The packer reuses one projected glyph set per slot for every value.

The blank casing remains `zedcomm_devices_01_431`. Legacy attachment frames 432 to 465 remain in the pack for older saves. The separate `zedcomm_display_01` floor tileset contains signal loss at frame 0 and byte values 0 to 255 at frames 1 to 256.

## Combined Build 42 smoke test

Restart PZ with the linked mod enabled and use the same disposable singleplayer save. Leave the game running at the two capture points.

### 1. Display and debug-byte sweep

1. Inspect a saved numeric display and confirm the digits are now on its casing. Use **ZedComm → Debug → Place wired byte test rig** in debug mode on the first of three clear tiles along increasing X. Check the console for the source, wire, and display coordinates.
2. On the source tile (the first tile), choose **ZedComm → Debug → Set test byte**. Send **0, 1, 85, 170, and 255**. Check the face and compare it with **Read test display** or **Inspect circuit**. Verify the small yellow circle stays dark at 0 and lights for nonzero values.
3. Leave the source at 170 and use **Toggle test source link** in the Debug submenu to cut its wire link. Expect red **---** while the display is still attached. Reconnect and expect **170** to return with the source value held. On the third tile, use **Toggle test display link** and expect a blank face. Reconnect it.
4. Zoom in and out, move the camera, and walk over the device. The digits and indicator should stay aligned with the casing and share its occlusion. Record any placement or zoom where they drift or become unreadable.

### 2. Occupancy and weight plates

1. Use the [occupancy plate checklist](occupancy-plate.md). Watch the face as the count changes **0 → 1 → 2 → 1 → 0**, then pick up, replace, and reconnect the plate.
2. Use the [weight plate road checklist](weight-plate.md). Record a lone pedestrian reading and a parked vehicle reading. Check a close pass with no overlap, overlap with the car center off the plate, and a return to 0 when the car leaves.
3. Leave the two plate circuits connected and the debug rig at 170. Pause for a pre-reload console capture.

### 3. Reload and recover

1. Save and reload. Check that the debug rig restores **170** and both plates drive their displays without rewiring.
2. Repeat the exact **0, 85, 170, and 255** debug sweep, including signal loss and held-value reconnect. Compare the face with the circuit inspector.
3. Pick up a numeric display while its wire stays in place, replace it, and check that the face is blank until reconnect. Reconnect with a held nonzero source and confirm the face updates without ghost digits.
4. Leave the game running for the post-reload console capture. Record the PZ patch, observed plate readings, and any alignment or occlusion issues.

## Offline checkpoint

511 Lua 5.1 checks passed, including the debug menu callbacks and floor-sprite selection across signal changes, reload, and pickup. The pack contains 258 distinct display states including the original blank casing. The installed PZ texture reader opened all 723 frames. The Windows build passed.

## Build 42.22.2 live results

- Phase 1 passed the display and occlusion checks. The debug rig recorded 0, 1, 85, 170, and 255, then no signal and restoration of 170. Console capture: phase-1-display-20261112-093251.txt.
- Phase 2 recorded occupancy of 1 for the player and 2 with a dragged zombie. The weight plate read 8 for the player, 16 with a dragged zombie, 115 for the sheriff car with or without a driver, 123 for the car plus the player on foot, and 0 when clear. Console capture: phase-2-plates-pre-reload-20261112-094747.txt.
- Phase 3 was accepted based on Darth-Ginger's prior independent verification of save/reload, the debug sweep and signal recovery, and display pickup, replacement, and reconnect.
- The follow-up live-zombie occupancy test passed. Crates and bookshelves left all readings unchanged on the tested build. Console capture: live-zombie-and-furniture-20261112-100529.txt. The concealed basic plate has its own follow-up check in the [player placement guide](player-placement.md).
