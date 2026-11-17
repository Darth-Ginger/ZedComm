local testState = dofile("tests/support/editor_harness.lua")()
local Packet = testState.Packet
local check = testState.check
local worldObject = testState.worldObject
local save = testState.save
local fire = testState.fire
local start = testState.start
local placement = testState.placement
local runtime = testState.runtime
local simulation = testState.simulation
local inventory = testState.inventory
local carried = testState.carried
local player = testState.player
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local target = testState.target
local lay = testState.lay
local join = testState.join
local menu = testState.menu
local menuAt = testState.menuAt
local optionsAt = testState.optionsAt
local droppedItem = testState.droppedItem
local dragCarried = testState.dragCarried
local click = testState.click

local plateTile, lampTile, lamp
give("ZedComm.ThresholdModule")

-- Build the cabinet from the real placement menu, editor and simulation pass.
testState.registry, testState.java = start()
local cabinetTile = floorTile(170, 125)
plateTile, lampTile = floorTile(168, 125), floorTile(172, 125)
local armTile = floorTile(170, 123)
local inputTile, armWireTile, outputTile = floorTile(169, 125), floorTile(170, 124), floorTile(171, 125)
local cabinetItem = give("ZedComm.SmallCabinet")
local cabinetMenu = menuAt(cabinetTile)
local placementOptions = cabinetMenu.children["Place device"] or cabinetMenu
assert(placementOptions.options["Place basic small cabinet"])()
assert(testState.queued and testState.queued:isValid() and testState.queued:complete())
local cabinet = cabinetTile.objects[1]
local cabinetId = cabinet:getModData().zedcomm.id
local function cabinetPiece() return testState.registry.network.pieces[cabinetId] end
check(cabinet.sprite == "zedcomm_devices_01_466" and not inventory:contains(cabinetItem)
    and cabinetPiece().ports.input == false and cabinetPiece().ports.output == false,
    "normal placement creates a cabinet with two fixed external jacks")
local plateOK, cabinetPlate = runPlacement(plateTile, { kind = "place", item = give("ZedComm.WeightPlate") })
local armItem = give("ZedComm.NetworkSwitch")
check(not runPlacement(armTile, { kind = "place", item = armItem }) and inventory:contains(armItem),
    "the network switch needs a wall and an invalid placement keeps the item")
armTile.northWall = {}
local armOK, arm = runPlacement(armTile, { kind = "place", item = armItem })
assert(plateOK and armOK)
local function armPiece() return testState.registry.network.pieces[arm] end
local function armObject() return placement.resolve(testState.registry, arm).object end
local function flipArm(on)
    local action = on and "Turn network switch on" or "Turn network switch off"
    assert(optionsAt(armTile)[action])()
    assert(testState.queued and testState.queued:isValid() and testState.queued:complete())
end
check(armPiece().state.on == false and armObject().sprite == "zedcomm_devices_01_467",
    "a freshly mounted network switch defaults off")
lamp = worldObject(lampTile, nil)
lamp.class, lamp.active = "IsoLightSwitch", false
function lamp.getCanBeModified() return true end
function lamp.getSprite() return nil end
function lamp.getAttachedAnimSprite() return nil end
function lamp.addAttachedAnimSprite() end
function lamp.canSwitchLight() return true end
function lamp.isActivated() return lamp.active end
function lamp.setActive(_, active) lamp.active = active end
assert(optionsAt(lampTile)["Install test relay"])()
assert(testState.queued and testState.queued:isValid() and testState.queued:complete())
local lampId = lamp:getModData().zedcomm.id

local andItem, extension = give("ZedComm.AndModule"), give("ZedComm.InputExtension")
assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
assert(testState.panel and testState.panel:refresh())
testState.panel:render()
check(testState.panel.gridSize == 6 and testState.panel.parts.input.height == 120 and testState.panel.parts.output.height == 120,
    "the cabinet uses the same editor with fixed two-cell parts on a 6 by 6 grid")
dragCarried("threshold")
testState.panel:onMouseUp(106, 124)
dragCarried("and")
testState.panel:onMouseUp(226, 244)
dragCarried("inputExtension")
testState.panel:onKeyPress(testState.rotateKey)
testState.panel:onMouseUp(207, 104)
check(not inventory:contains(andItem) and not inventory:contains(extension)
    and cabinetPiece().state.circuit.modules["inputExtension-3"].rotation == 90,
    "dragging from the cabinet inventory installs AND and a rotated extension")
testState.panel:linkTerminal("input", "out")
testState.panel:linkTerminal("threshold-1", "in")
testState.panel:linkTerminal("threshold-1", "out")
testState.panel:linkTerminal("and-2", "a")
testState.panel:linkTerminal("inputExtension-3", "out")
testState.panel:linkTerminal("and-2", "b")
testState.panel:linkTerminal("and-2", "out")
testState.panel:linkTerminal("output", "in")
check(#cabinetPiece().state.circuit.links == 4, "editor wires each named AND contact")

local laidInput, inputWire = lay(inputTile, give("ZedComm.SignalWire"), cabinetPlate, "signal")
local laidArm, armWire = lay(armWireTile, give("ZedComm.SignalWire"), arm, "signal")
local laidOutput, outputWire = lay(outputTile, give("ZedComm.SignalWire"), lampId, "signal")
assert(laidInput and laidArm and laidOutput)
assert(join(cabinetTile, inputWire, false, cabinetId, "input"))
assert(join(cabinetTile, armWire, false, cabinetId, "inputExtension-3"))
assert(join(cabinetTile, outputWire, false, cabinetId, "output"))
local function tick()
    fire("OnTick")
    fire("OnTick")
end
local function output()
    return runtime.inspect(cabinetId, "output").sourceByte
end
tick()
local net = testState.registry.network
local root = menuAt(cabinetTile)
local cabinetMenu = assert(root.children.Cabinet)
local labelMenu = assert(cabinetMenu.children["Label cabinet jack"])
check(cabinetMenu.options["Open Small Cabinet"] and not root.options["Open Small Cabinet"]
    and not root.children["Label cabinet jack"], "the editor and jack labels are grouped under the cabinet")
local boardBefore = cabinetPiece().board
assert(labelMenu.options.IN)()
testState.input = "Load"
testState.confirm()
check(cabinetPiece().state.portLabels.input == "Load" and cabinetPiece().board == boardBefore
    and cabinetPiece().ports.input == inputWire and optionsAt(cabinetTile)["Disconnect cabinet jack (IN (Load))"],
    "labeling a wired jack preserves its board, port identity and cable")
player.isDead, player.isAiming, player.isIgnoreContextKey = function() return false end, function() return false end,
    function() return false end
player.isClimbingLadder, player.isClimbingDownLadder = player.isDead, player.isDead
local previousUI = UIManager
UIManager = { getSpeedControls = function() return nil end }
player.tile = armTile
fire("OnObjectLeftMouseButtonDown", armObject())
assert(testState.queued and testState.queued:isValid() and testState.queued:complete())
tick()
check(armPiece().state.on and runtime.inspect(arm).sourceByte == 255
    and armObject().sprite == "zedcomm_switch_01_7", "a direct click toggles the mounted, wired switch")
UIManager = previousUI
flipArm(false)
tick()
check(net:networkOf(inputWire) ~= net:networkOf(armWire) and net:networkOf(armWire) ~= net:networkOf(outputWire)
    and net:networkOf(inputWire) ~= net:networkOf(outputWire), "the three cabinet runs stay independent")
local load = 80
plateTile.overlappingVehicle = { getMass = function() return load end }
flipArm(true)
tick()
check(output() == 0 and not lamp.active and runtime.inspect(arm).sourceByte == 255
    and armObject().sprite == "zedcomm_switch_01_7",
    "the arm latches at 255 and shows the on sprite while a low load leaves the receiver off")
load = 1150
flipArm(false)
fire("OnTick")
check(output() == 0 and runtime.inspect(arm).sourceByte == 0
    and armObject().sprite == "zedcomm_switch_01_2" and not ZedComm.Simulation.hasPending(),
    "coalesced input changes do not publish a transient ON or requeue an equal output")
local packets = ZedComm.SignalModules.Packet
runtime.prepare(testState.registry)
runtime.deliver(net:networkOf(inputWire), packets.basic(8))
runtime.deliver(net:networkOf(armWire), packets.basic(255))
runtime.finish()
runtime.prepare(testState.registry)
runtime.deliver(net:networkOf(armWire), packets.basic(0))
runtime.deliver(net:networkOf(inputWire), packets.basic(115))
runtime.finish()
check(output() == 0 and not ZedComm.Simulation.hasPending(),
    "explicitly reversed delivery order produces the same output without extra work")
flipArm(true)
fire("OnTick")
check(output() == 255 and not lamp.active, "the cabinet publishes after the input pass")
fire("OnTick")
check(lamp.active, "the changed output reaches the lamp in the next pass")
assert(runtime.setWeightPlateSender(testState.registry, cabinetPlate, ZedComm.SignalModules.ADVANCED_SENDER))
load = 0
tick()
check(output() == 0 and not lamp.active, "a valid advanced fallback of zero is delivered as OFF")
load = 1150
tick()
assert(lamp.active)
runtime.prepare(testState.registry)
runtime.deliver(net:networkOf(inputWire), packets.weight(1150))
runtime.finish()
check(output() == nil, "an advanced packet without a byte fallback clears a required cabinet input")
ZedComm.Simulation.markDirty(net:networkOf(inputWire))
tick()
assert(lamp.active)
local options = optionsAt(cabinetTile)
assert(options["Disconnect cabinet jack (IN 3)"])()
assert(testState.queued and testState.queued:isValid() and testState.queued:complete())
tick()
check(output() == nil and not lamp.active, "unplugging the arm clears the wired lamp")
assert(join(cabinetTile, armWire, false, cabinetId, "inputExtension-3"))
tick()
check(output() == 255 and lamp.active, "reconnecting adopts the held arm byte")
testState.panel:linkTerminal("inputExtension-3", "out")
testState.panel:linkTerminal("and-2", "b")
tick()
check(output() == nil and not lamp.active, "cutting an internal arm link clears the cabinet output")
testState.panel:linkTerminal("inputExtension-3", "out")
testState.panel:linkTerminal("and-2", "b")
tick()
check(output() == 255 and lamp.active, "restoring an internal arm link uses the existing wire reading")

local jack = testState.panel.parts["inputExtension-3"]
testState.panel:onRightMouseUp(jack.x + 6, jack.y + 6)
assert(testState.jackMenu.options["Rename jack"])()
testState.input = "Arm"
testState.confirm()
check(testState.panel:refresh() and testState.panel.jackLabels["inputExtension-3"] == "Arm"
    and cabinetPiece().ports["inputExtension-3"] == armWire,
    "renaming a wired input from the editor updates its label and preserves the cable")
testState.panel:onMouseDown(160, 89) -- top-edge extension body
testState.panel:onKeyPress(testState.rotateKey)
testState.panel:onMouseUp(365, 289)
check(cabinetPiece().ports["inputExtension-3"] == armWire
    and cabinetPiece().state.circuit.modules["inputExtension-3"].rotation == 180
    and cabinetPiece().state.portLabels["inputExtension-3"] == "Arm",
    "moving a wired extension to another edge preserves its jack identity")
jack = testState.panel.parts["inputExtension-3"]
testState.panel:onRightMouseUp(jack.x + 6, jack.y + 6)
assert(testState.jackMenu.options["Remove module"])()
tick()
check(output() == nil and not lamp.active and not net:record(armWire).links[cabinetId]
    and not cabinetPiece().state.portLabels["inputExtension-3"]
    and inventory:getFirstType("ZedComm.InputExtension"),
    "right-click removal returns the extension, clears its label and leaves its run loose")
dragCarried("inputExtension")
testState.panel:onKeyPress(testState.rotateKey)
testState.panel:onMouseUp(207, 104)
check(cabinetPiece().ports["inputExtension-4"] == false and cabinetPiece().ports["inputExtension-3"] == nil,
    "reinstalled extension has a fresh, disconnected jack ID")
testState.panel:linkTerminal("inputExtension-4", "out")
testState.panel:linkTerminal("and-2", "b")
assert(join(cabinetTile, armWire, false, cabinetId, "inputExtension-4"))
assert(testState.registry:renameRun(inputWire, "Load"))
tick()
assert(lamp.active)
testState.panel:close()
load = 80
testState.registry, testState.java = start(save(testState.java))
tick()
local _, runName = testState.registry:getRunName(inputWire)
check(runName == "Load" and armPiece().state.on and runtime.inspect(arm).sourceByte == 255
    and cabinetPiece().ports["inputExtension-4"] == armWire
    and cabinetPiece().state.portLabels.input == "Load"
    and #cabinetPiece().state.circuit.links == 4 and output() == 0 and not lamp.active,
    "reload restores layout, jack identities and names and uses the new load")
load = 1150
tick()
check(output() == 255 and lamp.active, "reloaded circuit responds to the next load")

local downstreamTile, downstreamWireTile = floorTile(171, 126), floorTile(172, 126)
local downstreamOK, downstreamId = runPlacement(downstreamTile,
    { kind = "place", item = give("ZedComm.SmallCabinet") })
assert(downstreamOK)
local downstream = placement.resolve(testState.registry, downstreamId)
local downstreamLayout = { modules = {}, links = {
    { from = "input", output = "out", to = "output", input = "in" },
} }
assert(placement.editCircuit(player, testState.registry, downstream, downstream.piece.state.circuit, downstreamLayout))
assert(testState.registry:unlink(outputWire, lampId))
assert(join(downstreamTile, outputWire, false, downstreamId, "input"))
local wiredDownstream, downstreamWire = lay(downstreamWireTile, give("ZedComm.SignalWire"), downstreamId, "output")
assert(wiredDownstream and join(lampTile, downstreamWire, false, lampId, "signal"))
tick()
assert(lamp.active)
load = 80
fire("OnTick")
check(output() == 0 and runtime.inspect(downstreamId, "output").sourceByte == 255 and lamp.active,
    "a chained cabinet sees the upstream change on the following pass")
fire("OnTick")
check(runtime.inspect(downstreamId, "output").sourceByte == 0 and lamp.active,
    "the chained cabinet schedules its own downstream run")
fire("OnTick")
check(not lamp.active and not ZedComm.Simulation.hasPending(), "the two-cabinet chain settles and drains its work")

local function combinedLoad()
    local secondTile, secondWireTile = floorTile(170, 127), floorTile(170, 126)
    local placedSecond, second = runPlacement(secondTile, { kind = "place", item = give("ZedComm.WeightPlate") })
    assert(placedSecond)
    local extensionItem, adderItem = give("ZedComm.InputExtension"), give("ZedComm.AdderModule")
    assert(optionsAt(cabinetTile)["Open Small Cabinet"])()
    dragCarried("inputExtension")
    for _ = 1, 3 do testState.panel:onKeyPress(testState.rotateKey) end
    testState.panel:onMouseUp(146, 406)
    local secondJack = testState.panel.selected
    dragCarried("adder")
    testState.panel:onMouseUp(106, 244)
    local adderId = testState.panel.selected
    check(not inventory:contains(extensionItem) and not inventory:contains(adderItem)
        and cabinetPiece().state.circuit.modules[adderId].kind == "adder", "the editor installs the Adder and its second jack")
    testState.panel:linkTerminal("input", "out")
    testState.panel:linkTerminal("threshold-1", "in")
    testState.panel:linkTerminal("input", "out")
    testState.panel:linkTerminal(adderId, "a")
    testState.panel:linkTerminal(secondJack, "out")
    testState.panel:linkTerminal(adderId, "b")
    testState.panel:linkTerminal(adderId, "out")
    testState.panel:linkTerminal("threshold-1", "in")
    assert(optionsAt(cabinetTile)["Set threshold"])()
    testState.input = "100"
    testState.confirm()
    local laidSecond, secondWire = lay(secondWireTile, give("ZedComm.SignalWire"), second, "signal")
    assert(laidSecond and join(cabinetTile, secondWire, false, cabinetId, secondJack))
    local function settle()
        tick()
        fire("OnTick")
    end
    plateTile.overlappingVehicle = nil
    plateTile.looseItems = { droppedItem(600) }
    settle()
    check(output() == 0 and not lamp.active, "60 alone stays below the threshold of 100")
    plateTile.looseItems = {}
    secondTile.looseItems = { droppedItem(550) }
    settle()
    check(output() == 0 and not lamp.active, "55 alone stays below the threshold of 100")
    plateTile.looseItems = { droppedItem(600) }
    settle()
    check(output() == 255 and lamp.active, "60 plus 55 trips the armed threshold")
    flipArm(false)
    settle()
    check(output() == 0 and not lamp.active, "the arm switch still cuts the combined load")
    flipArm(true)
    assert(testState.registry:unlink(secondWire, cabinetId))
    settle()
    check(output() == nil and not lamp.active, "disconnecting one plate clears the sum")
    assert(join(cabinetTile, secondWire, false, cabinetId, secondJack))
    settle()
    check(output() == 255 and lamp.active, "reconnecting restores both held plate readings")
    testState.panel:close()
end
combinedLoad()

local westTile = floorTile(171, 123)
westTile.westWall = {}
check(not target(armTile, arm, "set-network-switch", { on = 1 }) and armPiece().state.on,
    "the switch command rejects a non-boolean state")
assert(target(armTile, arm, "pickup"))
local savedSwitch = inventory:getFirstType("ZedComm.NetworkSwitch")
check(savedSwitch and savedSwitch:getModData().zedcommPlacement.state.on
    and not testState.registry.network:record(armWire).links[arm],
    "picking up an active switch keeps its latch and leaves the run end loose")
check(placement.previewSprite(westTile, savedSwitch) == "zedcomm_devices_01_470",
    "the placement preview uses the destination wall and the saved latch state")
local replaced, sameId = runPlacement(westTile, { kind = "place", item = savedSwitch })
check(replaced and sameId == arm and armObject().sprite == "zedcomm_devices_01_470"
    and armPiece().state.on and armPiece().ports.signal == false,
    "remounting keeps the switch state and uses the west-facing sprite")

local southTile, eastTile = floorTile(175, 124), floorTile(177, 124)
floorTile(175, 125).northWall = {}
floorTile(178, 124).westWall = {}
assert(target(westTile, arm, "pickup"))
savedSwitch = inventory:getFirstType("ZedComm.NetworkSwitch")
check(placement.previewSprite(southTile, savedSwitch) == "zedcomm_devices_01_472",
    "south mounting recognizes the north wall owned by the neighboring tile")
replaced, sameId = runPlacement(southTile, { kind = "place", item = savedSwitch })
check(replaced and sameId == arm and armPiece().state.mount == "south"
    and armObject().sprite == "zedcomm_devices_01_472", "south-facing placement preserves the on state")
armTile = southTile
flipArm(false)
tick()
check(armObject().sprite == "zedcomm_devices_01_471" and runtime.inspect(arm).sourceByte == 0,
    "toggling keeps the south face and publishes zero")
assert(target(southTile, arm, "pickup"))
savedSwitch = inventory:getFirstType("ZedComm.NetworkSwitch")
check(placement.previewSprite(eastTile, savedSwitch) == "zedcomm_devices_01_473",
    "east mounting recognizes the west wall owned by the neighboring tile")
replaced, sameId = runPlacement(eastTile, { kind = "place", item = savedSwitch })
check(replaced and sameId == arm and armPiece().state.mount == "east"
    and armObject().sprite == "zedcomm_devices_01_473", "east-facing placement preserves the off state")
armTile = eastTile
flipArm(true)
tick()
check(armObject().sprite == "zedcomm_devices_01_474" and runtime.inspect(arm).sourceByte == 255,
    "toggling keeps the east face and publishes 255")
southTile.northWall, southTile.westWall = {}, {}
check(ZedComm.NetworkSwitch.mount(southTile) == "north", "multiple walls keep north-first preference")
check(ZedComm.NetworkSwitch.nextMount(southTile, "north") == "west"
    and ZedComm.NetworkSwitch.nextMount(southTile, "west") == "south"
    and ZedComm.NetworkSwitch.nextMount(southTile, "south") == "north",
    "corner rotation cycles eligible walls and skips the open edge")
assert(target(eastTile, arm, "pickup"))
savedSwitch = assert(inventory:getFirstType("ZedComm.NetworkSwitch"))
check(not runPlacement(southTile, { kind = "place", item = savedSwitch, mount = "east" })
    and inventory:contains(savedSwitch), "an ineligible chosen wall cannot consume the switch")
local corner = menuAt(southTile)
local placeMenu = corner.children["Place device"] or corner
assert(placeMenu.children["Place network switch"].options["Mount on west wall"])()
assert(testState.queued:isValid() and testState.queued:complete())
check(armPiece().state.mount == "west" and armObject().sprite == "zedcomm_devices_01_470",
    "the corner context menu can mount the carried switch on its non-default wall")

local logicTile = floorTile(185, 125)
local logicPlaced, logicId = runPlacement(logicTile, { kind = "place", item = give("ZedComm.SmallCabinet") })
assert(logicPlaced and optionsAt(logicTile)["Open Small Cabinet"])()
for ix, kind in ipairs({ "or", "xor", "not" }) do
    local itemType = ZedComm.InternalCircuit.kinds[kind].item
    local item = inventory:getFirstType(itemType) or give(itemType)
    dragCarried(kind)
    testState.panel:onMouseUp(106 + (ix - 1) * 60, 244)
    local logic = testState.registry.network.pieces[logicId].state.circuit
    check(not inventory:contains(item) and logic.modules[testState.panel.selected].kind == kind,
        "cabinet editor installs the " .. kind .. " module from the carried pane")
end
testState.panel:render()
testState.panel:close()

testState.finish()
