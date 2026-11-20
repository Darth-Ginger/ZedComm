local testState = dofile("tests/support/editor_harness.lua")()
local check = testState.check
local fire = testState.fire
local start = testState.start
local runtime = testState.runtime
local inventory = testState.inventory
local give = testState.give
local floorTile = testState.floorTile
local placedReading = testState.placedReading
local optionsAt = testState.optionsAt
local dragCarried = testState.dragCarried
local click = testState.click
local placeTestItem = testState.placeTestItem
local runTestWire = testState.runTestWire


testState.registry, testState.java = start()
local previousTime, previousItems = getGameTime, ItemContainer
local delta, powered = 0, false
getGameTime = function()
    return { getRealworldSecondsSinceLastUpdate = function() return delta end }
end
ItemContainer = { isObjectPowered = function(_, allowGenerator) return powered and allowGenerator end }
local function seconds(value)
    delta = value
    fire("OnTick")
    delta = 0
    fire("OnTick")
end
local sourceTile, cabinetTile, displayTile = floorTile(203, 124), floorTile(205, 124), floorTile(207, 124)
local inputId = placeTestItem(sourceTile, "ZedComm.DebugByteSource")
local cabinetId = placeTestItem(cabinetTile, "ZedComm.SmallCabinet")
local displayId = placeTestItem(displayTile, "ZedComm.NumericDisplay")
local inputWire = runTestWire(floorTile(204, 124), inputId, "signal", cabinetTile, cabinetId, "input")
runTestWire(floorTile(206, 124), cabinetId, "output", displayTile, displayId, "signal")
assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
give("ZedComm.TimerModule")
give("ZedComm.WaitModule")
dragCarried("timer")
testState.panel:onMouseUp(166, 244)
local timer = testState.panel.selected
dragCarried("wait")
testState.panel:onMouseUp(106, 124)
local wait = testState.panel.selected
testState.panel:linkTerminal("input", "out")
testState.panel:linkTerminal(wait, "in")
testState.panel:linkTerminal(wait, "out")
testState.panel:linkTerminal(timer, "in")
testState.panel:linkTerminal(timer, "out")
testState.panel:linkTerminal("output", "in")
seconds(0)
assert(runtime.setTestByte(testState.registry, inputId, 255))
seconds(0)
check(placedReading(displayId) == 0, "a native cabinet starts with Wait's OFF output")
check(runtime.getTimingRemaining(cabinetId, wait) == 2 and runtime.getTimingRemaining(cabinetId, timer) == nil,
    "only Wait has a countdown before it forwards the input")
seconds(1)
local countdown
function testState.panel:drawTextCentre(value, _, y)
    if y == self.parts[wait].y + 39 then countdown = value end
end
testState.panel:render()
check(countdown == "1.0s", "the editor draws the remaining seconds below Wait's setting")
seconds(1)
check(placedReading(displayId) == 255 and runtime.getTimingRemaining(cabinetId, wait) == nil
    and runtime.getTimingRemaining(cabinetId, timer) == 10,
    "Timer begins counting when Wait forwards, even with a quiet input wire")
assert(runtime.setTestByte(testState.registry, inputId, 0))
seconds(0)
check(placedReading(displayId) == 255, "timer holds ON after valid zero")
seconds(10)
check(placedReading(displayId) == 0 and runtime.getTimingRemaining(cabinetId, timer) == nil,
    "timer expiration publishes OFF and clears the countdown")
assert(runtime.setTestByte(testState.registry, inputId, 255))
seconds(0)
seconds(2)
assert(testState.registry:unlink(inputWire, cabinetId))
seconds(0)
check(placedReading(displayId) == nil and runtime.getTimingRemaining(cabinetId, timer) == nil,
    "disconnect clears both the signal and countdown")
testState.panel:close()

cabinetTile, displayTile = floorTile(213, 124), floorTile(215, 124)
cabinetId = placeTestItem(cabinetTile, "ZedComm.SmallCabinet")
displayId = placeTestItem(displayTile, "ZedComm.NumericDisplay")
runTestWire(floorTile(214, 124), cabinetId, "output", displayTile, displayId, "signal")
assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
give("ZedComm.MainsSourceModule")
dragCarried("mainsSource")
testState.panel:onMouseUp(106, 94)
local mains = testState.panel.selected
testState.panel.configureButton.click()
testState.input = "37"
testState.confirm()
testState.panel:linkTerminal(mains, "out")
testState.panel:linkTerminal("output", "in")
seconds(0)
check(placedReading(displayId) == nil, "a placed mains source waits for host power")
powered = true
seconds(0)
check(placedReading(displayId) == 37, "power recovery sends the tuned byte without changes to wiring")
powered = false
seconds(0)
check(placedReading(displayId) == nil, "power loss clears the source run")
testState.panel.selected = mains
testState.panel:removePart()
give("ZedComm.BatterySourceModule")
dragCarried("batterySource")
testState.panel:onMouseUp(106, 94)
local batterySource = testState.panel.selected
testState.panel:linkTerminal(batterySource, "out")
testState.panel:linkTerminal("output", "in")
testState.panel.selected = batterySource
local battery = give("Base.Battery")
battery:setUsedDelta(0.45)
inventory.full = true
testState.panel.batteryButton.click()
seconds(0)
check(not inventory:contains(battery) and placedReading(displayId) == 255,
    "installing a battery at capacity powers the source without mains")
testState.panel.batteryButton.click()
seconds(0)
check(not inventory:getFirstType("Base.Battery") and placedReading(displayId) == 255
    and testState.panel.message == "There is no room for the battery.",
    "a full inventory preserves the installed battery and its signal")
inventory.full = false
testState.panel.batteryButton.click()
seconds(0)
check(inventory:getFirstType("Base.Battery"):getCurrentUsesFloat() == 0.45
    and placedReading(displayId) == nil, "battery removal returns its charge and clears the signal")
testState.panel:close()
getGameTime, ItemContainer = previousTime, previousItems

testState.finish()
