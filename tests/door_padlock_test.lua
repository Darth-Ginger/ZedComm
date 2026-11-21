local test = dofile("tests/support/editor_harness.lua")()
dofile("tests/support/padlocks.lua")(test)
local check, placement, player, inventory = test.check, test.placement, test.player, test.inventory
local circuit, runtime = ZedComm.InternalCircuit, ZedComm.DeviceRuntime
local tile, inside, sourceTile = test.floorTile(110, 90), test.floorTile(110, 89), test.floorTile(111, 90)
tile.blocked, inside.blocked = inside, tile
local makeDoor = dofile("tests/support/door_fixture.lua")(function(square)
    local object = IsoObject.new(square, "test_door")
    square:AddTileObject(object)
    return object
end)
local door = makeDoor(tile)
test.give("Base.Screwdriver")
test.give("ZedComm.AdvancedAdapter")
test.give("ZedComm.AdvancedAdapter")
local installed, id = test.runPlacement(tile, { kind = "install-door", object = door, tier = "advanced" })
assert(installed, id)

local source = test.placeTestItem(sourceTile, "ZedComm.DebugByteSource")
local wire = test.placeTestItem(tile, "ZedComm.SignalWire")
assert(test.join(tile, wire, false, id, "lock"))
assert(test.join(sourceTile, wire, false, source, "signal"))

local padlock = test.give("Base.Padlock")
padlock:setKeyId(123)
getRandomUUID = function() return "test-installer-id" end
assert(test.optionsAt(inside)["Padlock door board (Remember me)"])()
check(test.queued:isValid() and test.queued:complete(), "either face can fit a door board padlock")
local key = assert(inventory:haveThisKeyId(123))
while inventory:haveThisKeyId(123) do inventory:Remove(inventory:haveThisKeyId(123)) end
local function piece() return test.registry.network.pieces[id] end
local function entry() return placement.resolve(test.registry, id) end

assert(test.optionsAt(inside)["Open Door Board"])()
check(test.panel ~= nil and piece().ports.lock == wire and circuit.padlockId(piece()) == 123,
    "the installer opens a locked board from the inside without a key")
local layout = piece().state.circuit
local edited = test.registry.network:record(id).state.circuit
check(placement.editCircuit(player, test.registry, entry(), layout, edited)
    and test.registry:renameCabinetPort(id, "lock", "Entry lock", player)
    and circuit.remembersPlayer(piece(), player), "board edits and jack labels preserve remembered access")
check(not test.target(tile, id, "remove-door-adapters"),
    "remove the padlock before taking the door adapters off")

local otherWire = test.placeTestItem(tile, "ZedComm.SignalWire")
local ownerData = player.modData
player.modData = { zedcommPadlockIdentity = "another-survivor" }
test.panel:render()
check(test.panel == nil and not test.optionsAt(inside)["Open Door Board"]
    and not test.optionsAt(tile)["Open Door Board"], "another survivor has no keyless board access from either side")
check(not test.target(tile, id, "disconnect-port", { port = "lock", cableId = wire })
    and not test.target(tile, wire, "pickup")
    and not test.join(tile, otherWire, false, id, "open"), "the same lock blocks jack edits and direct wire pickup")
check(not test.target(tile, id, "remove-padlock", { keyId = 123 }),
    "another survivor cannot remove the padlock without a matching key")

assert(runtime.setTestByte(test.registry, source, 255))
test.fire("OnTick")
check(door:isLocked() and not door:isOpen(), "a padlocked board still runs the physical door actuator")
assert(runtime.setTestByte(test.registry, source, 0))
test.fire("OnTick")
check(not door:isLocked() and circuit.padlockId(piece()) == 123,
    "network unlock changes the native door while the board stays padlocked")

inventory:AddItem(key)
check(test.optionsAt(inside)["Open Door Board"] ~= nil and inventory:contains(key),
    "a different survivor can service the board with a matching key")
inventory:Remove(key)
player.modData = { zedcommPadlockIdentity = ownerData.zedcommPadlockIdentity }
test.registry, test.java = test.start(test.save(test.java))
check(test.optionsAt(inside)["Open Door Board"] ~= nil and piece().ports.lock == wire,
    "reload preserves the remembered survivor, locked board, and attached jack")
check(test.target(tile, id, "disconnect-port", { port = "lock", cableId = wire })
    and test.join(tile, wire, false, id, "lock"), "the remembered player can detach and reconnect a padlocked jack")
assert(test.optionsAt(inside)["Remove padlock"])()
check(test.queued:isValid() and test.queued:complete() and circuit.padlockId(piece()) == nil
    and inventory:getFirstType("Base.Padlock"):getNumberOfKey() == 0, "remembered removal needs no key and creates no duplicate keys")
assert(test.optionsAt(inside)["Padlock door board"])()
check(test.queued:complete() and inventory:haveThisKeyId(123),
    "refitting the same lock without Remember me issues a usable backup key")
assert(test.target(tile, id, "remove-padlock", { keyId = 123 }))
check(test.target(tile, id, "remove-door-adapters"), "the adapters can be removed after taking off the padlock")
test.finish()
