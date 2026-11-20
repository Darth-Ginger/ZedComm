local test = dofile("tests/support/editor_harness.lua")()
local place, wire, target = test.placeTestItem, test.runTestWire, test.target
local inventory, check = test.inventory, test.check
local newItem = instanceItem

instanceItem = function(itemType)
    local item = newItem(itemType)
    function item:getKeyId() return self.keyId end
    function item:setKeyId(id) self.keyId = id end
    function item:getNumberOfKey() return self.keyCount or 2 end
    function item:setNumberOfKey(count) self.keyCount = count end
    return item
end

function inventory:haveThisKeyId(id)
    for _, item in ipairs(test.carried) do
        if item:getFullType() == "Base.KeyPadlock" and item:getKeyId() == id then return item end
    end
end

local sourceTile, inTile, tile, outTile, displayTile =
    test.floorTile(168, 125), test.floorTile(169, 125), test.floorTile(170, 125),
    test.floorTile(171, 125), test.floorTile(172, 125)
sourceTile.northWall = {}
local source = place(sourceTile, "ZedComm.NetworkSwitch")
local id = place(tile, "ZedComm.SmallCabinet")
local display = place(displayTile, "ZedComm.NumericDisplay")
local initial = test.registry.network:record(id).state
initial.circuit.links = { { from = "input", output = "out", to = "output", input = "in" } }
assert(test.registry:setDeviceState(id, initial))
local inWire = wire(inTile, source, "signal", tile, id, "input")
wire(outTile, id, "output", displayTile, display, "signal")

local function piece() return test.registry.network.pieces[id] end
local function entry() return test.placement.resolve(test.registry, id) end

local padlock = test.give("Base.Padlock")
padlock:setKeyId(42)
local advanced = test.give("ZedComm.AdvancedAdapter")
assert(test.optionsAt(tile)["Open Small Cabinet"])()
local panel = assert(test.panel)
local board = piece().board
assert(test.optionsAt(tile)["Padlock cabinet"])()
check(test.queued:isValid() and test.queued:complete(), "cabinet can be padlocked from its submenu")
local matching = inventory:haveThisKeyId(42)
check(matching and not inventory:contains(padlock) and piece().state.padlockKeyId == 42
    and piece().board == board and piece().ports.input == inWire,
    "locking exchanges the padlock for matching keys without rebuilding or rewiring")
panel:render()
check(test.panel == nil and not test.optionsAt(tile, "Cabinet (Padlocked)")["Open Small Cabinet"],
    "locking closes an open board and hides its edit menu")
check(not target(tile, id, "pickup") and not target(tile, id, "upgrade-cabinet", { item = advanced })
    and inventory:contains(advanced), "padlock blocks pickup and upgrade")
local lockedMenu = test.optionsAt(tile, "Cabinet (Padlocked)")
local wireMenu = test.optionsAt(inTile)
local disconnected, disconnectReason = target(tile, id, "disconnect-port", { port = "input", cableId = inWire })
local pickedUp, pickupReason = target(inTile, inWire, "pickup")
check(not disconnected and disconnectReason == "The cabinet is padlocked."
    and not pickedUp and pickupReason == "The wire is connected to a padlocked cabinet."
    and piece().ports.input == inWire,
    "padlock refuses direct jack disconnection and pickup of the attached wire")
local disconnectOffered = false
for label in pairs(lockedMenu) do
    if label:match("^Disconnect cabinet jack") then disconnectOffered = true end
end
check(not disconnectOffered and not wireMenu["Pick up wire"],
    "locked jack and attached wire hide their removal actions")

local spareCabinetTile, spareWireTile, outerTile =
    test.floorTile(170, 128), test.floorTile(171, 128), test.floorTile(172, 128)
local spareCabinet = place(spareCabinetTile, "ZedComm.SmallCabinet")
local looseWire = place(spareWireTile, "ZedComm.SignalWire")
local spareWire = test.give("ZedComm.SignalWire")
assert(test.registry:setCabinetPadlock(spareCabinet, 77))
local function lockedFailure(ok, reason)
    return not ok and reason == "The cabinet is padlocked."
end
check(lockedFailure(test.join(spareCabinetTile, looseWire, false, spareCabinet, "input"))
    and lockedFailure(test.join(spareWireTile, spareCabinet, "input", looseWire, false))
    and lockedFailure(test.lay(spareWireTile, spareWire, spareCabinet, "input"))
    and inventory:contains(spareWire)
    and test.registry.network.pieces[spareCabinet].ports.input == false,
    "a locked free jack cannot attach from either side or consume a new wire")
check(#test.placement.freePorts(assert(test.placement.resolve(test.registry, spareCabinet))) == 0,
    "placement choices omit locked free jacks")
assert(test.registry:setCabinetPadlock(spareCabinet, nil))
assert(test.join(spareCabinetTile, looseWire, false, spareCabinet, "input"))
local repaired, outerWire = test.lay(outerTile, spareWire, looseWire, false)
assert(repaired, outerWire)
assert(test.registry:setCabinetPadlock(spareCabinet, 77))
check(target(outerTile, outerWire, "pickup") and test.registry.network.pieces[spareCabinet].ports.input == looseWire,
    "pickup farther along the run remains available")

local layout = piece().state.circuit
check(not test.placement.editCircuit(test.player, test.registry, entry(), layout, layout)
    and not test.placement.changeCircuitBattery(test.player, test.registry, entry(), layout, "battery")
    and not test.registry:renameCabinetPort(id, "input", "Changed"),
    "padlock blocks circuit edits, battery changes and jack labels")
assert(target(sourceTile, source, "toggle-network-switch"))
test.fire("OnTick")
check(test.placedReading(display) == 255, "locked cabinet continues to process signals")

test.registry, test.java = test.start(test.save(test.java))
test.fire("OnTick")
check(piece().state.padlockKeyId == 42 and test.placedReading(display) == 255
    and piece().ports.input == inWire, "padlock, signal and wires survive reload")
local wrong = test.give("Base.KeyPadlock")
wrong:setKeyId(99)
local spare = test.give("Base.KeyPadlock")
spare:setKeyId(42)
while inventory:haveThisKeyId(42) do inventory:Remove(inventory:haveThisKeyId(42)) end
check(not target(tile, id, "remove-cabinet-padlock", { keyId = 42 }) and inventory:contains(wrong),
    "a wrong key cannot remove the padlock")
inventory:AddItem(matching)
inventory:AddItem(spare)
inventory.full = true
check(not target(tile, id, "remove-cabinet-padlock", { keyId = 42 })
    and inventory:contains(matching) and piece().state.padlockKeyId == 42,
    "failed recovery restores the key and leaves the lock in place")
inventory.full = false
local used = inventory:haveThisKeyId(42)
assert(test.optionsAt(tile)["Remove padlock"])()
check(test.queued:isValid() and test.queued:complete(), "matching key removes the lock through the menu")
local recovered = inventory:getFirstType("Base.Padlock")
check(recovered and recovered:getKeyId() == 42 and recovered:getNumberOfKey() == 1
    and not inventory:contains(used) and inventory:haveThisKeyId(42)
    and piece().state.padlockKeyId == nil and test.optionsAt(tile)["Open Small Cabinet"],
    "removal returns the keyed padlock, uses one key and restores access")
check(target(tile, id, "disconnect-port", { port = "input", cableId = inWire }) and piece().ports.input == false
    and test.join(tile, inWire, false, id, "input"), "unlocking makes the jack editable again")
assert(test.registry:setCabinetPadlock(id, 42))
inTile:transmitRemoveItemFromSquare(assert(test.placement.resolve(test.registry, inWire)).object)
check(test.registry.network.pieces[inWire] == nil and piece().ports.input == false
    and piece().state.padlockKeyId == 42, "forced world removal detaches the wire while the cabinet stays locked")
test.finish()
