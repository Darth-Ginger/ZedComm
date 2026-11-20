local testState = dofile("tests/support/menu_harness.lua")()
local check = testState.check
local placement = testState.placement
local inventory = testState.inventory
local give = testState.give
local floorTile = testState.floorTile
local menu = testState.menu
local optionsAt = testState.optionsAt

local otherPlate = give("ZedComm.PressurePlate")
local far = floorTile(46, 40)

local player = testState.player
function player:isTimedActionInstant() return self.instant == true end
function player:Say(message) self.lastPlacementMessage = message end

local opts = optionsAt(far)
assert(opts["Place pressure plate"])()
check(testState.queued and testState.queued.maxTime == 25 and testState.queued:isValid()
    and testState.queued:complete() and not inventory:contains(otherPlate)
    and player.lastPlacementMessage == "Device placed.",
    "normal context menu uses a short placement action and reports success")

local staleItem = give("ZedComm.PressurePlate")
local staleTile = floorTile(46, 41)
player.instant = true
assert(optionsAt(staleTile)["Place pressure plate"])()
local staleAction = testState.queued
inventory:Remove(staleItem)
check(staleAction.maxTime == 1 and not staleAction:isValid() and not staleAction:complete()
    and #staleTile.objects == 0 and player.lastPlacementMessage == "That item is no longer in your main inventory.",
    "instant placement still checks that the exact selected item is carried")
player.instant = false

local cabinetTile = floorTile(46, 42)
local placedCabinet, cabinetId = testState.runPlacement(cabinetTile,
    { kind = "place", item = give("ZedComm.SmallCabinet") })
assert(placedCabinet, cabinetId)
local adapter = give("ZedComm.AdvancedAdapter")
assert(optionsAt(cabinetTile)["Upgrade cabinet with Advanced Adapter"])()
local upgrade = testState.queued
assert(testState.target(cabinetTile, cabinetId, "pickup"))
local cabinet = inventory:getFirstType("ZedComm.SmallCabinet")
assert(testState.runPlacement(cabinetTile, { kind = "place", item = cabinet }))
check(upgrade.maxTime == 120 and not upgrade:isValid() and not upgrade:complete()
    and inventory:contains(adapter) and player.lastPlacementMessage == "That device or wire is no longer on the tile.",
    "long upgrade action rejects a replacement cabinet with the same network identity")
local spare = give("ZedComm.SignalWire")
local nextTile = floorTile(47, 40)
opts = optionsAt(far)
assert(opts["Select pressure plate free end"])()
opts = optionsAt(nextTile)
check(ISBuildingObject == nil and opts["Lay wire here"] and not getCell():getDrag(0),
    "the ZedComm menu works before the native cursor class loads")
assert(opts["Lay wire here"])()
assert(opts["Pause wire run"])()
check(not testState.queued:isValid() and not testState.queued:complete() and inventory:contains(spare)
    and #nextTile.objects == 0, "pausing the run cancels a queued wire placement")

getDebug = function() return true end
local sourceTile = floorTile(48, 40)
local placed, sourceId = testState.runPlacement(sourceTile,
    { kind = "place", item = give("ZedComm.DebugByteSource") })
assert(placed, sourceId)
local registry = testState.registry
local source = placement.resolve(registry, sourceId).object
local sourceMenu
ZedComm.DebugCircuits = { optionsAt = function() return {} end, setByte = function() end }
ISContextMenu.get = function() sourceMenu = menu(); return sourceMenu end
getMouseX, getMouseY = function() return 0 end, function() return 0 end
UIManager = { getSpeedControls = function() return nil end }
local function doubleClick()
    testState.fire("OnObjectLeftMouseButtonDown", source)
    testState.worldTime = testState.worldTime + 100
    testState.fire("OnObjectLeftMouseButtonDown", source)
end
doubleClick()
check(sourceMenu == nil, "source double click is off by default")
assert(optionsAt(sourceTile)["Enable double-click configuration"])()
assert(optionsAt(sourceTile)["Show name label"])()
assert(registry:renameFixture(sourceId, "Door Open Test"))
assert(testState.runtime.setTestByte(registry, sourceId, 170))
doubleClick()
check(sourceMenu and sourceMenu.options["Set test byte"] and sourceMenu.options["Rename Source"],
    "opted-in source opens byte and name controls")
testState.registry = testState.start(testState.save(testState.java))
local state = testState.registry.network.pieces[sourceId].state
check(state.byte == 170 and state.fixtureName == "Door Open Test" and state.showFixtureName
    and state.configureOnDoubleClick, "fixture display preferences survive byte edits and reload")
assert(optionsAt(sourceTile)["Hide name label"])()
assert(optionsAt(sourceTile)["Disable double-click configuration"])()
sourceMenu = nil
doubleClick()
check(sourceMenu == nil and not state.showFixtureName, "both fixture preferences can be toggled off")

testState.finish()
