local test = dofile("tests/support/placement_harness.lua")()
local makeDoor = dofile("tests/support/door_fixture.lua")(function(tile)
    local object = IsoObject.new(tile, "zedcomm_devices_01_467")
    tile.objects[#tile.objects + 1] = object
    return object
end)
local originalSprite = getSprite
getSprite = function(name)
    if name:match("^zedcomm_door.*_%d+$") then return { getName = function() return name end } end
    return originalSprite(name)
end
FBORenderChunk.DIRTY_OBJECT_MODIFY = 256
require "ZedComm/DoorVisuals"
local visuals, check = ZedComm.DoorVisuals, test.check
local tile = test.floorTile(300, 300)
local northFace = test.floorTile(300, 299)
local westFace = test.floorTile(299, 300)
local door = makeDoor(tile)
test.player.getPerkLevel = function() return 3 end
test.give("Base.Screwdriver")
test.give("ZedComm.BasicAdapter"); test.give("ZedComm.BasicAdapter")
local ok, id = test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic" })
assert(ok, id)
local network = test.registry.network
local function housing()
    for _, object in ipairs(tile.objects) do
        if object:getModData().zedcommDoorHousing == id then return object end
    end
end
local function name()
    local frame = housing()
    return frame and frame:getSprite():getName()
end
local nativeSprite = door:getSprite()
test.player.tile = northFace
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_0" and housing().noPicking, "north face has a non-pickable unwired housing")
door.locked = true
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_36", "indicator follows actual locked state")
door.open = true
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_36" and door:getSprite() == nativeSprite, "opening retains frame housing without replacing native sprite")
for _, face in ipairs({
    { north = true, square = tile, frame = 180, name = "south" },
    { north = false, square = tile, frame = 252, name = "east" },
    { north = false, square = westFace, frame = 108, name = "west" },
}) do
    door.north, test.player.tile = face.north, face.square
    visuals.update(network, getCell())
    check(name() == "zedcomm_door_01_" .. face.frame, face.name .. " face follows the viewer")
end
local laid, wire = test.lay(tile, test.give("ZedComm.SignalWire"), id, "lock")
assert(laid, wire)
test.player.tile = westFace
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_114", "same-tile Lock connection changes its socket independently")
local frame = housing()
visuals = dofile(test.LUA .. "client/ZedComm/DoorVisuals.lua")
visuals.update(network, getCell())
check(housing() == frame and not door:getAttachedAnimSprite(), "visual reload reuses the separate housing")
door.openSprite = { getProperties = function() return { has = function(_, key) return key == "attachedE" end } end }
visuals.update(network, getCell())
check(name() == "zedcomm_door_reverse_01_114", "opposite hinge selects reversed jamb routing")
door.openSprite = nil
assert(test.registry:unlink(wire, id))
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_108", "disconnect clears wire tell")
assert(test.target(tile, id, "remove-door-adapters"))
visuals.update(network, getCell())
check(not housing() and door:getSprite() == nativeSprite,
    "removal clears housing and preserves original door sprite")
test.finish()
