# ZedComm combined Build 42 smoke test

Continue the current singleplayer save. Run A has enough evidence to move on. Check a box when you finish its steps and record any failure or skip under that run. **One reload remains.** Use the restart out of debug to verify B and C before starting D.

## A - Door receiver and Contact

- [x] Tested the Advanced door board and reload, disposable door destruction, the secret-door circuit and reload, standalone Contact at `255` closed / `0` open, and standalone and combined fitting. Darth-Ginger accepted the derivative cases without another pass.
- **Open findings** Inside-face fitting, wiring and board access fail on the closed map door. Native E opens a held-closed door from both sides and a held-locked door from inside. Door and Contact fixture visuals were missing. Fixture labels, cabinet double-click, and internal wire readability are follow-ups.
- **Coverage limits** Manual locking was unavailable. Delayed close was not confirmed. Full-inventory stress and dedicated combined-fit reload were deferred.

## B - One window and two plates

- [ ] **B1.** With a screwdriver, fit one Window Contact and wire it to a Numeric Display. Expect `255` closed and `0` open. Check housing and lead visibility once. Leave it wired.
- [ ] **B2.** Wire a Basic Pressure Plate to a second display and set it to `155`. Put a crate on it, step clear, and expect `155`. Move the crate away for `0`, then put it back for reload.
- [ ] **B3.** Wire a Basic Sender Weight Plate to a display. While standing clear, expect `1` for an empty standard crate, `0` when moved off, and `2` for a floor-standing shelf with pickup weight 20. You can reuse the Weight Plate hardware from Run A.

If needed, grant only the missing parts.

```lua
getPlayer():getInventory():AddItem("ZedComm.WindowContact")
getPlayer():getInventory():AddItem("ZedComm.PressurePlate")
getPlayer():getInventory():AddItem("ZedComm.WeightPlate")
getPlayer():getInventory():AddItems("ZedComm.NumericDisplay", 3)
getPlayer():getInventory():AddItems("ZedComm.SignalWire", 12)
```

**Comments and recommendations**

**General notes**

## C - Cabinet variants and shared restart

- [ ] **C1.** Open one Large and one Advanced XL. Confirm **8×8 and two fixed IN/OUT pairs** for Large and **10×10 and three pairs** for XL. Link **IN 3 → OUT 3** in the XL. Wire a Test Byte Source to IN 3 and a display to OUT 3. Expect `0 → 255 → 0`. Leave it wired.
- [ ] **C2.** Place one Tabletop on a table or counter and one Wall Cabinet on an eligible wall. Check that each ends up on its intended surface or face.
- [ ] **C3.** In debug, stage Electrical **5**, one powered movable lamp with a bulb, a screwdriver, Electronics Scrap, Electric Wire, a full roll of Wire, and Sheet Metal. Keep granted ZedComm parts separate from crafted parts. Pause and say **go** for the console capture.
- [ ] **C4.** After capture, exit PZ fully and restart **without debug**. Load the same save with cheats off. Confirm that the window still switches `255/0`, the crate still holds the plate at `155`, and XL IN 3 still drives OUT 3. Then continue to D.

```lua
local inv = getPlayer():getInventory()
for _, name in ipairs({"LargeCabinet", "AdvancedXLCabinet", "TabletopCabinet", "WallCabinet"}) do inv:AddItem("ZedComm." .. name) end
```

**Comments and recommendations**

**General notes**

## D - Normal-play crafting and lamp

- [ ] **D1.** In Crafting → ZedComm, make one contact, both wire batch sizes (**5** and **50**), and one Advanced XL Cabinet. Check the wire recipes each award **1 base Electrical XP**, accounting for the character’s XP multiplier. Advanced XL requires Electrical **5**, an Advanced Adapter, four Sheet Metal, two Electronics Scrap, and a screwdriver.
- [ ] **D2.** Craft a Pressure Plate, Basic Small Cabinet, Threshold Module, Numeric Display, and Signal Wire. Use only crafted parts in this rig. Connect **Plate → Cabinet IN** and **Cabinet OUT → Display**. Inside the board, link **IN → Threshold → OUT** and set Threshold to `1`. Step on and off the plate and expect `0 → 255 → 0`.

### Non-debug lamp retrofit

- [ ] **D3.** Fit one Advanced Adapter to a powered movable vanilla lamp. Check that the adapter is consumed and the wired lamp follows a plate or switch. Pick up and replace the lamp with native Moveables, reconnect it, and verify the adapter still works. Remove it and confirm the adapter returns, the wire end is free, and manual control returns.
- [ ] **D4.** Pause and say **go** for the final console capture. Report recipe or fitting discrepancies and skipped cases.

**Comments and recommendations**

**General notes**

## Verification

This is a representative play test. Additional orientations, recipe variants, lamp types, and full-inventory stress tests are deferred. The relevant cards retain their original acceptance criteria.

The prior full checklist and evidence were archived at `%USERPROFILE%/Zomboid/zedcomm-test-logs/combined-smoke-test-full-repo-2026-11-19.md`.
