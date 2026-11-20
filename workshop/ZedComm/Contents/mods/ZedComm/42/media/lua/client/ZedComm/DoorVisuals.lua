-- Housings attach to native doors; grounded leads render above finished floors.
require "ZedComm/ModuleVisuals"
local Visuals = {}
local entries = {}
local directions = { [0] = 1, [1] = 2, [2] = 3, [4] = 4, [8] = 5 }
local mounts = { north = 0, west = 1, south = 2, east = 3 }

local function actuatorSprite(name)
    return name ~= nil and (name:match("^zedcomm_door_01_%d+$")
        or name:match("^zedcomm_door_reverse_01_%d+$"))
end

local function contactSprite(name)
    return name ~= nil and (name:match("^zedcomm_contact_01_%d+$")
        or name:match("^zedcomm_window_contact_01_%d+$"))
end

local function mountOf(object, piece)
    local mount = piece.state and piece.state.doorMount
    if not mount then
        local north
        if instanceof(object, "IsoWindow") then north = object:isNorth() else north = object:getNorth() end
        mount = north and "north" or "west"
    end
    return mounts[mount]
end

function Visuals.frame(object, network, piece)
    local shape = ZedComm.WireShape
    local lock = directions[shape.portDirection(network, piece, "lock")] or 0
    local open = directions[shape.portDirection(network, piece, "open")] or 0
    return mountOf(object, piece) * 72 + (object:isLocked() and 36 or 0) + lock * 6 + open
end

local function setAttachment(entry, name)
    if ZedComm.ModuleVisuals.setAttachment(entry.door, name, entry.matches) then
        entry.door:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY)
    end
end

local function removeLead(entry)
    local lead = entry.lead
    if lead and lead:getSquare() then lead:getSquare():transmitRemoveItemFromSquare(lead) end
    entry.lead = nil
end

local function syncLead(entry, square, id, name)
    if entry.lead and entry.lead:getSquare() ~= square then entry.lead = nil end
    if not entry.lead then
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if object:hasModData() and object:getModData().zedcommDoorLead == id then entry.lead = object end
        end
    end
    if not name then removeLead(entry); return end
    if not entry.lead then
        entry.lead = IsoObject.new(square, name, "ZedComm door lead")
        entry.lead:getModData().zedcommDoorLead = id
        square:AddTileObject(entry.lead)
    end
    local sprite = getSprite(name)
    if sprite and entry.lead:getSprite() ~= sprite then
        entry.lead:setSprite(sprite)
        entry.lead:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY)
    end
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
    local seen = {}
    for id, piece in pairs(network and network.pieces or {}) do
        local contact = ZedComm.DoorContact.profiles[piece.definitionId]
        if contact or piece.definitionId == ZedComm.InternalCircuit.DOOR_ID then
            local square = cell and cell:getGridSquare(piece.x, piece.y, piece.z)
            local object = findObject(square, id)
            local door = object
            if contact and object then door = ZedComm.DoorContact.host(object) end
            if door and (contact or ZedComm.Door.isEligible(door)) then
                local entry = entries[id]
                if entry and entry.door ~= door then setAttachment(entry, nil); removeLead(entry); entry = nil end
                entry = entry or { door = door, matches = contact and contactSprite or actuatorSprite }
                local isWindow = piece.definitionId == ZedComm.DoorContact.WINDOW_ID
                local reverse = not isWindow and ZedComm.Door.reverseHinge(door) and 1 or 0
                local name, floorName
                if contact then
                    local direction = directions[ZedComm.WireShape.portDirection(network, piece, "signal")] or 0
                    local frame = mountOf(door, piece) * 12 + reverse * 6 + direction
                    local framesPerFace = isWindow and 12 or 24
                    name = contact.prefix .. (mountOf(door, piece) * framesPerFace + reverse * 12
                        + (contact.isClosed(door) and 6 or 0) + direction)
                    if direction > 0 then floorName = "zedcomm_contact_floor_01_" .. frame end
                else
                    local frame = Visuals.frame(door, network, piece)
                    name = (reverse == 1 and "zedcomm_door_reverse_01_" or "zedcomm_door_01_") .. frame
                    if frame % 36 > 0 then
                        floorName = "zedcomm_door_floor_01_" .. (math.floor(frame / 72) * 72 + reverse * 36 + frame % 36)
                    end
                end
                if entry.name ~= name then setAttachment(entry, name); entry.name = name end
                syncLead(entry, square, id, floorName)
                seen[id] = entry
            end
        end
    end
    for id, entry in pairs(entries) do
        if not seen[id] then setAttachment(entry, nil); removeLead(entry) end
    end
    entries = seen
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
