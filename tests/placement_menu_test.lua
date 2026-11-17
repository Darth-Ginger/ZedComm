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

local opts = optionsAt(far)
assert(opts["Place pressure plate"])()
check(testState.queued and testState.queued:isValid() and testState.queued:complete() and not inventory:contains(otherPlate),
    "normal context menu completes timed placement from an exact inventory item")
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

testState.finish()
