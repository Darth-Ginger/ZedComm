local test = dofile("tests/support/placement_harness.lua")()
local makeDoor = dofile("tests/support/door_fixture.lua")(function(tile)
    local object = IsoObject.new(tile, "zedcomm_devices_01_467")
    tile.objects[#tile.objects + 1] = object
    return object
end)
require "ZedComm/DoorVisuals"
local visuals, check = ZedComm.DoorVisuals, test.check
test.player.getPerkLevel = function() return 3 end
test.give("Base.Screwdriver"); test.give("ZedComm.DoorContact")
local tile = test.floorTile(450, 450)
local northFace = test.floorTile(450, 449)
local westFace = test.floorTile(449, 450)
local door = makeDoor(tile)
local ok, id = test.runPlacement(tile, { kind = "install-door-contact", object = door })
assert(ok, id)
local registry, nativeSprite = test.registry, door:getSprite()
local function contactName()
    local children = door:getAttachedAnimSprite()
    for i = 0, children and children:size() - 1 or -1 do
        local name = children:get(i):getParentSprite():getName()
        if name:match("^zedcomm_contact_01_") then return name end
    end
end
local function leads()
    local count = 0
    for _, object in ipairs(tile.objects) do
        if object:getModData().zedcommDoorLead == id then count = count + 1 end
    end
    return count
end
for _, face in ipairs({
    { north = true, square = northFace, frame = 0, name = "north" },
    { north = true, square = tile, frame = 48, name = "south" },
    { north = false, square = westFace, frame = 24, name = "west" },
    { north = false, square = tile, frame = 72, name = "east" },
}) do
    door.north, test.player.tile = face.north, face.square
    for reverse = 0, 1 do
        door.openSprite = reverse == 1 and { getProperties = function()
            return { has = function(_, key) return key == "attachedE" end }
        end } or nil
        door.open = false
        visuals.update(registry.network, getCell())
        check(contactName() == "zedcomm_contact_01_" .. (face.frame + reverse * 12 + 6), face.name .. " closed sensor selects its hinge and face")
        door.open = true
        visuals.update(registry.network, getCell())
        check(contactName() == "zedcomm_contact_01_" .. (face.frame + reverse * 12), face.name .. " open sensor changes magnet spacing")
    end
end
check(leads() == 0, "unwired contact creates no floor lead helper")
door.open = true
door.openSprite = { getProperties = function() return { has = function(_, key) return key == "attachedE" end } end }
local laid, wire = test.lay(tile, test.give("ZedComm.SignalWire"), id, "signal")
assert(laid, wire)
visuals.update(registry.network, getCell())
check(leads() == 1 and contactName() == "zedcomm_contact_01_85", "wired contact has its own jamb and floor lead")
visuals = dofile(test.LUA .. "client/ZedComm/DoorVisuals.lua")
visuals.update(registry.network, getCell())
check(leads() == 1 and door:getAttachedAnimSprite():size() == 1, "visual reconstruction reuses lead and attachment")
assert(registry:unlink(wire, id))
visuals = dofile(test.LUA .. "client/ZedComm/DoorVisuals.lua")
visuals.update(registry.network, getCell())
check(leads() == 0, "reconstruction removes saved floor lead when fixture is now unwired")
assert(registry:link(wire, id, "signal"))
visuals.update(registry.network, getCell())
check(leads() == 1, "reconnecting rebuilds exactly one floor lead")
test.give("ZedComm.BasicAdapter"); test.give("ZedComm.BasicAdapter")
local fitted, receiver = test.runPlacement(tile, { kind = "install-door", object = door, tier = "basic" })
assert(fitted, receiver)
visuals.update(registry.network, getCell())
check(door:getAttachedAnimSprite():size() == 2 and door:getSprite() == nativeSprite, "independent housings coexist without replacing native door")
assert(test.target(tile, id, "remove-door-contact"))
visuals.update(registry.network, getCell())
check(leads() == 0 and contactName() == nil and door:getAttachedAnimSprite():size() == 1,
    "contact removal clears its own housing and floor lead only")
test.finish()
