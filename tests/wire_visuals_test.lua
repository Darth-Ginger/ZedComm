local testState = dofile("tests/support/placement_harness.lua")()
local LUA = testState.LUA
local check = testState.check
local list = testState.list
local square = testState.square
local worldObject = testState.worldObject
local takeOff = testState.takeOff
local save = testState.save
local fire = testState.fire
local start = testState.start
local placement = testState.placement
local inventory = testState.inventory
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local target = testState.target
local lay = testState.lay
local spriteOf = testState.spriteOf

local p0, w0, w1, d0, plateId, displayId, replacement, secondWire = dofile("tests/support/bend_fixture.lua")(testState)

-- Update wires and plate terminals using the real topology and square-load callbacks.
dofile(LUA .. "client/ZedComm/WireVisuals.lua")
fire("OnTick")
check(spriteOf(replacement) == "zedcomm_devices_01_9"
    and spriteOf(secondWire) == "zedcomm_devices_01_11", "both bends use their actual orthogonal connections")
check(spriteOf(plateId) == "zedcomm_devices_01_22", "existing plate shows the lead to its +X cable")
local replacedWireObject = placement.resolve(testState.registry, replacement).object
replacedWireObject.sprite = "zedcomm_devices_01_1"
fire("LoadGridsquare", w0)
check(spriteOf(replacement) == "zedcomm_devices_01_9", "a streamed-in wire gets the current variant")
assert(testState.registry:unlink(secondWire, displayId))
fire("OnTick")
check(spriteOf(secondWire) == "zedcomm_devices_01_10", "disconnect exposes a capped free end")
assert(testState.registry:link(secondWire, displayId))
fire("OnTick")
check(spriteOf(secondWire) == "zedcomm_devices_01_11", "reconnect restores the bend sprite")
local unlinkedTile = floorTile(42, 40)
local unlinked = worldObject(unlinkedTile, {
    id = "unlinked-neighbor", kind = "cable", placedItem = "ZedComm.SignalWire",
})
function unlinked.getSprite() return nil end
function unlinked.setSprite(_, sprite) unlinked.sprite = sprite:getName() end
fire("OnObjectAdded", unlinked)
fire("OnTick")
check(unlinked.sprite == "zedcomm_devices_01_3" and spriteOf(secondWire) == "zedcomm_devices_01_11",
    "adjacent unlinked wires stay visually separate")
testState.registry, testState.java = start(save(testState.java))
replacedWireObject.sprite = "zedcomm_devices_01_1"
placement.resolve(testState.registry, plateId).object.sprite = "zedcomm_devices_01_0"
fire("OnTick")
check(spriteOf(replacement) == "zedcomm_devices_01_9", "wire shapes are rederived after reload")
check(spriteOf(plateId) == "zedcomm_devices_01_22", "plate direction is rederived from the saved link")

do
    local tile, wireTile = floorTile(50, 59), floorTile(51, 59)
    tile.northWall = {}
    local function setFloor()
        local floor = worldObject(tile)
        local attachments = {}
        function floor:getAttachedAnimSprite() return list(attachments) end
        function floor:addAttachedAnimSprite(sprite)
            attachments[#attachments + 1] = { getParentSprite = function() return sprite end }
        end
        function floor:RemoveAttachedAnim(index) table.remove(attachments, index + 1) end
        function floor:invalidateRenderChunkLevel() end
        tile.floor = floor
        return floor, attachments
    end
    local original, attachments = setFloor()
    original:addAttachedAnimSprite(getSprite("zedcomm_devices_01_1"))
    local placed, id = runPlacement(tile, { kind = "place", item = give("ZedComm.NetworkSwitch") })
    assert(placed)
    local laid, cable = lay(wireTile, give("ZedComm.SignalWire"), id, "signal")
    assert(laid)
    local function leadObjects()
        local found = {}
        for _, object in ipairs(tile.objects) do
            if object:getModData().zedcommSwitchLead then found[#found + 1] = object end
        end
        return found
    end
    fire("OnTick")
    local lead = leadObjects()[1]
    check(#attachments == 1 and lead and lead.sprite == "zedcomm_switch_floor_01_1",
        "the switch lead is a standalone overlay and preserves unrelated floor attachments")
    fire("OnObjectAboutToBeRemoved", original)
    takeOff(tile, original)
    local replacement, replacementAttachments = setFloor()
    fire("OnObjectAdded", replacement)
    fire("OnTick")
    check(#replacementAttachments == 0 and leadObjects()[1] == lead, "reflooring keeps the grounded overlay")
    fire("LoadGridsquare", tile)
    check(#leadObjects() == 1, "loading the floor does not duplicate the lead")
    assert(target(tile, id, "pickup"))
    fire("OnTick")
    check(#leadObjects() == 0 and testState.registry.network:record(cable), "pickup clears only the floor lead")
    inventory:Remove(inventory:getFirstType("ZedComm.NetworkSwitch"))
end

do
    local tile = floorTile(49, 50)
    local placed, display = runPlacement(tile, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(placed)
    local laid, cable = lay(tile, give("ZedComm.SignalWire"), display, "signal")
    assert(laid)
    local displayObject = placement.resolve(testState.registry, display).object
    local cableObject = placement.resolve(testState.registry, cable).object
    fire("OnTick")
    check(tile.objects[1] == cableObject and tile.objects[2] == displayObject
        and displayObject.chunkDirty == FBORenderChunk.DIRTY_OBJECT_ADD,
        "a wire laid after a display renders beneath its face")
    tile.objects[1], tile.objects[2] = displayObject, cableObject
    fire("LoadGridsquare", tile)
    check(tile.objects[1] == cableObject and testState.registry.network:record(display).ports.signal == cable,
        "square load restores draw order without touching the wire connection")
    displayObject:setSprite(getSprite("zedcomm_devices_01_466"))
    tile.objects[1], tile.objects[2] = displayObject, cableObject
    fire("LoadGridsquare", tile)
    check(tile.objects[1] == displayObject and tile.objects[2] == cableObject,
        "a raised sprite does not reorder same-tile wires even on a display definition")
end

do
    local tile = floorTile(50, 50)
    local ok, id = runPlacement(tile, { kind = "place", item = give("ZedComm.PressurePlate") })
    assert(ok, id)
    local decoy = worldObject(floorTile(51, 50), { id = "plate-visual-decoy", kind = "cable" })
    fire("OnObjectAdded", decoy)
    local plateObject = placement.resolve(testState.registry, id).object
    plateObject.spriteInstance = { getName = function() return "zedcomm_devices_01_20" end,
        getProperties = getSprite("zedcomm_devices_01_20").getProperties }
    fire("OnTick")
    check(plateObject:getSprite() == getSprite("zedcomm_devices_01_20"),
        "an unlinked neighbor leaves an empty socket using the registered floor sprite")

    for _, route in ipairs({ { 50, 51, 23 }, { 49, 50, 24 }, { 50, 49, 25 }, { 50, 50, 21 } }) do
        local wireTile = floorTile(route[1], route[2])
        local laid, cableId = lay(wireTile, give("ZedComm.SignalWire"), id, "signal")
        assert(laid, cableId)
        fire("OnTick")
        check(spriteOf(id) == "zedcomm_devices_01_" .. route[3], "plate follows the cable for frame " .. route[3])
        assert(target(wireTile, cableId, "pickup"))
    end
    fire("OnTick")
    check(spriteOf(id) == "zedcomm_devices_01_20", "picking up the linked cable restores the empty socket")
end

-- Parallel routes share lane positions across tile edges and around bends.
do
    local left, middle, right, south = floorTile(47, 62), floorTile(48, 62), floorTile(49, 62), floorTile(49, 63)
    local function parallelCable(tile, id)
        local object = IsoObject.new(tile, "zedcomm_devices_01_1")
        object:getModData().zedcomm = { id = id, kind = "cable", placedItem = "ZedComm.SignalWire" }
        tile:AddTileObject(object)
        fire("OnObjectAdded", object)
        return object
    end
    for _, lane in ipairs({ "parallel-b", "parallel-a" }) do
        parallelCable(left, lane .. "-left")
        parallelCable(middle, lane .. "-middle")
        parallelCable(right, lane .. "-right")
        parallelCable(south, lane .. "-south")
        assert(testState.registry:link(lane .. "-left", lane .. "-middle"))
        assert(testState.registry:link(lane .. "-middle", lane .. "-right"))
        assert(testState.registry:link(lane .. "-right", lane .. "-south"))
    end
    fire("OnTick")
    local function frame(id, index)
        return spriteOf(id) == "zedcomm_devices_01_" .. index
    end
    check(frame("parallel-a-left", 190) and frame("parallel-a-middle", 257)
        and frame("parallel-b-left", 192) and frame("parallel-b-middle", 292),
        "parallel straight routes keep distinct matching lanes at the seam")
    check(frame("parallel-a-right", 355) and frame("parallel-a-south", 207)
        and frame("parallel-b-right", 334) and frame("parallel-b-south", 205),
        "parallel elbows preserve each lane across the turn and out the next seam")
    testState.registry, testState.java = start(save(testState.java))
    fire("OnTick")
    check(frame("parallel-a-middle", 257) and frame("parallel-a-right", 355)
        and frame("parallel-b-middle", 292) and frame("parallel-b-right", 334),
        "parallel visual lanes are stable across reload despite reverse placement order")
    assert(target(middle, "parallel-a-middle", "pickup"))
    fire("OnTick")
    check(spriteOf("parallel-b-middle") == "zedcomm_devices_01_8"
        and #testState.registry.network:partners("parallel-b-middle") == 2,
        "a remaining parallel wire returns to the centered sprite and keeps both links")

    local cableTile, deviceTile = floorTile(51, 62), floorTile(52, 62)
    local ok, device = runPlacement(deviceTile, { kind = "place", item = give("ZedComm.PressurePlate") })
    assert(ok, device)
    parallelCable(cableTile, "port-wire")
    parallelCable(cableTile, "passing-wire")
    parallelCable(deviceTile, "passing-other")
    assert(testState.registry:link("port-wire", device, "signal"))
    assert(testState.registry:link("passing-wire", "passing-other"))
    fire("OnTick")
    check(frame("port-wire", 191) and frame("passing-wire", 192) and frame("passing-other", 202),
        "an adjacent device keeps its centered lead and the passing wire keeps a distinct lane")
end


testState.finish()
