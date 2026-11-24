-- Refresh cable and device visuals on topology changes or square loads.
if isClient() or isServer() then return end

require "ZedComm/WireShape"
require "ZedComm/ModuleVisuals"
require "ZedComm/DoorVisuals"
require "ZedComm/InternalCircuit"
require "ZedComm/Devices/RelayLamp"
require "ZedComm/Devices/NetworkSwitch"
local Shape = ZedComm.WireShape
local ModuleVisuals = ZedComm.ModuleVisuals
local Relay = ZedComm.RelayLamp
local Switch = ZedComm.NetworkSwitch
local Circuit = ZedComm.InternalCircuit
local leadDirections = { 0, 1, 2, 4, 8 }
local floorCabinetLeads = {
    [1] = "zedcomm_devices_01_4", [2] = "zedcomm_devices_01_5",
    [4] = "zedcomm_devices_01_7", [8] = "zedcomm_devices_01_10",
}
local plateSprites = {
    ["ZedComm.PressureSensor"] = { itemType = "ZedComm.PressurePlate", firstFrame = 20 },
    ["ZedComm.OccupancyPlate"] = { itemType = "ZedComm.OccupancyPlate", firstFrame = 419 },
    ["ZedComm.WeightPlate"] = { itemType = "ZedComm.WeightPlate", firstFrame = 425 },
}
local lastNetwork, lastVersion
local layoutNetwork, layoutVersion, cableSprites
local pendingSquares = {}
local missing = {}

local function currentNetwork()
    local registry = ZedComm.Registry and ZedComm.Registry.instance
    return registry and registry.network
end

local function setWorldSprite(object, name)
    if not name then return end
    local sprite = getSprite(name)
    if sprite then
        -- Use the registered tile so a sprite swap preserves FloorOverlay.
        if object:getSprite() ~= sprite then object:setSprite(sprite) end
    elseif not missing[name] then
        missing[name] = true
        print("[ZedComm] missing world sprite " .. name)
    end
end

local function spritesFor(network)
    if network ~= layoutNetwork or network.version ~= layoutVersion then
        cableSprites = Shape.layout(network)
        layoutNetwork, layoutVersion = network, network.version
    end
    return cableSprites
end

local function updateLead(square, lead, name, label, tag, marker)
    if lead then
        if name then
            setWorldSprite(lead, name)
        else
            square:transmitRemoveItemFromSquare(lead)
        end
    elseif name and getSprite(name) then
        lead = IsoObject.new(square, name, label)
        lead:setNoPicking(true)
        lead:getModData()[tag] = marker
        square:AddTileObject(lead)
    end
end

local function refreshCabinet(object, network, piece, mountType, leads)
    local mount = piece.state.mount
    local height = math.floor(object:getRenderYOffset() + 0.5)
    local wired = false
    for port in pairs(piece.ports) do
        local direction = Shape.portDirection(network, piece, port)
        if direction then
            wired = true
            if mountType == "wall" and mount then
                leads[direction] = Switch.floorLead(mount, direction)
            elseif mountType == "surface" then
                if height >= 1 and height <= 64 then
                    leads[direction] = "zedcomm_tabletop_leads_01_" .. ((height - 1) * 5 + Shape.portFrames[direction] - 1)
                end
            else
                leads[direction] = floorCabinetLeads[direction]
            end
        end
    end
    if mountType == "wall" then setWorldSprite(object, Circuit.wallCabinetSprite(mount, wired)) end
end

local function refreshSquare(square, network)
    if not square or not network then return end
    local sprites = spritesFor(network)
    local objects = square:getObjects()
    local endpoint, endpointIndex, changedOrder
    local switchLead, switchLeadObject
    local cabinetSprites, cabinetLeads = {}, {}
    local duplicates
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local data = object:hasModData() and object:getModData()
        if data and data.zedcommSwitchLead then switchLeadObject = object end
        local direction = data and data.zedcommCabinetLead
        if direction then
            if cabinetLeads[direction] then
                duplicates = duplicates or {}
                duplicates[#duplicates + 1] = object
            else
                cabinetLeads[direction] = object
            end
        end
        local tag = data and data.zedcomm
        if type(tag) == "table" then
            local piece = network.pieces[tag.id]
            if piece and piece.x == square:getX() and piece.y == square:getY() and piece.z == square:getZ() then
                local plate = plateSprites[piece.definitionId]
                local cabinet = Circuit.cabinets[piece.definitionId]
                if piece.kind == "cable" and tag.placedItem == "ZedComm.SignalWire" then
                    setWorldSprite(object, sprites[tag.id])
                    -- Build 42 draws floor overlays in square object order.
                    if endpoint then
                        objects:set(endpointIndex, object)
                        objects:set(i, endpoint)
                        endpointIndex, changedOrder = i, true
                    end
                elseif piece.definitionId == Relay.ID and tag.definitionId == Relay.ID then
                    ModuleVisuals.refresh(object, network, piece, "signal")
                elseif piece.definitionId == Switch.ID and tag.definitionId == Switch.ID then
                    Switch.updateSprite(object, piece.state, network, piece)
                    if piece.state then
                        switchLead = Switch.floorLead(piece.state.mount, Shape.portDirection(network, piece, "signal"))
                    end
                elseif cabinet and piece.definitionId == tag.definitionId then
                    refreshCabinet(object, network, piece, cabinet.mount, cabinetSprites)
                elseif plate and piece.definitionId == tag.definitionId
                    and tag.placedItem == plate.itemType then
                    local direction = Shape.portDirection(network, piece, "signal")
                    local frame = plate.firstFrame + (ZedComm.WireShape.portFrames[direction] or 0)
                    setWorldSprite(object, "zedcomm_devices_01_" .. frame)
                end
                if piece.kind == "endpoint" and piece.definitionId and piece.definitionId == tag.definitionId then
                    local sprite = object:getSprite()
                    local props = sprite and sprite:getProperties()
                    if props and props:has(IsoFlagType.FloorOverlay) then
                        endpoint, endpointIndex = object, i
                    end
                end
            end
        end
    end
    if changedOrder then endpoint:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_ADD) end
    updateLead(square, switchLeadObject, switchLead, "ZedComm switch lead", "zedcommSwitchLead", true)
    for _, direction in ipairs(leadDirections) do
        updateLead(square, cabinetLeads[direction], cabinetSprites[direction],
            "ZedComm cabinet lead", "zedcommCabinetLead", direction)
    end
    if duplicates then
        for _, duplicate in ipairs(duplicates) do square:transmitRemoveItemFromSquare(duplicate) end
    end
end

local function onTick()
    local network = currentNetwork()
    ZedComm.DoorVisuals.update(network, getCell())
    if not network then
        lastNetwork, lastVersion = nil, nil
        layoutNetwork, layoutVersion, cableSprites = nil, nil, nil
        pendingSquares = {}
        return
    end
    local cell = getCell()
    if not cell then return end
    local seen = pendingSquares
    pendingSquares = {}
    for square in pairs(seen) do refreshSquare(square, network) end
    if network == lastNetwork and network.version == lastVersion then return end
    for _, piece in pairs(network.pieces) do
        if piece.kind == "cable" or piece.definitionId == Relay.ID
            or piece.definitionId == Switch.ID or Circuit.cabinets[piece.definitionId] or plateSprites[piece.definitionId] then
            local square = cell:getGridSquare(piece.x, piece.y, piece.z)
            if square and not seen[square] then
                seen[square] = true
                refreshSquare(square, network)
            end
        end
    end
    lastNetwork, lastVersion = network, network.version
end

-- Wait for the registry to restore the endpoint after native placement or a square load.
Events.OnObjectAdded.Add(function(object)
    local square = object:getSquare()
    if not square then return end
    if object:hasModData() then
        local data = object:getModData()
        local marker = type(data.movableData) == "table" and data.movableData.zedcommRelay
        local tag = data.zedcomm
        if marker or (type(tag) == "table" and Circuit.cabinets[tag.definitionId]) then
            pendingSquares[square] = true
        end
    end
end)
Events.OnObjectAboutToBeRemoved.Add(function(object)
    if not object:hasModData() then return end
    local data = object:getModData()
    local tag = data.zedcomm
    if data.zedcommSwitchLead or data.zedcommCabinetLead
        or (type(tag) == "table" and (tag.definitionId == Switch.ID or Circuit.cabinets[tag.definitionId])) then
        local square = object:getSquare()
        if square then pendingSquares[square] = true end
    end
end)
Events.OnTick.Add(onTick)
Events.LoadGridsquare.Add(function(square) refreshSquare(square, currentNetwork()) end)
