-- Refresh cable and device visuals on topology changes or square loads.
if isClient() or isServer() then return end

require "ZedComm/WireShape"
require "ZedComm/ModuleVisuals"
require "ZedComm/Devices/RelayLamp"
require "ZedComm/Devices/NetworkSwitch"
local Shape = ZedComm.WireShape
local ModuleVisuals = ZedComm.ModuleVisuals
local Relay = ZedComm.RelayLamp
local Switch = ZedComm.NetworkSwitch
local pressureSensor = "ZedComm.PressureSensor"
local plateSprites = {
    [pressureSensor] = { itemType = "ZedComm.PressurePlate", firstFrame = 20 },
    ["ZedComm.OccupancyPlate"] = { itemType = "ZedComm.OccupancyPlate", firstFrame = 419 },
    ["ZedComm.WeightPlate"] = { itemType = "ZedComm.WeightPlate", firstFrame = 425 },
}
local plateFrameOffset = { [0] = 1, [1] = 2, [2] = 3, [4] = 4, [8] = 5 }
local lastNetwork, lastVersion
local layoutNetwork, layoutVersion, cableSprites
local pendingRelaySquares = {}
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

local function refreshSquare(square, network)
    if not square or not network then return end
    local sprites = spritesFor(network)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local tag = object:hasModData() and object:getModData().zedcomm
        if type(tag) == "table" then
            local piece = network.pieces[tag.id]
            if piece and piece.x == square:getX() and piece.y == square:getY() and piece.z == square:getZ() then
                local plate = plateSprites[piece.definitionId]
                if piece.kind == "cable" and (tag.placedItem == "ZedComm.SignalWire" or tag.useRouteSprite) then
                    setWorldSprite(object, sprites[tag.id])
                elseif piece.definitionId == Relay.ID and tag.definitionId == Relay.ID then
                    ModuleVisuals.refresh(object, network, piece, "signal")
                elseif piece.definitionId == Switch.ID and tag.definitionId == Switch.ID then
                    Switch.updateSprite(object, piece.state, network, piece)
                elseif plate and piece.definitionId == tag.definitionId
                    and (tag.placedItem == plate.itemType or (piece.definitionId == pressureSensor and tag.spikeWire)) then
                    local direction = Shape.portDirection(network, piece, "signal")
                    local frame = plate.firstFrame + (plateFrameOffset[direction] or 0)
                    setWorldSprite(object, "zedcomm_devices_01_" .. frame)
                end
            end
        end
    end
end

local function onTick()
    local network = currentNetwork()
    if not network then
        lastNetwork, lastVersion = nil, nil
        layoutNetwork, layoutVersion, cableSprites = nil, nil, nil
        pendingRelaySquares = {}
        return
    end
    local cell = getCell()
    if not cell then return end
    local seen = pendingRelaySquares
    pendingRelaySquares = {}
    for square in pairs(seen) do refreshSquare(square, network) end
    if network == lastNetwork and network.version == lastVersion then return end
    for _, piece in pairs(network.pieces) do
        if piece.kind == "cable" or piece.definitionId == Relay.ID
            or piece.definitionId == Switch.ID or plateSprites[piece.definitionId] then
            local square = cell:getGridSquare(piece.x, piece.y, piece.z)
            if square and not seen[square] then
                seen[square] = true
                refreshSquare(square, network)
            end
        end
    end
    lastNetwork, lastVersion = network, network.version
end

-- Native placement restores movableData before OnObjectAdded. Wait until
-- the registry has had a chance to restore the relay tag and endpoint.
Events.OnObjectAdded.Add(function(object)
    if not object:hasModData() then return end
    local data = object:getModData()
    local marker = type(data.movableData) == "table" and data.movableData.zedcommRelay
    local square = marker and object:getSquare()
    if square then pendingRelaySquares[square] = true end
end)
Events.OnTick.Add(onTick)
Events.LoadGridsquare.Add(function(square) refreshSquare(square, currentNetwork()) end)
