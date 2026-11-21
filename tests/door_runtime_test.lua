local test = dofile("tests/support/placement_harness.lua")()
local makeDoor = dofile("tests/support/door_fixture.lua")(test.worldObject)
test.player.getPerkLevel = function() return test.player.electrical or 3 end
local check, fire = test.check, test.fire
local Circuit, Runtime = ZedComm.InternalCircuit, ZedComm.DeviceRuntime
local tile = test.floorTile(100, 100)
local door = makeDoor(tile)
door:getModData().unrelated = "preserve"
local function count(itemType)
    local amount = 0
    for _, item in ipairs(test.carried) do if item:getFullType() == itemType then amount = amount + 1 end end
    return amount
end
test.give("ZedComm.BasicAdapter")
test.player.electrical = 0
check(not ZedComm.DoorInstallation.materials(test.player, "basic"), "installation enforces Electrical skill")
test.player.electrical = 3
check(not test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic" }), "one adapter cannot retrofit a door")
test.give("ZedComm.AdvancedAdapter")
test.give("Base.Screwdriver")
check(not test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic" }), "mixed adapters cannot form a matched pair")
test.give("ZedComm.BasicAdapter")
local ok, id = test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic" })
assert(ok, id)
local registry = test.registry
check(count("ZedComm.BasicAdapter") == 0 and count("ZedComm.AdvancedAdapter") == 1
    and door:getModData().unrelated == "preserve", "installation consumes two matching adapters and preserves other data")
check(test.placement.resolve(registry, id).spec.fixtureType == "Door", "native door resolves as a Door fixture")
local function sourceAt(x, y)
    local square = test.floorTile(x, y)
    local placed, source = test.runPlacement(square, { kind = "place", item = test.give("ZedComm.DebugByteSource") })
    assert(placed, source)
    return source
end
local lockSource, openSource = sourceAt(99, 100), sourceAt(100, 99)
local laid, lockWire = test.lay(tile, test.give("ZedComm.SignalWire"), lockSource, "signal")
assert(laid); assert(test.join(tile, lockWire, false, id, "lock"))
local laidOpen, openWire = test.lay(tile, test.give("ZedComm.SignalWire"), openSource, "signal")
assert(laidOpen); assert(test.join(tile, openWire, false, id, "open"))
local function signals(lock, open)
    assert(Runtime.setTestByte(registry, lockSource, lock))
    assert(Runtime.setTestByte(registry, openSource, open))
    fire("OnTick")
end
local nativeCalls = 0
package.loaded["TimedActions/ISOpenCloseDoor"] = true
ISOpenCloseDoor = {
    isValid = function() return true end,
    complete = function() nativeCalls = nativeCalls + 1; return true end,
}
dofile(test.LUA .. "client/ZedComm/DoorInteraction.lua")
local interaction = { item = door }
signals(0, 0)
check(not ISOpenCloseDoor.isValid(interaction) and not ISOpenCloseDoor.complete(interaction)
    and nativeCalls == 0, "held Open OFF blocks the vanilla action before its animation")
signals(0, 255)
check(door.open and not door.locked, "separate input runs drive native opener")
assert(registry:unlink(openWire, openSource))
fire("OnTick")
check(door.open and registry.network.pieces[id].ports.open == openWire,
    "losing Open input leaves an open door in place with its jack wired")
assert(registry:link(openWire, openSource))
signals(0, 0)
check(not door.open and not ISOpenCloseDoor.isValid(interaction), "valid zero closes and holds the door")
assert(registry:unlink(openWire, openSource))
fire("OnTick")
check(not door.open and ISOpenCloseDoor.isValid(interaction) and registry.network.pieces[id].ports.open == openWire,
    "losing a held Close releases manual control without moving the closed door")
assert(registry:link(openWire, openSource))
signals(0, 255)
check(door.open, "a restored live Open input takes control again")
signals(255, 255)
check(door.open and not door.locked, "lock request on already-open door is pending")
local status = Runtime.getDoorState(id)
check(status.actions.lockAction.status == "unavailable", "inspection separates pending lock from actual state")
signals(255, 0)
check(not door.open and door.locked, "opener closure lets pending lock apply in the same pass")
check(not ISOpenCloseDoor.isValid(interaction) and not ISOpenCloseDoor.complete(interaction)
    and nativeCalls == 0, "held Lock blocks the vanilla action before its animation")
local writes, toggles = door.lockWrites, door.toggles
signals(255, 0)
check(door.lockWrites == writes and door.toggles == toggles, "quiet held inputs produce no native writes")
door.open = true
fire("OnContainerUpdate")
check(not door.open, "native door update reapplies a held lock before the next tick")
signals(0, 0)
local lockNet, openNet = registry.network:networkOf(id, "lock"), registry.network:networkOf(id, "open")
for _, order in ipairs({ { lockNet, openNet }, { openNet, lockNet } }) do
    Runtime.prepare(registry)
    for _, run in ipairs(order) do Runtime.deliver(run, test.Packet.basic(255)) end
    Runtime.finish()
    check(not door.open and door.locked, "simultaneous ON requests obey lock precedence in either delivery order")
    ZedComm.Simulation.markDirty(lockNet); ZedComm.Simulation.markDirty(openNet)
    signals(0, 0)
end
signals(255, 0)
assert(registry:unlink(lockWire, lockSource))
fire("OnTick")
check(not door.locked, "attached Lock cable without source fails open")
assert(registry:link(lockWire, lockSource))
fire("OnTick")
check(door.locked, "restored source reapplies current lock request")
assert(registry:unlink(lockWire, id))
fire("OnTick")
check(not door.locked, "physically unwired lock restores native control")
assert(registry:unlink(openWire, id))
fire("OnTick")
check(ISOpenCloseDoor.isValid(interaction) and ISOpenCloseDoor.complete(interaction) and nativeCalls == 1,
    "unwired door retains the vanilla action")
assert(registry:link(openWire, id, "open"))
door.locked, door.keyed = true, true
signals(0, 255)
check(not door.open, "opener does not bypass a mechanical lock while Lock jack is unwired")
door.locked, door.keyed = false, false
assert(registry:link(lockWire, id, "lock"))
signals(0, 255)
check(door.open, "reconnected OFF releases lock and reconciles opener")

local saved = test.save(test.java)
test.registry, test.java = test.start(saved)
registry = test.registry
assert(Runtime.setTestByte(registry, openSource, 0))
fire("OnTick")
check(not door.open and not door.locked, "reload samples actual source state instead of replaying old ON")
check(registry.network.pieces[id].ports.lock == lockWire and registry.network.pieces[id].ports.open == openWire,
    "both independent input connections survive reload")
signals(255, 0)
saved = test.save(test.java)
test.registry, test.java = test.start(saved)
registry = test.registry
assert(Runtime.setTestByte(registry, lockSource, 0))
fire("OnTick")
check(not door.locked, "reload with OFF restores fail-open state even if native lock was saved ON")
test.inventory.full = true
check(not test.target(tile, id, "remove-door-adapters") and registry.network.pieces[id], "full inventory prevents adapter removal")
test.inventory.full = false
check(test.target(tile, id, "remove-door-adapters") and count("ZedComm.BasicAdapter") == 2
    and not door:getModData().zedcomm and door:getModData().unrelated == "preserve",
    "removal returns adapters without removing the native door or unrelated data")
check(not registry.network.pieces[lockWire].links[id] and not registry.network.pieces[openWire].links[id],
    "removing adapters detaches both runs")

test.give("ZedComm.AdvancedAdapter")
ok, id = test.runPlacement(tile, { kind = "install-door", object = door, tier = "advanced" })
assert(ok, id)
local expected = registry.network.pieces[id].state.circuit
local layout = Circuit.doorPreset()
layout.modules.source = { kind = "batterySource", column = 2, row = 1, rotation = 0, charge = 0.75, level = 100 }
layout.links[2] = { from = "source", output = "out", to = "openAction", input = "in" }
local item = test.give("ZedComm.BatterySourceModule")
item:getModData().zedcommCharge = 0.75
local entry = assert(test.placement.resolve(registry, id))
check(test.placement.editCircuit(test.player, registry, entry, expected, layout, item), "advanced door accepts existing local source module")
fire("OnTick")
check(door.open and not door.locked, "explicit internal source can control an action without an external Open cable")
check(test.target(tile, id, "remove-door-adapters") and count("ZedComm.AdvancedAdapter") == 2
    and count("ZedComm.BatterySourceModule") == 1, "advanced removal recovers modules and both adapters")
local recovered = test.inventory:getFirstType("ZedComm.BatterySourceModule")
check(recovered:getModData().zedcommCharge == 0.75, "module recovery preserves battery charge")
test.give("ZedComm.BasicAdapter"); test.give("ZedComm.BasicAdapter")
ok, id = test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic" })
assert(ok, id)
fire("OnTick")
door.destroyed = true
fire("OnObjectAboutToBeRemoved", door)
test.takeOff(tile, door)
fire("OnTick")
check(not registry.network.pieces[id] and Runtime.getDoorState(id) == nil, "destroyed native door leaves no registry or runtime binding")
test.finish()
