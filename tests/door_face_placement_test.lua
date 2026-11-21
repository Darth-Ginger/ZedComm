local test = dofile("tests/support/menu_harness.lua")()
local check, placement = test.check, test.placement
local makeDoor = dofile("tests/support/door_fixture.lua")(function(tile)
    local door = IsoObject.new(tile, "zedcomm_devices_01_467")
    tile:AddTileObject(door)
    return door
end)
local owner, far = test.floorTile(50, 50), test.floorTile(49, 50)
local otherWall = test.floorTile(50, 49)
owner.blocked, far.blocked, otherWall.blocked = far, owner, owner
local door = makeDoor(owner, "IsoDoor")
door.north = false
test.give("Base.Screwdriver")
test.give("ZedComm.BasicAdapter"); test.give("ZedComm.BasicAdapter")
test.give("ZedComm.DoorContact")

local options = test.optionsAt(far, "Door")
assert(options["Install Basic inputs and contact"])()
check(test.queued:isValid() and test.queued:complete(), "combined fitting works from the west face of a closed door")
local data = door:getModData()
local id, contact = data.zedcomm.id, data.zedcommContact
local network = test.registry.network

local function placeWire(tile)
    local ok, result = test.runPlacement(tile, { kind = "place", item = test.give("ZedComm.SignalWire") })
    assert(ok, result)
    return result
end
local farWire, nearWire, wallWire = placeWire(far), placeWire(owner), placeWire(otherWall)
local function entry(pieceId) return assert(placement.resolve(test.registry, pieceId)) end
check(not placement.canJoin(network, entry(wallWire), false, entry(id), "lock"),
    "a door does not exempt another blocked edge")
check(not placement.canJoin(network, entry(farWire), false, entry(nearWire), false),
    "two cables cannot cross the closed doorway by joining each other")

assert(test.optionsAt(far)["Select wire free end"])()
test.fire("OnTick")
local connect = assert(test.optionsAt(far, "Door")["Connect wire to networked door (Lock IN)"])
connect()
check(test.queued:isValid() and test.queued:complete() and network.pieces[id].ports.lock == farWire,
    "an existing far-face run can connect to a door jack through its submenu")

local otherSideOptions = test.optionsAt(far, "Door Contact")
assert(otherSideOptions["Select door contact free end"])()
check(test.optionsAt(far)["Pause wire run"] ~= nil, "contact end is selectable from the opposite face")
local short = test.floorTile(48, 50)
check(not placement.canLay(entry(contact), "signal", short),
    "target discovery leaves physical cable reach anchored to the door edge")
local ok, newWire = test.lay(far, test.give("ZedComm.SignalWire"), contact, "signal")
check(ok and network.pieces[contact].ports.signal == newWire,
    "detached contact can lay its first cable on the far face")
assert(test.optionsAt(far, "Door Contact")["Remove door contact"])()
check(test.queued:isValid() and test.queued:complete() and not network.pieces[contact]
    and network.pieces[id].ports.lock == farWire,
    "removing a contact from the far face preserves the actuator connection")
test.finish()
