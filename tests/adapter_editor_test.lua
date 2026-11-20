local testState = dofile("tests/support/editor_harness.lua")()
local check = testState.check
local worldObject = testState.worldObject
local fire = testState.fire
local placement = testState.placement
local inventory = testState.inventory
local carried = testState.carried
local player = testState.player
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local lay = testState.lay
local join = testState.join
local menu = testState.menu
local optionsAt = testState.optionsAt
local clickPalette = testState.clickPalette
local dragCarried = testState.dragCarried
local grabCarried = testState.grabCarried
local click = testState.click
local key = testState.key


local lampTile, wireTile, plateTile = floorTile(155, 125), floorTile(156, 125), floorTile(157, 125)
local lamp = worldObject(lampTile, nil)
lamp.class, lamp.active = "IsoLightSwitch", false
function lamp.getCanBeModified() return true end
function lamp.getSprite() return nil end
function lamp.getAttachedAnimSprite() return nil end
function lamp.addAttachedAnimSprite() end
function lamp.canSwitchLight() return true end
function lamp.isActivated() return lamp.active end
function lamp.setActive(_, active) lamp.active = active end
local adapter, part = give("ZedComm.AdvancedAdapter"), give("ZedComm.ThresholdModule")
testState.queued = nil
assert(optionsAt(lampTile)["Fit Advanced Adapter"])()
assert(testState.queued and testState.queued:isValid() and testState.queued:complete())
local id = lamp:getModData().zedcomm.id
local function circuit() return testState.registry.network:record(id).state.circuit end
check(not inventory:contains(adapter) and #circuit().links == 0, "install consumes the carried adapter and creates its empty board")
local placed, plateId = runPlacement(plateTile, { kind = "place", item = give("ZedComm.WeightPlate") })
assert(placed)
local laid, wireId = lay(wireTile, give("ZedComm.SignalWire"), plateId, "signal")
assert(laid and join(lampTile, wireId, false, id, "signal"))
plateTile.overlappingVehicle = { getMass = function() return 1150 end }
assert(optionsAt(lampTile)["Open Advanced Adapter"])()
assert(testState.panel and testState.panel:refresh())
testState.panel:render()
clickPalette(nil, "Logic")
testState.panel:refresh()
local collapsedCount = #testState.panel.paletteEntries
clickPalette(nil, "Logic")
testState.panel:refresh()
check(#testState.panel.paletteEntries > collapsedCount, "the carried module group can collapse and expand")
grabCarried()
check(testState.panel.wantKeyEvents and testState.panel.captured and testState.panel.drag.item == part,
    "dragging a carried module captures the mouse and enables rotate input through the editor")
testState.panel:onKeyPress(testState.rotateKey)
check(testState.panel.drag.rotation == 90, "carried modules use the same rotate binding while held")
testState.panel:onRightMouseUp(133, 142)
check(not testState.panel.drag and not testState.panel.captured and inventory:contains(part), "cancelling a carried module keeps the item")

grabCarried()
testState.mouseX, testState.mouseY = 72, 142
testState.panel:render()
check(not testState.panel.drag.preview.valid and testState.panel.drag.part.column == 1 and testState.panel.drag.part.row == 1,
    "the snapped preview rejects a footprint overlapping a fixed part")
testState.mouseX, testState.mouseY = 133, 86
testState.panel:render()
check(not testState.panel.drag.preview.valid and testState.panel.drag.part.row == 0,
    "the preview rejects a footprint that extends above the grid")
testState.mouseY = 142
testState.mouseX = 133
testState.panel:render()
check(testState.panel.drag.preview.valid and testState.panel.drag.part.column == 2 and testState.panel.drag.part.row == 1
    and inventory:contains(part) and not circuit().modules["threshold-1"],
    "moving the pointer previews a valid snapped location without consuming or installing the module")
testState.panel:onMouseUp(72, 142)
check(inventory:contains(part) and not circuit().modules["threshold-1"],
    "an overlapping placement consumes no module")
grabCarried()
testState.panel:onMouseUp(133, 142)
check(not inventory:contains(part) and circuit().modules["threshold-1"].threshold == 50,
    "placing the selected module commits the inventory and board together")
fire("OnTick")
check(not lamp.active, "an installed module with no links leaves the lamp off")
click(85, 142)
click(103, 142)
click(163, 142)
click(181, 142)
fire("OnTick")
check(lamp.active and #circuit().links == 2, "terminal selection completes the circuit")
testState.panel:onRightMouseUp(94, 142)
fire("OnTick")
check(not lamp.active and #circuit().links == 1 and circuit().links[1].to == "output",
    "right-clicking the drawn link removes only that link")
click(85, 142)
click(103, 142)
testState.panel:linkTerminal("threshold-1", "out")
testState.panel:linkTerminal("output", "in")
fire("OnTick")
check(not lamp.active and #circuit().links == 1, "selecting the same connected terminals unlinks them")
testState.panel.autoButton.click()
fire("OnTick")
check(lamp.active and #circuit().links == 2, "automatic routing restores the single module path")
testState.panel:onMouseDown(122, 105)
check(not testState.panel:isKeyConsumed(19) and testState.panel:isKeyConsumed(testState.rotateKey),
    "the held module uses the game's configured rotate key")
testState.panel:onKeyPress(19)
check(testState.panel.drag.rotation == 0, "unrelated keys leave the preview orientation alone")
testState.panel:onKeyPress(testState.rotateKey)
testState.panel:onMouseUp(158, 105)
check(circuit().modules["threshold-1"].rotation == 0 and #circuit().links == 2,
    "rotation that overlaps a fixed part leaves the existing board intact")
testState.panel:onRightMouseUp(122, 105)
assert(testState.jackMenu.options.Configure)()
testState.input = "120"
testState.confirm()
fire("OnTick")
check(not lamp.active and circuit().modules["threshold-1"].threshold == 120,
    "Configure from an installed module's context menu edits its threshold on a steady byte")
assert(optionsAt(lampTile)["Set threshold"])()
testState.input = "50"
testState.panel:onMouseDown(122, 105)
testState.panel:onKeyPress(testState.rotateKey)
testState.confirm()
testState.panel:onMouseUp(155, 262)
fire("OnTick")
check(lamp.active and circuit().modules["threshold-1"].threshold == 50
    and circuit().modules["threshold-1"].rotation == 0 and not testState.panel.captured,
    "an edit from the world shortcut updates the same setting and cancels a stale drag")
testState.panel:onMouseDown(122, 105)
testState.panel:onKeyPress(testState.rotateKey)
testState.panel:onRightMouseUp(155, 262)
check(not testState.panel.drag and not testState.panel.captured and not testState.panel:isKeyConsumed(testState.rotateKey)
    and circuit().modules["threshold-1"].rotation == 0, "right-click cancels without moving the installed module")
testState.panel:onMouseUp(155, 262)
check(not testState.panel.terminal and #circuit().links == 2, "releasing after cancellation does not select a contact")
testState.panel:onMouseDown(122, 105)
testState.panel:onMouseUpOutside(-1, 105)
check(not testState.panel.drag and not testState.panel.captured and circuit().modules["threshold-1"].row == 1,
    "releasing outside the editor leaves the installed part in place")
testState.panel:onMouseDown(122, 105)
player.tile = plateTile
testState.panel:render()
testState.panel:onMouseUp(155, 262)
check(not testState.panel.drag and not testState.panel.captured and circuit().modules["threshold-1"].row == 1,
    "losing edit reach cancels a held module before it can be dropped")
player.tile = lampTile
testState.panel:onMouseDown(122, 105)
testState.panel:onKeyPress(testState.rotateKey)
testState.mouseX, testState.mouseY = 155, 262
testState.panel:render()
check(testState.panel.drag.preview.valid and circuit().modules["threshold-1"].rotation == 0,
    "the rotated bottom-row preview does not mutate the live circuit")
testState.panel:onMouseUp(155, 262)
fire("OnTick")
check(circuit().modules["threshold-1"].row == 3 and circuit().modules["threshold-1"].rotation == 90
    and #circuit().links == 2 and lamp.active and not testState.panel.captured,
    "move and rotate together preserve the wired terminal identities")
inventory.full = true
testState.panel:removePart()
inventory.full = false
check(circuit().modules["threshold-1"] ~= nil, "a full inventory preserves the installed part")
testState.panel:removePart()
fire("OnTick")
check(not circuit().modules["threshold-1"] and #circuit().links == 0 and not lamp.active
    and inventory:getFirstType("ZedComm.ThresholdModule"), "removal returns a module and releases its links")
local returnedPart = inventory:getFirstType("ZedComm.ThresholdModule")
grabCarried()
testState.panel:onKeyPress(testState.rotateKey)
testState.panel:onMouseUp(118, 275)
local installed = circuit().modules["threshold-1"]
check(installed and installed.column == 1 and installed.row == 3 and installed.rotation == 90
    and not inventory:contains(returnedPart), "a carried module can be installed directly in its rotated position")
testState.panel:removePart()
local inverterItem = give("ZedComm.NotModule")
dragCarried("not")
testState.panel:onMouseUp(133, 142)
testState.panel.autoButton.click()
fire("OnTick")
check(not inventory:contains(inverterItem) and not lamp.active and #circuit().links == 2,
    "dragging and auto-connecting NOT in the Advanced Adapter inverts a positive byte")
plateTile.overlappingVehicle = nil
fire("OnTick")
check(lamp.active, "NOT on the 3x3 board turns the lamp on for a valid zero")
assert(testState.registry:unlink(wireId, plateId))
fire("OnTick")
check(not lamp.active, "unplugging NOT's input leaves the wired lamp off")
testState.panel:removePart()
testState.panel:close()

-- Two tiles away the editor opens and reads, but every change asks the player to step closer.
local openEditor = assert(optionsAt(lampTile)["Open Advanced Adapter"])
player.tile = plateTile
openEditor()
check(testState.panel and testState.panel:refresh() and not testState.panel.reachable, "the editor opens read-only from two tiles away")
testState.panel:render()
grabCarried()
check(not testState.panel.drag and testState.panel.message == "Step next to the lamp to make changes.",
    "starting a placement from two tiles away asks the player to step closer")
testState.panel:onMouseUp(111, 82)
check(not circuit().modules["threshold-1"], "a click from two tiles away changes nothing")
testState.panel:linkTerminal("input", "out")
check(testState.panel.terminal == nil, "contact selection needs reach")
wireTile.blocked = lampTile
check(not testState.panel:refresh(), "a blocked path closes the looking range")
wireTile.blocked = nil
local farTile = floorTile(158, 125)
player.tile = farTile
check(not testState.panel:refresh(), "three tiles away is out of range")
player.tile = lampTile
check(testState.panel:refresh() and testState.panel.reachable, "stepping back next to the lamp restores editing")
testState.panel:close()

testState.finish()
