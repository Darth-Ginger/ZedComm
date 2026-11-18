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
local door = makeDoor(tile)
test.player.getPerkLevel = function() return 3 end
test.give("Base.Screwdriver")
test.give("ZedComm.BasicAdapter"); test.give("ZedComm.BasicAdapter")
local ok, id = test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic" })
assert(ok, id)
local network = test.registry.network
network.pieces[id].state.doorMount = nil
local function name()
    local children = door:getAttachedAnimSprite()
    return children and children:get(0):getParentSprite():getName()
end
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_0", "unwired north door has a housing")
local nativeSprite = door:getSprite()
door.locked = true
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_36", "indicator follows actual locked state")
door.open = true
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_36" and door:getSprite() == nativeSprite, "opening retains frame housing without replacing native sprite")
door.north = false
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_108", "west door selects mirrored mounting")
for mount, offset in pairs({ north = 0, west = 72, south = 144, east = 216 }) do
    network.pieces[id].state.doorMount = mount
    visuals.update(network, getCell())
    check(name() == "zedcomm_door_01_" .. (offset + 36), mount .. " mounting face has independent art")
end
network.pieces[id].state.doorMount = nil
local laid, wire = test.lay(tile, test.give("ZedComm.SignalWire"), id, "lock")
assert(laid, wire)
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_114", "same-tile Lock connection changes its socket independently")
visuals.update(network, getCell())
check(door:getAttachedAnimSprite():size() == 1, "held visual state does not duplicate attachments")
door.openSprite = { getProperties = function() return { has = function(_, key) return key == "attachedE" end } end }
visuals.update(network, getCell())
check(name() == "zedcomm_door_reverse_01_114", "opposite hinge selects reversed jamb routing")
door.openSprite = nil
assert(test.registry:unlink(wire, id))
visuals.update(network, getCell())
check(name() == "zedcomm_door_01_108", "disconnect clears wire tell")
assert(test.target(tile, id, "remove-door-adapters"))
visuals.update(network, getCell())
check(door:getAttachedAnimSprite() == nil and door:getSprite() == nativeSprite,
    "removal clears housing and preserves original door sprite")
test.finish()
