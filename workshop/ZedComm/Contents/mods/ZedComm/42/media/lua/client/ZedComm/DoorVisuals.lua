-- Frame-mounted housing stays on the original door object through native toggles.
require "ZedComm/ModuleVisuals"
local Visuals = {}
local attached, contacts = {}, {}
local directions = { [0] = 1, [1] = 2, [2] = 3, [4] = 4, [8] = 5 }
local prefix = "zedcomm_door_01_"
local mounts = { north = 0, west = 1, south = 2, east = 3 }
local floors = {}

local function matches(name)
    return name ~= nil and (name:sub(1, #prefix) == prefix or name:match("^zedcomm_door_reverse_01_"))
end

local function set(object, name)
    if ZedComm.ModuleVisuals.setAttachment(object, name, matches) then
        object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY)
    end
end

function Visuals.frame(object, network, piece)
    local shape = ZedComm.WireShape
    local lock = directions[shape.portDirection(network, piece, "lock")] or 0
    local open = directions[shape.portDirection(network, piece, "open")] or 0
    local mount = piece.state and piece.state.doorMount or (object:getNorth() and "north" or "west")
    return (mounts[mount] or 0) * 72 + (object:isLocked() and 36 or 0) + lock * 6 + open
end

local function contactSprite(name)
    local index = name and tonumber(name:match("^zedcomm_devices_01_(%d+)$"))
    return index ~= nil and index >= 38 and index <= 43
end

local function setContact(object, name)
    if ZedComm.ModuleVisuals.setAttachment(object, name, contactSprite) then
        object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY)
    end
end

function Visuals.update(network, cell)
    local seen, seenContacts = {}, {}
    for id, piece in pairs(network and network.pieces or {}) do
        if piece.definitionId == ZedComm.DoorContact.ID then
            local square = cell and cell:getGridSquare(piece.x, piece.y, piece.z)
            local objects = square and square:getObjects()
            for i = 0, objects and objects:size() - 1 or -1 do
                local object = objects:get(i)
                local tag = object:hasModData() and object:getModData().zedcomm
                if tag and tag.id == id then
                    local door = ZedComm.DoorContact.host(object)
                    if door then
                        local direction = ZedComm.WireShape.portDirection(network, piece, "signal")
                        local name = "zedcomm_devices_01_" .. (38 + (directions[direction] or 0))
                        seenContacts[door] = name
                        if contacts[door] ~= name then setContact(door, name) end
                    end
                end
            end
        elseif piece.definitionId == ZedComm.InternalCircuit.DOOR_ID then
            local square = cell and cell:getGridSquare(piece.x, piece.y, piece.z)
            local objects = square and square:getObjects()
            for i = 0, objects and objects:size() - 1 or -1 do
                local object = objects:get(i)
                local tag = object:hasModData() and object:getModData().zedcomm
                if tag and tag.id == id and ZedComm.Door.isEligible(object) then
                    local reverse = ZedComm.Door.reverseHinge(object)
                    local frame = Visuals.frame(object, network, piece)
                    local name = (reverse and "zedcomm_door_reverse_01_" or prefix) .. frame
                    local floorName = "zedcomm_door_floor_01_" .. (math.floor(frame / 72) * 72 + (reverse and 36 or 0) + frame % 36)
                    local floor = floors[object]
                    if not floor then
                        for j = 0, objects:size() - 1 do
                            local candidate = objects:get(j)
                            if candidate:hasModData() and candidate:getModData().zedcommDoorLead == id then floor = candidate end
                        end
                    end
                    if not floor or floor:getSquare() ~= square then
                        floor = IsoObject.new(square, floorName, "ZedComm door leads")
                        floor:getModData().zedcommDoorLead = id
                        square:AddTileObject(floor)
                    end
                    floors[object] = floor
                    local sprite = getSprite(floorName)
                    if sprite and floor:getSprite() ~= sprite then
                        floor:setSprite(sprite)
                        floor:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY)
                    end
                    seen[object] = name
                    if attached[object] ~= name then set(object, name) end
                end
            end
        end
    end
    for object in pairs(attached) do
        if not seen[object] then
            set(object, nil)
            local floor = floors[object]
            if floor and floor:getSquare() then floor:getSquare():transmitRemoveItemFromSquare(floor) end
            floors[object] = nil
        end
    end
    for door in pairs(contacts) do
        if not seenContacts[door] then setContact(door, nil) end
    end
    contacts = seenContacts
    attached = seen
end

Events.LoadGridsquare.Add(function(square)
    local registry = ZedComm.Registry and ZedComm.Registry.instance
    if not registry then return end
    local objects = square:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local object = objects:get(i)
        local id = object:hasModData() and object:getModData().zedcommDoorLead
        if id and not registry.network.pieces[id] then square:transmitRemoveItemFromSquare(object) end
    end
end)

ZedComm.DoorVisuals = Visuals
return Visuals
