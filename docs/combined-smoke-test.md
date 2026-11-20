# ZedComm combined Build 42 smoke test

Use the existing singleplayer test save and the updated local Workshop build. Reuse the staged door, window and cabinet rigs. Mark each check you run and record any failure or skip. Use one shared reload and one final console capture.

## 1. Door and cabinet retest

Bring a screwdriver, a vanilla padlock, loose Signal Wire and the existing rigs. Use two Test Byte Sources in debug or two Network Switches in normal play to drive the door's Lock and Open jacks independently. Leave the window from Run B fitted until after reload.

- [ ] **Door access and art.** At an existing wired door, close and unlock it with both inputs at `0`. From each face, open **ZedComm → Door → Open Door Board**, then disconnect or reconnect the Open jack from the inside using an accessible wire end on that side. Verify the maglock and each connected lead from both faces. Check that Lock and Door indicators stay legible and that the fixtures stay aligned while the door opens. Use one north-facing door and check the equivalent inside interaction once on a west-facing door. If a Door Contact is fitted, check its independent housing and lead without repeating the previously verified signal sequence.
- [ ] **Door requests.** With the door shut, set Lock and Open to `255`. Confirm it stays shut and mouse interaction cannot open it from either side. Disconnect the source at the other end of the Lock run, leaving the Lock jack wired. Expect unlock and open with Open still `255`. Set Open to `0`. Expect closure and the mouse action to respect the held Close request. **Native E is a separate release blocker.** Keep it out of this pass until there is a supported interception path.
- [ ] **Cabinet mounting.** Use native **Place** on a clear countertop while standing a few tiles away. Confirm the character walks to a reachable adjacent tile, the cabinet lands at ghost height, and native **Pickup** returns it. At the wall cabinet, confirm a connected jack has a continuous lead from the chosen wall face to the floor wire. Leave it wired for reload.
- [ ] **Cabinet padlock.** Use a working cabinet-to-display circuit, ideally the wall cabinet, with one free jack and a matching key. Choose **Padlock cabinet**. Confirm the board stays closed and the display still responds. A free jack must reject new wiring, an attached jack must reject disconnect, and native **Pickup** must omit its directly attached wire. Leave the padlock on for reload.

**Run notes**

## 2. Shared reload

- [ ] Exit fully and launch **without debug**, with crafting and building cheats off. Check the wall lead is present once and the padlocked cabinet still runs and blocks access. Put away or drop the matching keys and verify removal is refused. Retrieve one matching key, remove the padlock, and confirm the board and jack are usable again. If using the wall cabinet, pick it up and confirm the lead clears.
- [ ] Open and close the previously fitted Window Contact host. Expect `0` open and `255` closed, with the same wire and visible housing. If the window is disposable, break the glass and expect the display's **no signal** indication. Remove the sensor independently and verify the cable end is free and the contact item returns.

**Reload notes**

## 3. Normal-play crafting and lamp

Bring Electrical **5**, a screwdriver, one powered movable vanilla lamp with a bulb, Electronics Scrap, Electric Wire, one full roll of Wire, Sheet Metal and the required adapters. Use the current character with no recipe bypass or crafting cheat.

- [ ] In **Crafting → ZedComm**, craft one Window Contact, one Advanced XL Cabinet and both Signal Wire recipes. Window Contact needs Electrical **1**, a Basic Adapter, one Electronics Scrap and one Electric Wire or roll unit. Advanced XL needs Electrical **5**, an Advanced Adapter, four Sheet Metal and two Electronics Scrap. Both keep the screwdriver. Signal Wire makes **5** from one Electric Wire or roll unit, and **50** from one full roll. Record Electrical XP before, between and after the two crafts. Each award is **1 base XP**, subject to the same character multiplier.
- [ ] Craft a Pressure Plate, Basic Small Cabinet, Threshold Module, Numeric Display and Signal Wire. Using the crafted parts, connect **Plate → Cabinet IN** and **Cabinet OUT → Display**. Link **IN → Threshold → OUT** inside, with Threshold at `1`. Expect `0 → 255 → 0` as you step on and off.
- [ ] Fit one Advanced Adapter to the powered lamp. Verify fitting consumes the adapter. Use the plate from the crafting check to drive the lamp on and off. Pick up and replace the lamp with native **Moveables**, reconnect the wire and confirm it still follows the plate. Remove the adapter and verify it returns, the wire end is free, and manual control returns.
- [ ] Pause and say **go** for the final console capture. Report any discrepancies and skipped checks.

**Run notes**

## Prior runs

| Run | Recorded result |
| --- | --- |
| A | Advanced door board, destruction cleanup, secret-door sequence, reload, standalone Contact at `255/0`, and combined fitting passed. Inside-face access and fixture art failed. Native E opened against held requests. |
| B | Window Contact and both plate checks passed. The window binding and loaded Basic Plate survived the shared reload. |
| C | Large showed 8×8 with two fixed IN/OUT pairs. Advanced XL showed 10×10 with three pairs, and IN 3 drove OUT 3 through reload. Native tabletop placement and the wall lead still needed work. |
| D | Representative recipes and a crafted circuit passed with debug enabled and crafting/building cheats off. The console identified an Advanced Small Cabinet in the rig. Exact wire XP was unrecorded and lamp fitting was carried forward. |

The broader checklist lives in [the archived test notes](<%USERPROFILE%/Zomboid/zedcomm-test-logs/combined-smoke-test-full-repo-2026-11-19.md>). The complete recipe table is in [crafting recipes](recipes.md). Full-inventory checks run offline. Additional recipe and lamp variants remain outside the representative live pass.
