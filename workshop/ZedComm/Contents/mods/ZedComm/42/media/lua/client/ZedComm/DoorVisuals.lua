-- Door housings render at the frame without inheriting door-leaf cutaway.
require "ZedComm/ModuleVisuals"
local Visuals = {}
local entries = {}
local mounts = { north = 0, west = 1, south = 2, east = 3 }

local function viewerMount(object, viewer)
    local square = object:getSquare()
    if object:isNorth() then
        return viewer and viewer:getY() >= square:getY() and mounts.south or mounts.north
    end
    return viewer and viewer:getX() >= square:getX() and mounts.east or mounts.west
end

local function actuatorSprite(name)
    return name ~= nil and (name:match("^zedcomm_door_01_%d+$")
        or name:match("^zedcomm_door_reverse_01_%d+$"))
end

local function contactSprite(name)
    return name ~= nil and (name:match("^zedcomm_contact_01_%d+$")
        or name:match("^zedcomm_window_contact_01_%d+$"))
end

local function actuatorFrame(object, network, piece, mount)
    local shape = ZedComm.WireShape
    local lock = ZedComm.WireShape.portFrames[shape.portDirection(network, piece, "lock")] or 0
    local open = ZedComm.WireShape.portFrames[shape.portDirection(network, piece, "open")] or 0
    return mount * 72 + (object:isLocked() and 36 or 0) + lock * 6 + open
end

local function setAttachment(entry, name)
    if ZedComm.ModuleVisuals.setAttachment(entry.door, name, entry.matches) then
        entry.door:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY)
    end
end

local leadKey, housingKey = "zedcommDoorLead", "zedcommDoorHousing"

local function removeHelper(object)
    if object and object:getSquare() then object:getSquare():transmitRemoveItemFromSquare(object) end
end

local function syncHelper(object, square, id, key, name)
    if not object or object:getSquare() ~= square then
        object = nil
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local candidate = objects:get(i)
            if candidate:hasModData() and candidate:getModData()[key] == id then
                object = candidate
                break
            end
        end
    end
    local sprite = name and getSprite(name)
    if not sprite then
        removeHelper(object)
        return nil
    end
    if not object then
        object = IsoObject.new(square, name, "ZedComm door fixture visual")
        object:getModData()[key] = id
        square:AddTileObject(object)
    elseif object:getSprite() ~= sprite then
        object:setSprite(sprite)
        object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY)
    end
    if key == housingKey then object:setNoPicking(true) end
    return object
end

local function clearEntry(entry)
    setAttachment(entry, nil)
    removeHelper(entry.housing)
    removeHelper(entry.lead)
end

local function findObject(square, id)
    local objects = square and square:getObjects()
    for i = 0, objects and objects:size() - 1 or -1 do
        local object = objects:get(i)
        local tag = object:hasModData() and object:getModData().zedcomm
        if tag and tag.id == id then return object end
    end
end

function Visuals.update(network, cell)
    local player = getSpecificPlayer(0)
    local viewer = player and player:getCurrentSquare()
    local seen = {}
    for id, piece in pairs(network and network.pieces or {}) do
        local contact = ZedComm.DoorContact.profiles[piece.definitionId]
        if contact and not contact.edge then contact = nil end
        if contact or piece.definitionId == ZedComm.InternalCircuit.DOOR_ID then
            local square = cell and cell:getGridSquare(piece.x, piece.y, piece.z)
            local object = findObject(square, id)
            local door = object
            if contact and object then door = ZedComm.DoorContact.host(object) end
            if door and (contact or ZedComm.Door.isEligible(door)) then
                local entry = entries[id]
                if entry and entry.door ~= door then clearEntry(entry); entry = nil end
                local isWindow = piece.definitionId == ZedComm.DoorContact.WINDOW_ID
                if not entry then
                    entry = { door = door, matches = contact and contactSprite or actuatorSprite }
                    if not isWindow then setAttachment(entry, nil) end
                end
                local reverse = not isWindow and ZedComm.Door.reverseHinge(door) and 1 or 0
                local mount = viewerMount(door, viewer)
                local name, floorName
                if contact then
                    local direction = ZedComm.WireShape.portFrames[ZedComm.WireShape.portDirection(network, piece, "signal")] or 0
                    local frame = mount * 12 + reverse * 6 + direction
                    local framesPerFace = isWindow and 12 or 24
                    name = contact.prefix .. (mount * framesPerFace + reverse * 12
                        + (contact.isClosed(door) and 6 or 0) + direction)
                    if direction > 0 then floorName = "zedcomm_contact_floor_01_" .. frame end
                else
                    local frame = actuatorFrame(door, network, piece, mount)
                    name = (reverse == 1 and "zedcomm_door_reverse_01_" or "zedcomm_door_01_") .. frame
                    local wireFrame = frame % 36
                    if wireFrame > 0 then
                        floorName = "zedcomm_door_floor_01_" .. (mount * 72 + reverse * 36 + wireFrame)
                    end
                end
                if isWindow then
                    if entry.name ~= name then setAttachment(entry, name) end
                elseif entry.name ~= name or not entry.housing or entry.housing:getSquare() ~= square then
                    entry.housing = syncHelper(entry.housing, square, id, housingKey, name)
                end
                if not entry.name or entry.floorName ~= floorName
                    or (floorName and (not entry.lead or entry.lead:getSquare() ~= square)) then
                    entry.lead = syncHelper(entry.lead, square, id, leadKey, floorName)
                end
                entry.name, entry.floorName = name, floorName
                seen[id] = entry
            end
        end
    end
    for id, entry in pairs(entries) do
        if not seen[id] then clearEntry(entry) end
    end
    entries = seen
end

Events.LoadGridsquare.Add(function(square)
    local registry = ZedComm.Registry and ZedComm.Registry.instance
    if not registry then return end
    local objects = square:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local object = objects:get(i)
        local data = object:hasModData() and object:getModData()
        local id = data and (data[leadKey] or data[housingKey])
        if id and not registry.network.pieces[id] then removeHelper(object) end
    end
end)

ZedComm.DoorVisuals = Visuals
return Visuals
