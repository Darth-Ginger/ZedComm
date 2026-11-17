local testState = dofile("tests/support/editor_harness.lua")()
local check = testState.check
local save = testState.save
local fire = testState.fire
local start = testState.start
local runtime = testState.runtime
local inventory = testState.inventory
local player = testState.player
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local target = testState.target
local placedReading = testState.placedReading
local join = testState.join
local menu = testState.menu
local menuAt = testState.menuAt
local optionsAt = testState.optionsAt
local dragCarried = testState.dragCarried
local click = testState.click
local placeTestItem = testState.placeTestItem
local runTestWire = testState.runTestWire


testState.registry, testState.java = start()
local plateTile, cabinetTile = floorTile(220, 124), floorTile(222, 124)
local firstTile, secondTile = floorTile(224, 124), floorTile(222, 126)
local plate = placeTestItem(plateTile, "ZedComm.WeightPlate")
local cabinet = placeTestItem(cabinetTile, "ZedComm.SmallCabinet")
local first = placeTestItem(firstTile, "ZedComm.AdvancedDisplay")
local second = placeTestItem(secondTile, "ZedComm.AdvancedDisplay")
plateTile.overlappingVehicle = { getMass = function() return 1150.25 end }
assert(runtime.setWeightPlateSender(testState.registry, plate, ZedComm.SignalModules.ADVANCED_SENDER))
local function record() return testState.registry.network:record(cabinet) end
local function reading(id)
    fire("OnTick")
    fire("OnTick")
    local _, _, _, packet = placedReading(id)
    return packet and packet.value
end
check(record().state.adapter == "basic", "a new default cabinet has a Basic Adapter")
assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
local splitter = give("ZedComm.SplitterModule")
dragCarried("splitter")
testState.panel:onMouseUp(166, 184)
check(inventory:contains(splitter) and record().state.circuit.modules["splitter-1"] == nil,
    "dropping the splitter in the middle leaves it in inventory")
dragCarried("splitter")
testState.panel:onMouseUp(346, 244)
local splitterId = assert(testState.panel.selected)
local firstPort = ZedComm.InternalCircuit.splitterPort(splitterId, 1)
local secondPort = ZedComm.InternalCircuit.splitterPort(splitterId, 2)
local splitterPart = record().state.circuit.modules[splitterId]
check(not inventory:contains(splitter) and splitterPart.rotation == 180 and splitterPart.column == 6
    and record().ports[firstPort] == false and record().ports[secondPort] == false,
    "installing a default right-facing splitter exposes two independent external jacks")
testState.panel:linkTerminal("input", "out")
testState.panel:linkTerminal(splitterId, "in")
local inRun = runTestWire(floorTile(221, 124), plate, "signal", cabinetTile, cabinet, "input")
local firstRun = runTestWire(floorTile(223, 124), cabinet, firstPort, firstTile, first, "signal")
local secondRun = runTestWire(floorTile(222, 125), cabinet, secondPort, secondTile, second, "signal")
assert(testState.registry:renameRun(firstRun, "First branch"))
assert(testState.registry:renameRun(secondRun, "Second branch"))
local firstName, secondName = testState.registry:getRunName(firstRun), testState.registry:getRunName(secondRun)
local board = testState.registry.network.pieces[cabinet].board
assert(optionsAt(cabinetTile)["Rename Cabinet"])()
testState.input = "East entrance"
testState.confirm()
local namedMenu = menuAt(cabinetTile).children["Cabinet (East entrance)"]
check(namedMenu and namedMenu.options["Open Small Cabinet"]
    and testState.registry.network.pieces[cabinet].board == board and record().state.fixtureName == "East entrance"
    and testState.registry:getRunName(firstRun) == firstName, "fixture rename updates its menu and preserves its runs")
check(reading(first) == 115 and reading(second) == 115, "Basic cabinet delivers a byte to both split runs")
testState.panel.selected = "output"
testState.panel.configureButton.click()
check(not record().state.circuit.outputModes, "Basic cabinet editor leaves both outputs in byte mode")
testState.panel:close()

local upgrade = give("ZedComm.AdvancedAdapter")
local instant = player.isTimedActionInstant
player.isTimedActionInstant = function() return false end
assert(optionsAt(cabinetTile)["Upgrade cabinet with Advanced Adapter"])()
check(testState.queued.maxTime == 120 and inventory:contains(upgrade) and record().state.adapter == "basic",
    "cabinet upgrade waits for the timed action before swapping adapters")
inventory:Remove(upgrade)
check(not testState.queued:isValid() and not testState.queued:complete() and record().state.adapter == "basic",
    "moving the adapter out of inventory invalidates the queued upgrade")
inventory:AddItem(upgrade)
player.isTimedActionInstant = instant
inventory.full = true
check(not testState.queued:complete() and inventory:contains(upgrade) and record().state.adapter == "basic",
    "failed cabinet upgrade returns the Advanced Adapter")
inventory.full = false
assert(optionsAt(cabinetTile)["Upgrade cabinet with Advanced Adapter"])()
assert(testState.queued:isValid() and testState.queued:complete())
local upgraded = record()
check(not inventory:contains(upgrade) and inventory:getFirstType("ZedComm.BasicAdapter")
    and upgraded.state.adapter == "advanced" and #upgraded.state.circuit.links == 1
    and upgraded.ports.input == inRun and upgraded.ports[firstPort] == firstRun
    and upgraded.ports[secondPort] == secondRun, "upgrade returns the Basic Adapter and preserves circuit and runs")
check(testState.registry:getRunName(firstRun) == firstName and testState.registry:getRunName(secondRun) == secondName,
    "cabinet upgrade keeps both splitter run names")
assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
assert(testState.panel:refresh())
local jack = testState.panel.parts.output
testState.panel:onRightMouseUp(jack.x + 6, jack.y + 6)
check(not testState.jackMenu.options["Remove module"], "fixed output cannot be removed from the context menu")
local part = testState.panel.parts[splitterId]
testState.panel:onRightMouseUp(part.x + 6, part.y + 6)
assert(testState.jackMenu.options["Rename SPL-1"])()
testState.input = "First output"
testState.confirm()
check(testState.panel:refresh() and testState.panel.jackLabels[firstPort] == "First output" and not testState.panel.jackLabels[secondPort]
    and testState.registry:getRunName(firstRun) == firstName,
    "renaming an advanced output from the editor leaves the cable run name intact")
testState.panel.selected = splitterId
testState.panel.configureButton.click()
assert(testState.jackMenu.options["Set SPL-1 to Advanced"])()
check(reading(first).amount == 1150.25 and reading(second) == 115, "splitter branches respect their own output modes")
testState.panel:linkTerminal("input", "out")
testState.panel:onRightMouseUp(part.x + 6, part.y + 6)
assert(testState.jackMenu.options["Set SPL-2 to Advanced"])()
check(reading(second).amount == 1150.25, "both splitter runs can deliver the full reading")
give("ZedComm.CacheModule")
dragCarried("cache")
testState.panel:onMouseUp(166, 184)
local cacheId = assert(testState.panel.selected)
testState.panel.configureButton.click()
testState.panel:linkTerminal("input", "out")
testState.panel:linkTerminal(splitterId, "in")
testState.panel:linkTerminal("input", "out")
testState.panel:linkTerminal(cacheId, "data")
testState.panel:linkTerminal(cacheId, "out")
testState.panel:linkTerminal(splitterId, "in")
check(reading(first).amount == 1150.25 and reading(second).amount == 1150.25,
    "Cache forwards the full reading through both advanced splitter ports")
assert(testState.registry:unlink(secondRun, second))
check(reading(first).amount == 1150.25 and reading(second) == nil, "unplugging a branch leaves the other live")
assert(join(secondTile, secondRun, false, second, "signal"))
assert(testState.registry:unlink(inRun, cabinet))
check(reading(first) == nil and reading(second) == nil, "unplugging the one input clears both branches")
assert(join(cabinetTile, inRun, false, cabinet, "input"))
testState.panel:close()
testState.registry, testState.java = start(save(testState.java))
check(record().state.adapter == "advanced" and reading(first).amount == 1150.25
    and reading(second).amount == 1150.25 and record().state.fixtureName == "East entrance",
    "upgrade, fixture name and both splitter routes restore on reload")
assert(target(cabinetTile, cabinet, "pickup"))
local moved = floorTile(226, 124)
local item = assert(inventory:getFirstType("ZedComm.AdvancedSmallCabinet"))
assert(runPlacement(moved, { kind = "place", item = item }))
check(record().state.adapter == "advanced" and #record().state.circuit.links == 2
    and record().state.fixtureName == "East entrance",
    "replacing a picked-up cabinet preserves its adapter grade, circuit and name")

testState.finish()
