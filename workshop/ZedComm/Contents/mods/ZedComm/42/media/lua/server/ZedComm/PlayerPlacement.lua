-- Singleplayer inventory actions backed by the saved registry.
if isClient() or isServer() then return end

require "ZedComm/Network"
require "ZedComm/NativeDevices"
require "ZedComm/DoorInstallation"

local Parts = require "ZedComm/CircuitParts"
local Placement = {}
local Network = ZedComm.Network
local definitions = ZedComm.DeviceDefinitions
local Relay = ZedComm.RelayLamp
local Circuit = ZedComm.InternalCircuit
local Switch = ZedComm.NetworkSwitch
local Sensors = ZedComm.EnvironmentalSensors
local serial = 0
local items = {
    { itemType = "ZedComm.PressurePlate", name = "pressure plate", sprite = "zedcomm_devices_01_20",
        kind = "endpoint", definitionId = "ZedComm.PressureSensor", fixtureType = "Plate" },
    { itemType = "ZedComm.SignalWire", name = "wire", sprite = "zedcomm_devices_01_1", kind = "cable" },
    { itemType = "ZedComm.NumericDisplay", name = "numeric display", sprite = "zedcomm_devices_01_431",
        kind = "endpoint", definitionId = "ZedComm.NumericDisplay", fixtureType = "Display", supportsSurface = true },
    { itemType = "ZedComm.AdvancedDisplay", name = "advanced display", sprite = "zedcomm_devices_01_431",
        kind = "endpoint", definitionId = "ZedComm.AdvancedDisplay", fixtureType = "Display", supportsSurface = true },
    { itemType = "ZedComm.OccupancyPlate", name = "occupancy plate", sprite = "zedcomm_devices_01_419",
        kind = "endpoint", definitionId = "ZedComm.OccupancyPlate", fixtureType = "Plate" },
    { itemType = "ZedComm.IRSensor", name = "IR proximity sensor", sprite = "zedcomm_ir_01_0",
        kind = "endpoint", definitionId = "ZedComm.IRSensor", fixtureType = "IR sensor" },
    { itemType = "ZedComm.WeightPlate", name = "weight plate", sprite = "zedcomm_devices_01_425",
        kind = "endpoint", definitionId = "ZedComm.WeightPlate", fixtureType = "Plate" },
    { itemType = "ZedComm.DebugByteSource", name = "test byte source", sprite = "zedcomm_devices_01_431",
        kind = "endpoint", definitionId = "ZedComm.DebugByteSource", fixtureType = "Source", supportsSurface = true },
    { itemType = Switch.ID, name = "network switch", sprite = Switch.OFF_NORTH,
        kind = "endpoint", definitionId = Switch.ID, fixtureType = "Switch", mount = "wall" },
    { itemType = Sensors.CLOCK, name = "time-of-day sensor", sprite = "zedcomm_devices_01_431",
        kind = "endpoint", definitionId = Sensors.CLOCK, fixtureType = "Clock" },
    { itemType = Sensors.POWER, name = "power sensor", sprite = "zedcomm_devices_01_431",
        kind = "endpoint", definitionId = Sensors.POWER, fixtureType = "Power Sensor" },
    { itemType = Sensors.DAYLIGHT, name = "daylight sensor", sprite = "zedcomm_devices_01_431",
        kind = "endpoint", definitionId = Sensors.DAYLIGHT, fixtureType = "Daylight Sensor" },
    { itemType = Sensors.RAIN, name = "rain intensity sensor", sprite = "zedcomm_devices_01_431",
        kind = "endpoint", definitionId = Sensors.RAIN, fixtureType = "Rain Sensor" },
}
local relaySpec = { name = "relay lamp", kind = "endpoint", definitionId = Relay.ID, nativePickup = true,
    fixtureType = "Lamp" }
local Door, Contact = ZedComm.Door, ZedComm.DoorContact
local Sensors = ZedComm.ContainerSensors
local contactSpecs = {}
for id, profile in pairs(Contact.profiles) do
    contactSpecs[id] = { name = profile.name:lower(), kind = "endpoint", definitionId = id,
        nativePickup = true, fixtureType = profile.name }
end
local doorSpec = { name = "networked door", kind = "endpoint", definitionId = Circuit.DOOR_ID,
    nativePickup = true, fixtureType = "Door" }
Placement.WIRE_TYPE = items[2].itemType

local specs, cabinetSpecs = {}, {}
for _, spec in ipairs(items) do specs[spec.itemType] = spec end
for id, profile in pairs(Circuit.cabinets) do
    local advancedItem = "ZedComm.Advanced" .. id:sub(#"ZedComm." + 1)
    local variants = {}
    for tier, itemType in pairs({ basic = id, advanced = advancedItem }) do
        local spec = { itemType = itemType, name = tier .. " " .. profile.name:lower(), sprite = profile.sprite,
            kind = "endpoint", definitionId = id, adapter = tier, fixtureType = "Cabinet", mount = profile.mount }
        specs[itemType], variants[tier] = spec, spec
    end
    cabinetSpecs[id] = variants
end

local function specFor(itemType) return specs[itemType] end

function Placement.getSpec(itemType)
    return specFor(itemType)
end

function Placement.isWallItem(itemType)
    local spec = specFor(itemType)
    return spec and spec.mount == "wall"
end

function Placement.wallMount(square, item, preferred)
    local saved = item:getModData().zedcommPlacement
    local state = type(saved) == "table" and saved.state
    return Switch.mount(square, preferred or (type(state) == "table" and state.mount))
end

function Placement.surfaceOffset(square, itemType)
    local spec = specFor(itemType)
    if not spec or (spec.mount ~= "surface" and not spec.supportsSurface) or not square or not ISMoveableSpriteProps
        or square:has("IsTableTop") then return nil end
    local height = ISMoveableSpriteProps:getTotalTableHeight(square)
    if height > 0 and height <= 64 then return height end
end

function Placement.previewSprite(square, item, mount)
    local spec = specFor(item:getFullType())
    if not spec then return nil end
    if spec.mount ~= "wall" or not square then return spec.sprite end
    local facing = Placement.wallMount(square, item, mount)
    if spec.definitionId ~= Switch.ID then
        return Circuit.wallCabinetSprite(facing) or spec.sprite
    end
    local saved = item:getModData().zedcommPlacement
    local state = type(saved) == "table" and saved.state
    return Switch.sprite(facing, type(state) == "table" and state.on == true)
end

function Placement.getRegistry()
    local registry = ZedComm.Registry
    return registry and registry.instance
end

require "ZedComm/DeviceDefinitions"
local tagOf = ZedComm.DeviceDefinitions.readFixtureTag

local cardinalOffsets = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function distance(first, second)
    if first:getZ() ~= second:getZ() then return 2 end
    return math.abs(first:getX() - second:getX()) + math.abs(first:getY() - second:getY())
end

local function loadedSquare(square)
    local cell = getCell()
    return cell and square and cell:getGridSquare(square:getX(), square:getY(), square:getZ()) == square
end

local function clearBetween(first, second)
    return first == second or (not first:isBlockedTo(second) and not second:isBlockedTo(first))
end

local function edgeFixture(object)
    if Door.isEligible(object) or (object and instanceof(object, "IsoWindow")) then return object end
    if object then return Contact.host(object, true) end
end

function Placement.oppositeFace(square, object)
    local fixture = edgeFixture(object)
    if fixture and fixture:getSquare() == square then return Door.oppositeSquare(fixture) end
end

local function canReachFrom(from, square, opposite)
    return from ~= nil and (from == opposite or (distance(from, square) <= 1 and clearBetween(from, square)))
end

function Placement.canReach(character, square, object)
    return loadedSquare(square)
        and canReachFrom(character:getCurrentSquare(), square, Placement.oppositeFace(square, object))
end

local function withinView(from, square)
    local steps = distance(from, square)
    if steps <= 1 then return clearBetween(from, square) end
    if steps ~= 2 then return false end
    local cell = getCell()
    for _, step in ipairs(cardinalOffsets) do
        local middle = cell:getGridSquare(from:getX() + step[1], from:getY() + step[2], from:getZ())
        if middle and distance(middle, square) == 1 and clearBetween(from, middle)
            and clearBetween(middle, square) then return true end
    end
    return false
end

function Placement.canView(character, square, object)
    local from = character:getCurrentSquare()
    if not loadedSquare(square) or not from then return false end
    if withinView(from, square) then return true end
    local opposite = Placement.oppositeFace(square, object)
    return opposite ~= nil and withinView(from, opposite)
end

function Placement.approachLocations(square, object, adjacentOnly, anchor)
    local locations = {}
    if not loadedSquare(square) then return locations end
    local cell = getCell()
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local opposite = Placement.oppositeFace(square, object)
    local anchorFace = anchor and Placement.oppositeFace(anchor.square, anchor.object)
    local function add(candidate)
        if not candidate or not candidate:canStand() or not canReachFrom(candidate, square, opposite) then return end
        if anchor and not canReachFrom(candidate, anchor.square, anchorFace) then return end
        locations[#locations + 1] = candidate:getX() + 0.5
        locations[#locations + 1] = candidate:getY() + 0.5
        locations[#locations + 1] = candidate:getZ()
    end
    if not adjacentOnly then add(square) end
    for _, step in ipairs(cardinalOffsets) do
        add(cell:getGridSquare(x + step[1], y + step[2], z))
    end
    return locations
end

local function squareObjects(square)
    local out = {}
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do out[#out + 1] = objects:get(i) end
    return out
end

local function onSquare(object, square)
    if not loadedSquare(square) or object:getSquare() ~= square then return false end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if objects:get(i) == object then return true end
    end
    return false
end

function Placement.relayCandidates(square)
    local out = {}
    for _, object in ipairs(squareObjects(square)) do
        if Relay.isEligible(object) and object:getModData().zedcomm == nil then out[#out + 1] = object end
    end
    return out
end

local function visitFaceOwners(square, visit)
    local cell = getCell()
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local east = cell:getGridSquare(x + 1, y, z)
    local south = cell:getGridSquare(x, y + 1, z)
    if east then visit(east) end
    if south then visit(south) end
end

local function fixtureCandidates(square, matches)
    local out = {}
    for _, object in ipairs(squareObjects(square)) do
        if matches(object) then out[#out + 1] = object end
    end
    visitFaceOwners(square, function(owner)
        for _, object in ipairs(squareObjects(owner)) do
            if matches(object) and Door.oppositeSquare(object) == square then out[#out + 1] = object end
        end
    end)
    return out
end

function Placement.doorCandidates(square)
    return fixtureCandidates(square, Door.isEligible)
end

function Placement.windowContactCandidates(square)
    return fixtureCandidates(square, function(object) return Contact.canFit(object, Contact.WINDOW_ID) end)
end

function Placement.containerSensorCandidates(square, definitionId)
    local out = {}
    for _, object in ipairs(squareObjects(square)) do
        if Contact.canFit(object, definitionId) then out[#out + 1] = object end
    end
    return out
end

local function collectPieces(registry, square, out, face)
    for _, object in ipairs(squareObjects(square)) do
        local tag = tagOf(object)
        local spec = tag and (specFor(tag.placedItem) or (tag.definitionId == Relay.ID and relaySpec)
            or (tag.definitionId == Circuit.DOOR_ID and doorSpec)
            or contactSpecs[tag.definitionId])
        local piece = spec and registry.network.pieces[tag.id]
        if piece and piece.kind == spec.kind and piece.definitionId == spec.definitionId
            and piece.x == square:getX() and piece.y == square:getY() and piece.z == square:getZ()
            and (not face or Placement.oppositeFace(square, object) == face) then
            local variants = cabinetSpecs[piece.definitionId]
            if variants then spec = variants[piece.state.adapter] or variants.basic end
            out[#out + 1] = { id = piece.id, piece = piece, object = object, square = square, spec = spec }
        end
    end
end

function Placement.piecesAt(registry, square)
    local out = {}
    collectPieces(registry, square, out)
    return out
end

function Placement.targetsAt(registry, square)
    local targets = Placement.piecesAt(registry, square)
    visitFaceOwners(square, function(owner)
        collectPieces(registry, owner, targets, square)
    end)
    return targets
end

function Placement.resolve(registry, id)
    local piece = id and registry.network.pieces[id]
    local cell = getCell()
    local square = piece and cell and cell:getGridSquare(piece.x, piece.y, piece.z)
    if not square then return nil end
    for _, entry in ipairs(Placement.piecesAt(registry, square)) do
        if entry.id == id then return entry end
    end
end

function Placement.freePorts(entry, character)
    local piece = entry.piece
    local out = {}
    if piece.kind == "cable" then
        local count = 0
        for _ in pairs(piece.links) do count = count + 1 end
        if count < Network.MAX_CABLE_LINKS then out[1] = false end
    elseif not piece.definitionUnavailable and Circuit.canService(piece, character) then
        for name, link in pairs(piece.ports) do
            if link == false then out[#out + 1] = name end
        end
        table.sort(out)
    end
    return out
end

function Placement.hasFreeEnd(entry, port, character)
    if not entry then return false end
    for _, candidate in ipairs(Placement.freePorts(entry, character)) do
        if port == candidate then return true end
    end
    return false
end

local function linkDistance(first, second, secondKind, secondObject)
    local steps = distance(first.square, second)
    if first.piece.kind == "cable" and secondKind == "cable" then
        return steps == 1 and clearBetween(first.square, second)
    end
    if steps > 1 then return false end
    return clearBetween(first.square, second) or second == Placement.oppositeFace(first.square, first.object)
        or first.square == Placement.oppositeFace(second, secondObject)
end

local function compatibleEnds(network, first, firstPort, second, secondPort, character)
    if not Placement.hasFreeEnd(first, firstPort, character) or not Placement.hasFreeEnd(second, secondPort, character)
        or first.id == second.id then return false end
    local a, b = first.piece.kind, second.piece.kind
    if a ~= "cable" and b ~= "cable" then return false end
    -- Free ends on the same chain cannot be joined into a loop.
    local firstNet = network:networkOf(first.id, firstPort or nil)
    local secondNet = network:networkOf(second.id, secondPort or nil)
    if firstNet == secondNet then return false end
    return #network.nets[firstNet].sources == 0 or #network.nets[secondNet].sources == 0
end

function Placement.canJoin(network, first, firstPort, second, secondPort, character)
    return first ~= nil and second ~= nil
        and linkDistance(first, second.square, second.piece.kind, second.object)
        and compatibleEnds(network, first, firstPort, second, secondPort, character)
end

local function link(registry, first, firstPort, second, secondPort)
    if first.piece.kind == "cable" then
        return registry:link(first.id, second.id, secondPort or nil)
    end
    return registry:link(second.id, first.id, firstPort or nil)
end

local function tileAvailable(square, spec)
    local height = Placement.surfaceOffset(square, spec.itemType)
    if spec.mount == "surface" and not height then
        return false, "Choose an empty table or countertop."
    end
    if not square:TreatAsSolidFloor() or (not height and (square:isSolid() or square:isSolidTrans())) then
        return false, "Choose a clear floor tile."
    end
    if spec.mount == "wall" and not Switch.mount(square) then
        return false, "Choose a tile next to an eligible wall."
    end
    if spec.kind == "endpoint" then
        for _, object in ipairs(squareObjects(square)) do
            local tag = tagOf(object)
            if tag and tag.kind == "endpoint" then return false, "There is already a device here." end
        end
    end
    return true, nil, height
end

function Placement.canPlace(square, itemType)
    local spec = specFor(itemType)
    return spec ~= nil and loadedSquare(square) and tileAvailable(square, spec)
end

local function canExtend(entry, port, square, character)
    return square ~= nil and Placement.hasFreeEnd(entry, port, character) and linkDistance(entry, square, "cable")
end

function Placement.canLay(entry, port, square, character)
    return canExtend(entry, port, square, character) and tileAvailable(square, items[2])
end

local function retainedState(item, spec)
    if not spec.definitionId then return nil end
    local saved = item:getModData().zedcommPlacement
    if type(saved) == "table" then return saved end
end

local function chooseId(registry, square, retained)
    if retained and type(retained.id) == "string" then
        if registry.network.pieces[retained.id] then return nil end
        return retained.id
    end
    local id
    repeat
        serial = serial + 1
        id = "placed-" .. square:getX() .. "," .. square:getY() .. "," .. square:getZ()
            .. "-" .. getTimestampMs() .. "-" .. serial
    until not registry.network.pieces[id]
    return id
end

local function removeWorldPiece(registry, entry)
    entry.square:transmitRemoveItemFromSquare(entry.object)
    if onSquare(entry.object, entry.square) then return false end
    -- The vanilla removal hook normally detaches it. Cover both paths.
    if registry.network.pieces[entry.id] then registry:removePiece(entry.id) end
    return true
end

function Placement.carries(character, item)
    local inventory = character:getInventory()
    return item ~= nil and item:getContainer() == inventory and inventory:contains(item)
end

local function place(registry, character, square, item, anchor, anchorPort, laying, mount, throughWall)
    local inventory = character:getInventory()
    local spec = item and specFor(item:getFullType())
    if not spec or not Placement.carries(character, item) then
        return false, "That item is no longer in your main inventory."
    end
    if laying and spec.kind ~= "cable" then return false, "Choose a wire to extend this run." end
    local valid, why, height = tileAvailable(square, spec)
    if not valid then return false, why end
    if laying and anchor and not Circuit.canService(anchor.piece, character) then return false, "The board is padlocked." end
    if laying and not throughWall and not canExtend(anchor, anchorPort, square, character) then
        return false, "Select a free end on this tile or a neighboring tile."
    end
    if spec.mount == "wall" then
        local facing = Placement.wallMount(square, item, mount)
        if mount and mount ~= facing then return false, "That wall is no longer available." end
        mount = facing
    end
    local sprite = Placement.previewSprite(square, item, mount)
    if not getSprite(sprite) then return false, "The ZedComm sprite is missing." end
    if spec.definitionId and not cabinetSpecs[spec.definitionId] and not definitions.get(spec.definitionId) then
        return false, "The device definition is missing."
    end
    local retained = retainedState(item, spec)
    local id = chooseId(registry, square, retained)
    if not id then return false, "A device with this identity is already placed." end

    local object = IsoObject.new(square, sprite, item:getName())
    if height then object:setRenderYOffset(height) end
    local state = retained and retained.state
    if spec.adapter then
        local cabinetState = {}
        for key, value in pairs(state or {}) do cabinetState[key] = value end
        cabinetState.circuit = cabinetState.circuit or { modules = {}, links = {} }
        cabinetState.adapter, cabinetState.mount = spec.adapter, mount
        state = cabinetState
    end
    if spec.definitionId == Switch.ID then
        state = { on = type(state) == "table" and state.on == true, mount = mount,
            fixtureName = state and state.fixtureName }
    end
    object:getModData().zedcomm = {
        id = id, kind = spec.kind, definitionId = spec.definitionId, placedItem = spec.itemType,
        state = state,
    }
    local entry = { id = id, object = object, square = square }
    local ok, err = pcall(function()
        square:AddTileObject(object)
        if not onSquare(object, square) then error("Could not place the object.") end
        triggerEvent("OnObjectAdded", object)
        entry.piece = registry.network.pieces[id]
        if not entry.piece then error("Could not register the object.") end
        if laying then
            local connected, reason = link(registry, anchor, anchorPort, entry, false)
            if not connected then error(reason) end
        end
    end)
    if not ok then
        if onSquare(object, square) and not removeWorldPiece(registry, entry) then
            return false, "Placement failed and the object could not be removed: " .. tostring(err)
        end
        return false, tostring(err)
    end
    inventory:Remove(item)
    return true, id
end

function Placement.canPickUp(registry, entry, character)
    if entry.spec.nativePickup then return false, "Use the normal moveable pickup for this lamp." end
    if Circuit.padlockId(entry.piece) then return false, "Remove the padlock first." end
    if entry.piece.kind == "cable" then
        for id in pairs(entry.piece.links) do
            local piece = registry.network.pieces[id]
            if not Circuit.canService(piece, character) then
                return false, "The wire is connected to a padlocked board."
            end
        end
    end
    return true
end

local function pickUp(registry, character, entry)
    local allowed, reason = Placement.canPickUp(registry, entry, character)
    if not allowed then return false, reason end
    local record = registry.network:record(entry.id)
    local inventory = character:getInventory()
    local item = instanceItem(entry.spec.itemType)
    if not item or not inventory:hasRoomFor(character, item) then
        return false, "There is no room in your main inventory."
    end
    if record.kind == "endpoint" then
        item:getModData().zedcommPlacement = { id = record.id, state = record.state }
    end
    inventory:AddItem(item)
    local ok, removed = pcall(removeWorldPiece, registry, entry)
    if not ok or not removed then
        if onSquare(entry.object, entry.square) then
            inventory:Remove(item)
            return false, "Could not pick up the object."
        end
        -- If a removal callback threw after the tile changed, keep the item
        -- and reconcile any remaining registry entry.
        if registry.network.pieces[entry.id] then registry:removePiece(entry.id) end
    end
    return true
end

function Placement.canFitLampAdapter(character, advanced)
    local required = advanced and 3 or 1
    if character:getPerkLevel(Perks.Electricity) < required then
        return false, "Requires Electrical " .. required
    end
    return true
end

local function fitLampAdapter(registry, square, lamp, character, item)
    if not Relay.isEligible(lamp) or not onSquare(lamp, square) then
        return false, "Choose a placed, modifiable lamp."
    end
    local inventory = character:getInventory()
    local itemType = item and item:getFullType()
    local advanced = itemType == Circuit.ADVANCED_ADAPTER_ITEM
    if (not advanced and itemType ~= Circuit.BASIC_ADAPTER_ITEM)
        or not Placement.carries(character, item) then
        return false, "Bring the matching adapter in your main inventory."
    end
    local skilled, reason = Placement.canFitLampAdapter(character, advanced)
    if not skilled then return false, reason .. "." end
    local data = lamp:getModData()
    if data.zedcomm ~= nil then return false, "This fixture already has a ZedComm device." end
    for _, object in ipairs(squareObjects(square)) do
        local tag = tagOf(object)
        if tag and tag.kind == "endpoint" then return false, "There is already a device on this tile." end
    end

    local id = chooseId(registry, square)
    local state = { adapter = advanced and "advanced" or "basic", module = { id = Relay.MODULE, config = {} } }
    if advanced then state.circuit = { modules = {}, links = {} } end
    inventory:Remove(item)
    data.zedcomm = { id = id, kind = "endpoint", definitionId = Relay.ID, state = state }
    local called, ok, failure = pcall(registry.addPiece, registry, lamp)
    if not called or not ok then
        if registry.network.pieces[id] then registry:removePiece(id) end
        data.zedcomm = nil
        inventory:AddItem(item)
        return false, called and failure or tostring(ok)
    end
    Relay.writeInstallation(data, id, state)
    return true, id
end

local function removeLampAdapter(character, registry, entry)
    local state = entry.piece.state
    local inventory = character:getInventory()
    local recovered = Parts.recover(character, state, state.adapter and 1 or 0)
    if not recovered then return false, "There is no room for the adapter and modules." end

    local ok, reason = registry:removePiece(entry.id)
    if not ok then
        Parts.discard(inventory, recovered)
        return false, reason
    end
    local data = entry.object:getModData()
    data.zedcomm = nil
    if type(data.movableData) == "table" then data.movableData.zedcommRelay = nil end
    ZedComm.DeviceRuntime.releaseLamp(entry.id)
    if ZedComm.ModuleVisuals then ZedComm.ModuleVisuals.clear(entry.object) end
    return true
end

local function changePadlock(registry, character, command, entry)
    local piece = entry.piece
    if not Circuit.canPadlock(piece) then return false, "That board cannot be padlocked." end
    local inventory = character:getInventory()
    local lockedKey = Circuit.padlockId(piece)
    local item, replacementType, replacementCount, keyId, owner
    if command.kind == "fit-padlock" then
        if lockedKey then return false, "The board is already padlocked." end
        item = command.item
        if not Placement.carries(character, item) or item:getFullType() ~= "Base.Padlock" then
            return false, "Bring a padlock in your main inventory."
        end
        keyId = item:getKeyId()
        replacementType, replacementCount = "Base.KeyPadlock", item:getNumberOfKey()
        if command.remember then
            owner = character:getModData().zedcommPadlockIdentity or getRandomUUID()
        else
            replacementCount = math.max(1, replacementCount)
        end
    else
        if lockedKey == nil or lockedKey ~= command.keyId then return false, "The padlock changed." end
        if not Circuit.remembersPlayer(piece, character) then
            item = inventory:haveThisKeyId(lockedKey)
            if not item then return false, "Bring the matching padlock key." end
        end
        keyId = lockedKey
        replacementType, replacementCount = "Base.Padlock", 1
    end
    local replacements = {}
    for i = 1, replacementCount do
        local replacement = instanceItem(replacementType)
        if not replacement then return false, "Could not create the padlock or its key." end
        replacement:setKeyId(keyId)
        -- A keyless removal leaves the existing keys intact.
        if lockedKey then replacement:setNumberOfKey(item and 1 or 0) end
        replacements[i] = replacement
    end
    local container = item and item:getContainer()
    if container then container:Remove(item) end
    local added = 0
    local ok, reason = false, nil
    for _, replacement in ipairs(replacements) do
        if not inventory:hasRoomFor(character, replacement) then
            reason = "There is no room for the padlock or its keys."
            break
        end
        inventory:AddItem(replacement)
        added = added + 1
    end
    if not reason then
        ok, reason = registry:setPadlock(entry.id, not lockedKey and keyId or nil, owner)
    end
    if ok then
        if owner then character:getModData().zedcommPadlockIdentity = owner end
    else
        for i = 1, added do inventory:Remove(replacements[i]) end
        if container then container:AddItem(item) end
    end
    return ok, reason
end

function Placement.canUpgradeCabinet(character, entry, adapter)
    if not entry or not cabinetSpecs[entry.piece.definitionId] then return false, "That cabinet is no longer available." end
    if Circuit.padlockId(entry.piece) then return false, "Remove the cabinet padlock first." end
    if entry.spec.adapter ~= "basic" then return false, "This cabinet already has an Advanced Adapter." end
    local inventory = character:getInventory()
    if not adapter or adapter:getFullType() ~= Circuit.ADVANCED_ADAPTER_ITEM
        or adapter:getContainer() ~= inventory or not inventory:contains(adapter) then
        return false, "Bring an Advanced Adapter in your main inventory."
    end
    return true
end

local function upgradeCabinet(registry, character, entry, adapter)
    local valid, reason = Placement.canUpgradeCabinet(character, entry, adapter)
    if not valid then return false, reason end
    local inventory = character:getInventory()
    local recovered = instanceItem(Circuit.BASIC_ADAPTER_ITEM)
    if not recovered then return false, "Could not recover the Basic Adapter." end
    -- Taking the Advanced Adapter out first frees its weight for the swap.
    inventory:Remove(adapter)
    if not inventory:hasRoomFor(character, recovered) then
        inventory:AddItem(adapter)
        return false, "There is no room for the recovered Basic Adapter."
    end
    inventory:AddItem(recovered)

    local state = registry.network:record(entry.id).state
    state.adapter = "advanced"
    local ok, reason = registry:setDeviceState(entry.id, state)
    if ok then return true end
    inventory:Remove(recovered)
    inventory:AddItem(adapter)
    return false, reason
end

-- Apply an edit only to the exact host and circuit the editor opened.
function Placement.editCircuit(character, registry, target, expected, layout, install, remove)
    local entry = Placement.getRegistry() == registry and Placement.resolve(registry, target.id)
    if not entry or entry.object ~= target.object or not Placement.canReach(character, entry.square, entry.object) then
        return false, "That device is no longer within reach."
    end
    if not Circuit.canService(entry.piece, character) then return false, "The board is padlocked." end
    local state = entry.piece.state
    local cabinet = Circuit.profileFor(entry.piece.definitionId)
    if (not cabinet and entry.piece.definitionId ~= Relay.ID) or not state
        or type(expected) ~= "table" or state.circuit ~= expected then
        return false, "The circuit changed. Reopen the editor."
    end
    local valid, errorMessage = Circuit.validate(layout, cabinet, cabinet and state.adapter or nil)
    if not valid then return false, errorMessage end
    local added, removed, addedPart, removedPart = 0, 0
    for id, part in pairs(layout.modules) do
        local previous = expected.modules[id]
        if not previous then
            added, addedPart = added + 1, part
        elseif previous.kind ~= part.kind then
            return false, "An installed module cannot change type."
        end
    end
    for id, part in pairs(expected.modules) do
        if not layout.modules[id] then removed, removedPart = removed + 1, part end
    end
    if (install and remove) or added ~= (install and 1 or 0) or removed ~= (remove and 1 or 0) then
        return false, "The module inventory does not match this edit."
    end

    local inventory = character:getInventory()
    local recovered
    if install then
        if install:getFullType() ~= Circuit.kinds[addedPart.kind].item
            or install:getContainer() ~= inventory or not inventory:contains(install) then
            return false, "The module is no longer in your main inventory."
        end
        if addedPart.kind == "batterySource" and addedPart.charge ~= install:getModData().zedcommCharge then
            return false, "The battery source changed. Pick it up again."
        end
        inventory:Remove(install)
    elseif remove then
        recovered = instanceItem(Circuit.kinds[removedPart.kind].item)
        if not recovered or not inventory:hasRoomFor(character, recovered) then
            return false, "There is no room for the module."
        end
        if removedPart.kind == "batterySource" then
            recovered:getModData().zedcommCharge = removedPart.charge
        end
        if Circuit.kinds[removedPart.kind].source then
            recovered:getModData().zedcommSourceLevel = removedPart.level
        end
        inventory:AddItem(recovered)
    end

    local ok, reason
    if cabinet then
        local copy = registry.network:record(entry.id).state
        copy.circuit = layout
        ok, reason = registry:setDeviceState(entry.id, copy)
    else
        ok, reason = ZedComm.DeviceRuntime.setLampCircuit(registry, entry.id, layout)
    end
    if not ok then
        if install then inventory:AddItem(install) end
        if recovered then inventory:Remove(recovered) end
    end
    return ok, reason
end

function Placement.changeCircuitBattery(character, registry, target, expected, id)
    local entry = Placement.getRegistry() == registry and Placement.resolve(registry, target.id)
    if not entry or entry.object ~= target.object or not Placement.canReach(character, entry.square, entry.object)
        or not entry.piece.state or entry.piece.state.circuit ~= expected then
        return false, "The circuit changed or is out of reach."
    end
    if not Circuit.canService(entry.piece, character) then return false, "The board is padlocked." end
    local layout = registry.network:record(target.id).state.circuit
    local part = layout.modules[id]
    if not part or part.kind ~= "batterySource" then return false, "Select a Battery Source." end

    local inventory = character:getInventory()
    local battery, taken
    if part.charge ~= nil then
        battery = instanceItem("Base.Battery")
        if not battery or not inventory:hasRoomFor(character, battery) then
            return false, "There is no room for the battery."
        end
        battery:setUsedDelta(part.charge)
        inventory:AddItem(battery)
        part.charge = nil
    else
        local items = inventory:getItems()
        for i = 0, items:size() - 1 do
            local candidate = items:get(i)
            if candidate:getFullType() == "Base.Battery" and candidate:getCurrentUsesFloat() > 0 then
                battery = candidate
                break
            end
        end
        if not battery then return false, "Bring a charged battery in your main inventory." end
        part.charge = battery:getCurrentUsesFloat()
        inventory:Remove(battery)
        taken = true
    end

    local ok, reason = Placement.editCircuit(character, registry, target, expected, layout)
    if not ok then
        if taken then inventory:AddItem(battery) else inventory:Remove(battery) end
        return false, reason
    end
    return true, taken and "Battery installed." or "Battery removed."
end

local function relayTarget(target)
    return target.piece.definitionId == Relay.ID
end

local function boardTarget(target)
    return target.piece.board ~= nil
end

local function switchTarget(target)
    return target.piece.definitionId == Switch.ID
end

local function setNetworkSwitch(registry, target, on)
    local state = registry.network:record(target.id).state or { mount = Switch.mount(target.square) }
    if on == nil then on = not state.on end
    state.on = on
    return registry:setDeviceState(target.id, state)
end

local wireRunMessages = {
    cursor = "Wire laid.",
    menu = "Wire laid. Select the next tile or a free end.",
}

local function contactInstallation(contactId, message)
    local profile = Contact.profiles[contactId]
    return {
        duration = 120,
        message = message,
        validate = function(character, command)
            return Contact.canFit(command.object, contactId) and command.object:getSquare() == command.square
                and ZedComm.DoorInstallation.contactMaterials(character, contactId) ~= nil
                and (not profile.installState or profile.installState(command.object, command.compartment) ~= nil)
        end,
        execute = function(registry, character, command)
            if not onSquare(command.object, command.square) then
                return false, "That fixture is no longer on the tile."
            end
            return ZedComm.DoorInstallation.installContact(character, registry, command.object,
                chooseId(registry, command.square), contactId, command.compartment)
        end,
    }
end

local wallEdges = {
    { name = "north", dx = 0, dy = -1, north = true },
    { name = "west", dx = -1, dy = 0, north = false },
    { name = "south", dx = 0, dy = 1, north = true },
    { name = "east", dx = 1, dy = 0, north = false },
}
Placement.wallCoverItems = { plastic = "Base.PlasticTray", metal = "Base.ScrapMetal" }
Placement.WALL_PASSTHROUGH_LIMIT = 5

local function wallPassthrough(square, edge)
    local other = getCell():getGridSquare(square:getX() + edge.dx, square:getY() + edge.dy, square:getZ())
    if not loadedSquare(other) or clearBetween(square, other) then return nil end
    local owner = (edge.dx > 0 or edge.dy > 0) and other or square
    local wall = owner:getWall(edge.north)
    if not wall or owner:getDoorOrWindow(edge.north) or square:getWindowFrameTo(other)
        or square:getHoppableTo(other) then return nil end
    local key = edge.north and "north" or "west"
    local data = wall:hasModData() and wall:getModData().zedcommWallPassthrough
    return { wall = wall, key = key, square = square, other = other, side = edge.name, cover = data and data[key] }
end

function Placement.wallPassthroughs(square)
    local walls = {}
    for _, edge in ipairs(wallEdges) do
        local passage = wallPassthrough(square, edge)
        if passage then walls[#walls + 1] = passage end
    end
    return walls
end

function Placement.wallCrossings(registry, square, other)
    local count = 0
    for _, entry in ipairs(Placement.piecesAt(registry, square)) do
        if entry.piece.kind == "cable" then
            for id in pairs(entry.piece.links) do
                local piece = registry.network.pieces[id]
                if piece.kind == "cable" and piece.x == other:getX() and piece.y == other:getY()
                    and piece.z == other:getZ() then count = count + 1 end
            end
        end
    end
    return count
end

function Placement.canJoinThroughWall(network, passage, anchor, target)
    return passage.cover and anchor and target and anchor.square == passage.square
        and target.square == passage.other and anchor.piece.kind == "cable" and target.piece.kind == "cable"
        and compatibleEnds(network, anchor, false, target, false)
end

local function commandPassage(command)
    for _, edge in ipairs(wallEdges) do
        if edge.name == command.side then
            local passage = wallPassthrough(command.square, edge)
            if passage and passage.wall == command.wall then return passage end
        end
    end
end

local function changeWallPassthrough(registry, character, command)
    local passage = commandPassage(command)
    if not passage or passage.cover ~= command.expected then return false, "The wall fitting changed." end
    local inventory = character:getInventory()
    local cover = command.cover
    if cover == "bare" then
        if passage.cover then return false, "This wall already has a passthrough." end
        if not inventory:getFirstType("Base.HandDrill") then return false, "Bring a hand drill." end
    elseif Placement.wallCoverItems[cover] then
        if passage.cover ~= "bare" then return false, "Choose a bare passthrough." end
        if not inventory:getFirstType("Base.Screwdriver") or not Placement.carries(character, command.item)
            or command.item:getFullType() ~= Placement.wallCoverItems[cover] then
            return false, "Bring the matching cover material and a screwdriver."
        end
        inventory:Remove(command.item)
    elseif cover == nil then
        if not passage.cover then return false, "There is no wall passthrough." end
        if Placement.wallCrossings(registry, command.square, passage.other) > 0 then
            return false, "Disconnect the runs through this wall first."
        end
    else
        return false, "Unknown passthrough cover."
    end
    local data = passage.wall:getModData()
    local fittings = data.zedcommWallPassthrough or {}
    fittings[passage.key] = cover
    data.zedcommWallPassthrough = (fittings.north or fittings.west) and fittings or nil
    passage.wall:transmitModData()
    return true
end

local function connectThroughWall(registry, character, command)
    local passage = commandPassage(command)
    if not passage or not passage.cover then return false, "There is no wall passthrough here." end
    local anchor = Placement.resolve(registry, command.anchorId)
    if not anchor or anchor.square ~= command.square or anchor.piece.kind ~= "cable"
        or not Placement.hasFreeEnd(anchor, false) then return false, "Select a free wire end on this side." end
    if Placement.wallCrossings(registry, command.square, passage.other) >= Placement.WALL_PASSTHROUGH_LIMIT then
        return false, "Five runs already cross this wall."
    end
    if command.targetId then
        local target = Placement.resolve(registry, command.targetId)
        if not target or target.object ~= command.remoteWire
            or not Placement.canJoinThroughWall(registry.network, passage, anchor, target) then
            return false, "Choose a compatible free wire end on the other side."
        end
        return link(registry, anchor, false, target, false)
    end
    return place(registry, character, passage.other, command.item, anchor, false, true, nil, true)
end

local commands = {
    ["change-wall-passthrough"] = {
        duration = 100,
        message = function(command)
            if not command.cover then return "Wall passthrough sealed." end
            return command.cover == "bare" and "Wall passthrough drilled." or "Wall passthrough covered."
        end,
        execute = changeWallPassthrough,
    },
    ["connect-through-wall"] = {
        runEffect = "join",
        runMessages = { joined = "Wire connected through the wall." },
        message = "Wire connected through the wall.",
        execute = connectThroughWall,
    },
    place = {
        runEffect = "place",
        runMessages = wireRunMessages,
        message = function(command)
            local spec = specFor(command.item:getFullType())
            return spec.kind == "cable" and "Wire placed loose." or "Device placed."
        end,
        validate = function(character, command)
            return Placement.carries(character, command.item)
                and Placement.canPlace(command.square, command.item:getFullType())
        end,
        execute = function(registry, character, command)
            return place(registry, character, command.square, command.item, nil, nil, false, command.mount)
        end,
    },
    lay = {
        runEffect = "lay",
        runMessages = wireRunMessages,
        validate = function(character, command, registry)
            local anchor = Placement.resolve(registry, command.anchorId)
            return Placement.carries(character, command.item)
                and Placement.canLay(anchor, command.anchorPort, command.square, character)
        end,
        execute = function(registry, character, command)
            local anchor = Placement.resolve(registry, command.anchorId)
            return place(registry, character, command.square, command.item, anchor, command.anchorPort, true, command.mount)
        end,
    },
    join = {
        target = true,
        runEffect = "join",
        runMessages = { joined = "Wire connected." },
        execute = function(registry, character, command, target)
            local anchor = Placement.resolve(registry, command.anchorId)
            if not Circuit.canService(anchor and anchor.piece, character) or not Circuit.canService(target.piece, character) then
                return false, "The board is padlocked."
            end
            if not Placement.canJoin(registry.network, anchor, command.anchorPort, target, command.port, character) then
                return false, "Choose an adjacent, compatible free end."
            end
            return link(registry, anchor, command.anchorPort, target, command.port)
        end,
    },
    pickup = {
        target = true,
        runEffect = "pickup",
        message = "Piece returned to inventory.",
        execute = function(registry, character, _, target)
            return pickUp(registry, character, target)
        end,
    },
    ["fit-lamp-adapter"] = {
        duration = 120,
        message = "Lamp adapter fitted.",
        validate = function(character, command)
            return Placement.carries(character, command.item) and Relay.isEligible(command.object)
                and command.object:getSquare() == command.square and not command.object:getModData().zedcomm
                and Placement.canFitLampAdapter(character, command.item:getFullType() == Circuit.ADVANCED_ADAPTER_ITEM)
        end,
        execute = function(registry, character, command)
            return fitLampAdapter(registry, command.square, command.object, character, command.item)
        end,
    },
    ["remove-lamp-adapter"] = {
        target = true,
        acceptsTarget = relayTarget,
        duration = 120,
        message = "Lamp adapter removed.",
        execute = function(registry, character, _, target)
            return removeLampAdapter(character, registry, target)
        end,
    },
    ["disconnect-relay"] = {
        target = true,
        acceptsTarget = function(target) return target.spec.nativePickup end,
        message = "Wire disconnected.",
        execute = function(registry, _, _command, target)
            local cable = target.piece.ports.signal
            if not cable then return false, "This fixture has no connected wire." end
            return registry:unlink(cable, target.id)
        end,
    },
    ["disconnect-port"] = {
        target = true,
        acceptsTarget = boardTarget,
        message = "Jack disconnected.",
        execute = function(registry, character, command, target)
            if not Circuit.canService(target.piece, character) then return false, "The board is padlocked." end
            local cable = target.piece.ports[command.port]
            if not cable or cable ~= command.cableId then return false, "That jack connection changed." end
            return registry:unlink(cable, target.id)
        end,
    },
    ["install-door-contact"] = contactInstallation(Contact.ID,
        "Door contact installed. Its output reports actual door position."),
    ["install-window-contact"] = contactInstallation(Contact.WINDOW_ID, "Window contact fitted."),
    ["install-storage-sensor"] = contactInstallation(Sensors.STORAGE, "Storage sensor fitted."),
    ["install-fluid-fill-sensor"] = contactInstallation(Sensors.FLUID, "Fluid fill sensor fitted."),
    ["configure-storage-sensor"] = {
        target = true,
        acceptsTarget = function(target) return target.piece.definitionId == Sensors.STORAGE end,
        execute = function(registry, _, command, target)
            local host = Contact.host(target.object)
            local selection = Sensors.storageState(host, command.compartment, command.mode)
            if not selection then return false, "Choose an available compartment and output mode." end
            local state = registry.network:record(target.id).state or {}
            for key, value in pairs(selection) do state[key] = value end
            return registry:setDeviceState(target.id, state)
        end,
    },
    ["remove-door-contact"] = {
        target = true,
        acceptsTarget = function(target) return contactSpecs[target.piece.definitionId] ~= nil end,
        duration = 120,
        message = "Sensor returned to inventory.",
        execute = function(registry, character, _, target)
            if not character:getInventory():getFirstType("Base.Screwdriver") then return false, "Bring a screwdriver." end
            return ZedComm.DoorInstallation.removeContact(character, registry, target)
        end,
    },
    ["install-door"] = {
        duration = 120,
        message = function(command)
            return command.contact and "Door inputs and contact installed. Wire each fixture independently."
                or "Door adapters installed. Wire the Lock and Open jacks independently."
        end,
        validate = function(character, command)
            return ZedComm.Door.isEligible(command.object) and command.object:getSquare() == command.square
                and command.object:getModData().zedcomm == nil
                and ZedComm.DoorInstallation.materials(character, command.tier) ~= nil
                and (not command.contact or (not command.object:getModData().zedcommContact
                    and ZedComm.DoorInstallation.contactMaterials(character) ~= nil))
        end,
        execute = function(registry, character, command)
            if not onSquare(command.object, command.square) then return false, "That door is no longer on the tile." end
            return ZedComm.DoorInstallation.fit(character, registry, command.object,
                chooseId(registry, command.square), command.tier,
                command.contact and chooseId(registry, command.square) or nil)
        end,
    },
    ["remove-door-adapters"] = {
        target = true,
        acceptsTarget = function(target) return target.piece.definitionId == Circuit.DOOR_ID end,
        duration = 120,
        message = "Door adapters and modules returned to inventory.",
        execute = function(registry, character, _, target)
            if not character:getInventory():getFirstType("Base.Screwdriver") then return false, "Bring a screwdriver." end
            return ZedComm.DoorInstallation.remove(character, registry, target)
        end,
    },
    ["fit-padlock"] = {
        target = true,
        message = "Board padlocked.",
        execute = changePadlock,
    },
    ["remove-padlock"] = {
        target = true,
        message = "Padlock removed.",
        execute = changePadlock,
    },
    ["upgrade-cabinet"] = {
        target = true,
        acceptsTarget = boardTarget,
        duration = 120,
        message = "Cabinet upgraded. Basic Adapter returned to inventory.",
        validate = function(character, command, _, target)
            return Placement.canUpgradeCabinet(character, target, command.item)
        end,
        execute = function(registry, character, command, target)
            return upgradeCabinet(registry, character, target, command.item)
        end,
    },
    ["set-network-switch"] = {
        target = true,
        acceptsTarget = switchTarget,
        message = function(command) return command.on and "Switch on." or "Switch off." end,
        execute = function(registry, _, command, target)
            if type(command.on) ~= "boolean" then return false, "Choose an on or off state." end
            return setNetworkSwitch(registry, target, command.on)
        end,
    },
    ["toggle-network-switch"] = {
        target = true,
        acceptsTarget = switchTarget,
        execute = function(registry, _, _command, target)
            return setNetworkSwitch(registry, target)
        end,
    },
}

function Placement.getCommand(kind)
    return commands[kind]
end

local function commandRegistry(character, command)
    local registry = Placement.getRegistry()
    if not registry or registry.network ~= command.network then return nil, "This circuit is no longer loaded." end
    if command.object and not onSquare(command.object, command.square) then
        return nil, "That device or wire is no longer on the tile."
    end
    if not Placement.canReach(character, command.square, command.object) then
        return nil, "Move onto or next to the target tile."
    end
    return registry
end

local function commandTarget(registry, command, descriptor)
    local target = Placement.resolve(registry, command.targetId)
    if not target or target.square ~= command.square or target.object ~= command.object then
        return nil, "That device or wire is no longer on the tile."
    end
    if descriptor.acceptsTarget and not descriptor.acceptsTarget(target) then
        return nil, "Unknown placement action."
    end
    return target
end

function Placement.isValidCommand(character, command)
    local registry = commandRegistry(character, command)
    local descriptor = commands[command.kind]
    if not registry or not descriptor then return false end
    local target
    if descriptor.target then
        target = commandTarget(registry, command, descriptor)
        if not target then return false end
    end
    return not descriptor.validate or descriptor.validate(character, command, registry, target)
end

function Placement.perform(character, command)
    local registry, reason = commandRegistry(character, command)
    if not registry then return false, reason end
    local descriptor = commands[command.kind]
    if not descriptor then return false, "Unknown placement action." end
    local target
    if descriptor.target then
        target, reason = commandTarget(registry, command, descriptor)
        if not target then return false, reason end
    end
    return descriptor.execute(registry, character, command, target)
end

ZedComm.PlayerPlacement = Placement
return Placement
