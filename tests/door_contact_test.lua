local test = dofile("tests/support/editor_harness.lua")()
local makeDoor = dofile("tests/support/door_fixture.lua")(function(tile)
    local object = IsoObject.new(tile, "zedcomm_devices_01_467")
    tile.objects[#tile.objects + 1] = object
    return object
end)
local check, fire = test.check, test.fire
test.player.getPerkLevel = function() return 3 end
local tile, outputTile = test.floorTile(400, 400), test.floorTile(401, 400)
local door = makeDoor(tile)
test.give("Base.Screwdriver")
local item = test.give("ZedComm.DoorContact")
local options = test.optionsAt(tile)
check(options["Install contact sensor only"] ~= nil, "contact-only fitting is available without actuator adapters")
assert(options["Install contact sensor only"])()
check(test.queued:isValid(), "contact fitting validates materials and host")
assert(test.queued:complete())
local id = door:getModData().zedcommContact
local registry, runtime = test.registry, ZedComm.DeviceRuntime
check(id ~= nil and door:getModData().zedcomm == nil and not test.inventory:contains(item),
    "contact-only fitting consumes sensor and leaves native receiver tag absent")
local entry = assert(test.placement.resolve(registry, id))
check(entry.spec.fixtureType == "Door Contact" and entry.piece.role == "source"
    and not entry.piece.board, "contact has its own source fixture and bypasses the board")
local display = test.placeTestItem(outputTile, "ZedComm.NumericDisplay")
local wire = test.runTestWire(tile, id, "signal", outputTile, display, "signal")
local function reading()
    fire("OnTick")
    return runtime.getDisplay(test.placement.resolve(registry, display).object)
end
check(reading() == 255, "closed door sends 255")
door.open = true
check(reading() == 0 and door.locked == false, "manual opening sends a valid zero without controlling door")
door.open, door.locked = false, true
check(reading() == 255, "contact reports position independently of lock state")
test.give("ZedComm.BasicAdapter"); test.give("ZedComm.BasicAdapter")
local ok, receiver = test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic" })
assert(ok, receiver)
check(door:getModData().zedcommContact == id and registry.network.pieces[id], "inputs can be fitted beside existing contact")
assert(test.target(tile, receiver, "remove-door-adapters"))
door.open = true
check(reading() == 0 and registry.network.pieces[id], "removing inputs leaves contact and its run working")
test.loaded[test.key(400, 400, 0)] = nil
check(reading() == nil, "unloaded contact publishes unavailable rather than a stale position")
test.loaded[test.key(400, 400, 0)] = true
check(reading() == 0, "reloaded contact samples actual native position")
local saved = test.save(test.java)
test.registry, test.java = test.start(saved); registry = test.registry
check(reading() == 0 and registry.network.pieces[id].ports.signal == wire, "contact identity and wire survive registry reload")
assert(registry:renameFixture(id, "Hall contact"))
local normalRemove = tile.transmitRemoveItemFromSquare
tile.transmitRemoveItemFromSquare = function(_, object)
    fire("OnObjectAboutToBeRemoved", object)
    error("injected callback before physical removal")
end
check(not test.target(tile, id, "remove-door-contact") and registry.network.pieces[id].state.fixtureName == "Hall contact"
    and registry.network.pieces[id].ports.signal == wire, "failed removal restores current fixture name and original wire")
tile.transmitRemoveItemFromSquare = normalRemove
test.inventory.full = true
check(not test.target(tile, id, "remove-door-contact") and door:getModData().zedcommContact == id,
    "full inventory preserves contact installation")
test.inventory.full = false
tile.refuseRemoval = true
check(not test.target(tile, id, "remove-door-contact") and registry.network.pieces[id], "refused native removal keeps sensor and record")
tile.refuseRemoval = nil
assert(test.target(tile, id, "remove-door-contact"))
check(not door:getModData().zedcommContact and not registry.network.pieces[id]
    and not registry.network.pieces[wire].links[id], "contact removal frees only its own run")

ok, receiver = test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic", contact = true })
assert(ok, receiver)
id = door:getModData().zedcommContact
check(id and registry.network.pieces[receiver] and registry.network.pieces[id], "combined fitting creates two distinct fixtures")
assert(test.target(tile, id, "remove-door-contact"))
check(registry.network.pieces[receiver] and door:getModData().zedcomm.id == receiver, "removing contact preserves actuator fixture")
assert(test.target(tile, receiver, "remove-door-adapters"))

local originalAdd = registry.addPiece
registry.addPiece = function(self, object)
    if object:getModData().zedcomm.definitionId == ZedComm.DoorContact.ID then return false, "injected contact failure" end
    return originalAdd(self, object)
end
local rollbackRemove = tile.transmitRemoveItemFromSquare
tile.transmitRemoveItemFromSquare = function(self, object)
    rollbackRemove(self, object)
    error("injected rollback cleanup failure")
end
local before = #test.carried
check(not test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic", contact = true })
    and #test.carried == before and not door:getModData().zedcomm and not door:getModData().zedcommContact,
    "combined fitting restores all materials and tags when contact registration fails")
local removalLogged, rollbackLogged
for _, line in ipairs(test.logged) do
    removalLogged = removalLogged or line:find("injected callback before physical removal", 1, true)
    rollbackLogged = rollbackLogged or line:find("injected rollback cleanup failure", 1, true)
end
check(removalLogged and rollbackLogged, "contact cleanup logs the original callback errors")
registry.addPiece = originalAdd
tile.transmitRemoveItemFromSquare = rollbackRemove
ok, receiver = test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic", contact = true })
assert(ok, receiver)
id = door:getModData().zedcommContact
door.destroyed = true
fire("OnObjectAboutToBeRemoved", door)
test.takeOff(tile, door)
fire("OnTick")
check(not registry.network.pieces[receiver] and not registry.network.pieces[id], "destroyed native door removes both independent records")
local orphanDoor = makeDoor(tile)
test.give("ZedComm.DoorContact")
local fitted, orphanId = test.runPlacement(tile, { kind = "install-door-contact", object = orphanDoor })
assert(fitted, orphanId)
local orphan = assert(test.placement.resolve(registry, orphanId)).object
test.takeOff(tile, orphanDoor)
registry:OnChunkLoaded(50, 50)
check(not registry.network.pieces[orphanId], "chunk reconciliation removes a saved contact whose host is gone")
local present = false
for _, object in ipairs(tile.objects) do if object == orphan then present = true end end
check(not present, "orphan cleanup also removes its world anchor")
local retryDoor = makeDoor(tile)
test.give("ZedComm.DoorContact")
fitted, id = test.runPlacement(tile, { kind = "install-door-contact", object = retryDoor })
assert(fitted, id)
local nativeRemove = tile.transmitRemoveItemFromSquare
tile.transmitRemoveItemFromSquare = function(self, object)
    nativeRemove(self, object)
    error("injected callback after removal")
end
check(test.target(tile, id, "remove-door-contact") and not retryDoor:getModData().zedcommContact,
    "exception after physical removal still returns item and clears owner marker")
tile.transmitRemoveItemFromSquare = nativeRemove
test.finish()
