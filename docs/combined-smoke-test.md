# ZedComm combined Build 42 smoke test

Use the existing singleplayer test save and the updated local Workshop build. Reuse the staged door, window and cabinet rigs. Mark each check you run and record any failure or skip. Use one shared reload and one final console capture.

## 1. Door and cabinet retest

If this save is missing setup items, open the debug console and grant only the matching lines. Keep these parts separate from the crafted rig in step 3.

```lua
local inv = getPlayer():getInventory()
inv:AddItem("Base.Screwdriver")
inv:AddItems("Base.Padlock", 2)
inv:AddItem("Base.HandDrill")
inv:AddItems("ZedComm.DebugByteSource", 2)
inv:AddItems("ZedComm.AdvancedAdapter", 2)
inv:AddItem("ZedComm.DoorContact")
inv:AddItem("ZedComm.TabletopCabinet")
inv:AddItem("ZedComm.WallCabinet")
inv:AddItem("ZedComm.NumericDisplay")
inv:AddItems("ZedComm.SignalWire", 16)
```

Bring a screwdriver, two vanilla padlocks, loose Signal Wire and the existing rigs. Use two Test Byte Sources in debug or two Network Switches in normal play to drive the door's Lock and Open jacks independently. Leave the window from Run B fitted until after reload.

- [ ] **Door access and art.** At one closed, wired door, open the board from the inside. Use native placement to connect a free end to the door from that side, starting one tile beyond the cable. The character should approach on the same side. Check the maglock, Door Contact housing and leads from both faces through one open and close. Check the fixture names and the two status icons near the hardware. Right-click the open door where its sprite covers a reachable source and confirm the source submenu appears. With Lock OFF, send 0 to Open IN and confirm closure. Cut the cable at the Open source and confirm that manual movement returns while the Open jack stays wired.
- **Carry forward.** Ordinary wiring, the held-close mouse result and blocked native E passage in both directions were checked in game. The door runtime suite covers the held Lock mouse guard and fail-safe unlock when the connected Lock run loses its source. Recheck these only if a regression appears.
- [ ] **Wall passthrough.** Drill one opening in a solid wall and route five independent wires through it. Confirm that the menu shows 5/5, a sixth crossing is unavailable, and the wall still blocks movement. Pick up one crossing and confirm the other four remain connected. Leave the four in place for reload.
- [ ] **Cabinet mounting.** Use native **Place** on a clear countertop while standing a few tiles away. Confirm the character walks to a reachable adjacent tile, the cabinet lands at ghost height, and native **Pickup** returns it. At the wall cabinet, confirm a connected jack has a continuous lead from the chosen wall face to the floor wire. Leave it wired for reload.
- [ ] **Cabinet padlock.** Use a working cabinet-to-display circuit, ideally the wall cabinet, with one free jack and an unused padlock. Choose **Padlock cabinet**. Confirm the matching key opens the board, then put away all matching keys. Confirm the board stays closed and the display still responds. A free jack must reject new wiring, an attached jack must reject disconnect, and native **Pickup** must omit its directly attached wire. Leave the padlock on for reload. At the wired door, fit **Padlock door board (Remember me)**, put away its keys, and confirm the board opens from inside and the wired inputs still control the door.

**Run notes**

## 2. Shared reload

- [ ] Exit fully and launch **without debug**, with crafting and building cheats off. Check that the wall passthrough still shows 4/5 and its four runs are connected. Check the wall lead is present once and the padlocked cabinet still runs and blocks access. Put away or drop the matching keys and verify removal is refused. Retrieve a cabinet key, remove that padlock, and confirm the board and jack are usable again. Open the remembered door board without its keys, confirm you can edit a jack, then remove the padlock keyless. If using the wall cabinet, pick it up and confirm the lead clears.
- [ ] Open and close the previously fitted Window Contact host. Expect `0` open and `255` closed, with the same wire and visible housing. If the window is disposable, break the glass and expect the display's **no signal** indication. Remove the sensor independently and verify the cable end is free and the contact item returns.

**Reload notes**

## 3. Normal-play crafting and lamp

Bring Electrical **5**, a screwdriver, a powered movable vanilla lamp with a bulb, 16 Electronics Scrap, 11 Electric Wire, one full roll of Wire and six Sheet Metal. Craft four Basic Adapters and two Advanced Adapters if you have none staged. The listed materials cover those adapters and the recipes below. Use the current character with no recipe bypass or crafting cheat.

- [ ] In **Crafting → ZedComm**, craft both Signal Wire recipes, one Window Contact and one Advanced XL Cabinet. Window Contact needs Electrical **1**, a Basic Adapter, one Electronics Scrap and one Electric Wire or roll unit. Advanced XL needs Electrical **5**, an Advanced Adapter, four Sheet Metal and two Electronics Scrap. Both keep the screwdriver. Signal Wire makes **5** from one Electric Wire or roll unit, and **50** from one full roll. In the character's Skills panel, hover the next Electrical skill square and record the XP shown before, between and after the two wire crafts. Compare the deltas within the same skill level. Each recipe awards **1 base XP** before character and sandbox multipliers. If a craft levels the skill or the UI cannot show the delta, record the yields and mark precise live XP unverified.
- [ ] Craft a Pressure Plate, Basic Small Cabinet, Threshold Module and Numeric Display. Using those parts and the Signal Wire you crafted, connect **Plate → Cabinet IN** and **Cabinet OUT → Display**. Link **IN → Threshold → OUT** inside, with Threshold at `1`. Expect `0 → 255 → 0` as you step on and off.
- [ ] Use **ZedComm → Lamp → Fit Advanced Adapter** on the powered lamp and verify it consumes the adapter. Use **Disconnect cabinet jack (IN)** on the crafted cabinet, leaving the plate end attached. Extend that free cable end to the lamp if needed, then connect and step on and off the plate. Pick up and replace the lamp with native **Moveables**, reconnect the wire and confirm it still follows the plate. Use **Remove lamp adapter** and verify it returns, the wire end is free, and manual control returns.
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
