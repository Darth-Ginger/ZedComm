local testState = dofile("tests/support/editor_harness.lua")()
local check = testState.check
local save = testState.save
local fire = testState.fire
local start = testState.start
local placement = testState.placement
local runtime = testState.runtime
local inventory = testState.inventory
local carried = testState.carried
local player = testState.player
local give = testState.give
local floorTile = testState.floorTile
local target = testState.target
local placedReading = testState.placedReading
local join = testState.join
local optionsAt = testState.optionsAt
local dragCarried = testState.dragCarried
local click = testState.click
local placeTestItem = testState.placeTestItem
local runTestWire = testState.runTestWire


testState.registry, testState.java = start()
local plateTile, cabinetTile, displayTile = floorTile(193, 124), floorTile(195, 124), floorTile(197, 124)
local plateId = placeTestItem(plateTile, "ZedComm.WeightPlate")
local cabinetId = placeTestItem(cabinetTile, "ZedComm.AdvancedSmallCabinet")
local displayId = placeTestItem(displayTile, "ZedComm.AdvancedDisplay")
assert(runtime.setWeightPlateSender(testState.registry, plateId, ZedComm.SignalModules.ADVANCED_SENDER))
local mass = 1150.25
plateTile.overlappingVehicle = { getMass = function() return mass end }
local inputWire = runTestWire(floorTile(194, 124), plateId, "signal", cabinetTile, cabinetId, "input")
runTestWire(floorTile(196, 124), cabinetId, "output", displayTile, displayId, "signal")
local cabinet = placement.resolve(testState.registry, cabinetId).object
local previousTime, previousUI = testState.worldTime, UIManager
UIManager = { getSpeedControls = function() return nil end }
player.tile = floorTile(194, 124)
fire("OnObjectLeftMouseButtonDown", cabinet)
check(not testState.panel, "one click on a cabinet leaves the editor closed")
testState.worldTime = testState.worldTime + 450
fire("OnObjectLeftMouseButtonDown", cabinet)
check(not testState.panel, "two separated cabinet clicks leave the editor closed")
testState.worldTime = testState.worldTime + 180
fire("OnObjectLeftMouseButtonDown", cabinet)
check(testState.panel and testState.panel.target.id == cabinetId, "double-clicking a nearby cabinet opens its editor")
testState.worldTime, UIManager = previousTime, previousUI
local cache = give("ZedComm.CacheModule")
dragCarried("cache")
testState.panel:onMouseUp(166, 184)
local cacheId = testState.panel.selected
check(not inventory:contains(cache) and cacheId ~= nil, "the carried palette can install Cache from Connections")
testState.panel.configureButton.click()
testState.panel:linkTerminal("input", "out")
testState.panel:linkTerminal(cacheId, "data")
testState.panel:linkTerminal(cacheId, "out")
testState.panel:linkTerminal("output", "in")
local function shown()
    fire("OnTick")
    fire("OnTick")
    local _, _, attached, received = placedReading(displayId)
    assert(attached)
    return received
end
check(shown().value == 115, "advanced display receives only the byte from a basic output")
local faceReading, jackDetail
local cursorBeforeX, cursorBeforeY = testState.mouseX, testState.mouseY
testState.mouseX, testState.mouseY = testState.panel.parts.input.x + 10, testState.panel.parts.input.y + 10
function testState.panel:drawTextCentre(value, x, y)
    local jack = self.parts.input
    if x == jack.x + jack.width / 2 and y == jack.y + 25 then faceReading = value end
end
function testState.panel:drawText(value)
    if value:find("IN |", 1, true) then jackDetail = value end
end
testState.panel:render()
check(faceReading == "1150 kg" and jackDetail == "IN | 1150.25 kg (byte 115)",
    "the Advanced cabinet shows weight and the jack detail includes the exact value and fallback")
testState.mouseX, testState.mouseY = cursorBeforeX, cursorBeforeY
testState.panel:onMouseDown(345, 96)
testState.panel:onMouseUp(345, 96)
testState.panel.configureButton.click()
check(shown().value.amount == 1150.25, "advanced output delivers full weight through a native placed receiver")
mass = 1150.75
local received = shown()
check(received.value.amount == 1150.75 and received.basicValue == 115,
    "a change beneath fallback resolution reaches the advanced display")
received.value.amount = 0
check(shown().value.amount == 1150.75, "the readout exposes a copy of the held packet")
local oldSay, said = player.Say
function player:Say(line) said = line end
assert(optionsAt(displayTile)["Read full signal"])()
player.Say = oldSay
check(said and said:find("1150.75 kg", 1, true), "advanced display context action shows value and unit")
testState.panel:close()
assert(testState.registry:unlink(inputWire, cabinetId))
check(shown() == nil, "advanced display clears when the data run is cut")
assert(join(cabinetTile, inputWire, false, cabinetId, "input"))
testState.registry, testState.java = start(save(testState.java))
check(shown().value.amount == 1150.75, "output mode and Cache settings restore after reload")

assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
testState.panel.selected = cacheId
testState.panel:removePart()
give("ZedComm.MultiplierModule")
give("ZedComm.BatterySourceModule")
dragCarried("multiplier")
testState.panel:onMouseUp(166, 184)
local multiplierId = testState.panel.selected
testState.panel.configureButton.click()
dragCarried("batterySource")
testState.panel:onMouseUp(226, 214)
local batteryId = testState.panel.selected
testState.panel.configureButton.click()
testState.input = "4"
testState.confirm()
give("Base.Battery"):setUsedDelta(0.8)
testState.panel.batteryButton.click()
testState.panel:linkTerminal("input", "out")
testState.panel:linkTerminal(multiplierId, "a")
testState.panel:linkTerminal(batteryId, "out")
testState.panel:linkTerminal(multiplierId, "b")
testState.panel:linkTerminal(multiplierId, "out")
testState.panel:linkTerminal("output", "in")
local full = shown()
check(full.value.amount == 4603 and full.basicValue == 255,
    "player-configured full multiplier and battery factor deliver the uncapped typed result")
testState.panel.selected = "output"
testState.panel.configureButton.click()
check(shown().value == 255, "the same math output supplies the generated capped fallback in Basic mode")
testState.panel:close()

testState.finish()
