-- Singleplayer inventory actions backed by the saved registry.
if isClient() or isServer() then return end

require "ZedComm/Network"
require "ZedComm/NativeDevices"
require "ZedComm/DoorInstallation"

local Placement = {}
local Network = ZedComm.Network
local definitions = ZedComm.DeviceDefinitions
local Relay = ZedComm.RelayLamp
local Circuit = ZedComm.InternalCircuit
local Switch = ZedComm.NetworkSwitch
local serial = 0
local items = {
    { itemType = "ZedComm.PressurePlate", name = "pressure plate", sprite = "zedcomm_devices_01_20",
        kind = "endpoint", definitionId = "ZedComm.PressureSensor", fixtureType = "Plate" },
    { itemType = "ZedComm.SignalWire", name = "wire", sprite = "zedcomm_devices_01_1", kind = "cable" },
    { itemType = "ZedComm.NumericDisplay", name = "numeric display", sprite = "zedcomm_devices_01_431",
        kind = "endpoint", definitionId = "ZedComm.NumericDisplay", fixtureType = "Display" },
    { itemType = "ZedComm.AdvancedDisplay", name = "advanced display", sprite = "zedcomm_devices_01_431",
        kind = "endpoint", definitionId = "ZedComm.AdvancedDisplay", fixtureType = "Display" },
    { itemType = "ZedComm.OccupancyPlate", name = "occupancy plate", sprite = "zedcomm_devices_01_419",
        kind = "endpoint", definitionId = "ZedComm.OccupancyPlate", fixtureType = "Plate" },
    { itemType = "ZedComm.WeightPlate", name = "weight plate", sprite = "zedcomm_devices_01_425",
        kind = "endpoint", definitionId = "ZedComm.WeightPlate", fixtureType = "Plate" },
    { itemType = Circuit.CABINET_ID, name = "basic small cabinet", sprite = "zedcomm_devices_01_466",
        kind = "endpoint", definitionId = Circuit.CABINET_ID, adapter = "basic", fixtureType = "Cabinet" },
    { itemType = Circuit.ADVANCED_CABINET_ITEM, name = "advanced small cabinet", sprite = "zedcomm_devices_01_466",
        kind = "endpoint", definitionId = Circuit.CABINET_ID, adapter = "advanced", fixtureType = "Cabinet" },
    { itemType = "ZedComm.DebugByteSource", name = "test byte source", sprite = "zedcomm_devices_01_431",
        kind = "endpoint", definitionId = "ZedComm.DebugByteSource", fixtureType = "Source" },
    { itemType = Switch.ID, name = "network switch", sprite = Switch.OFF_NORTH,
        kind = "endpoint", definitionId = Switch.ID, fixtureType = "Switch" },
}
local relaySpec = { name = "relay lamp", kind = "endpoint", definitionId = Relay.ID, nativePickup = true,
    fixtureType = "Lamp" }
local contactSpec = { name = "door contact", kind = "endpoint", definitionId = "ZedComm.DoorContact",
    nativePickup = true, fixtureType = "Door Contact" }
local doorSpec = { name = "networked door", kind = "endpoint", definitionId = Circuit.DOOR_ID,
    nativePickup = true, fixtureType = "Door" }
Placement.WIRE_TYPE = items[2].itemType

local function specFor(itemType)
    for i = 1, #items do
        if items[i].itemType == itemType then return items[i] end
    end
end

function Placement.getSpec(itemType)
    return specFor(itemType)
end

function Placement.switchMount(square, item, preferred)
    local saved = item:getModData().zedcommPlacement
    local state = type(saved) == "table" and saved.state
    return Switch.mount(square, preferred or (type(state) == "table" and state.mount))
end

function Placement.previewSprite(square, item, mount)
    local spec = specFor(item:getFullType())
    if not spec then return nil end
    if spec.definitionId ~= Switch.ID or not square then return spec.sprite end
    local saved = item:getModData().zedcommPlacement
    local state = type(saved) == "table" and saved.state
    return Switch.sprite(Placement.switchMount(square, item, mount), type(state) == "table" and state.on == true)
end

function Placement.getRegistry()
    local registry = ZedComm.Registry
    return registry and registry.instance
end

local function tagOf(object)
    if not object:hasModData() then return nil end
    local tag = object:getModData().zedcomm
    if type(tag) == "table" and type(tag.id) == "string" then return tag end
end

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

function Placement.canReach(character, square)
    local from = character:getCurrentSquare()
    return loadedSquare(square) and from and distance(from, square) <= 1 and clearBetween(from, square)
end

-- Looking range for read-only UI such as the adapter editor: up to two tiles on the same
-- level, through an open path. Changes still need canReach.
function Placement.canView(character, square)
    local from = character:getCurrentSquare()
    if not loadedSquare(square) or not from then return false end
    local steps = distance(from, square)
    if steps <= 1 then return clearBetween(from, square) end
    if steps ~= 2 then return false end
    local cell = getCell()
    for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local middle = cell:getGridSquare(from:getX() + step[1], from:getY() + step[2], from:getZ())
        if middle and distance(middle, square) == 1 and clearBetween(from, middle)
            and clearBetween(middle, square) then return true end
    end
    return false
end

local function squareObjects(square)
    local out = {}
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do out[#out + 1] = objects:get(i) end
    return out
end

local function onSquare(object, square)
    if not loadedSquare(square) or object:getSquare() ~= square then return false end
    for _, candidate in ipairs(squareObjects(square)) do
        if candidate == object then return true end
    end
    return false
end

function Placement.relayCandidates(square)
    local out = {}
    if not getDebug() then return out end
    for _, object in ipairs(squareObjects(square)) do
        if Relay.isEligible(object) and not tagOf(object) then out[#out + 1] = object end
    end
    return out
end

function Placement.doorCandidates(square)
    local out = {}
    for _, object in ipairs(squareObjects(square)) do
        if ZedComm.Door.isEligible(object) then out[#out + 1] = object end
    end
    return out
end

function Placement.piecesAt(registry, square)
    local out = {}
    for _, object in ipairs(squareObjects(square)) do
        local tag = tagOf(object)
        local spec = tag and (specFor(tag.placedItem) or (tag.definitionId == Relay.ID and relaySpec)
            or (tag.definitionId == Circuit.DOOR_ID and doorSpec)
            or (tag.definitionId == ZedComm.DoorContact.ID and contactSpec))
        local piece = spec and registry.network.pieces[tag.id]
        if piece and piece.kind == spec.kind and piece.definitionId == spec.definitionId
            and piece.x == square:getX() and piece.y == square:getY() and piece.z == square:getZ() then
            if piece.definitionId == Circuit.CABINET_ID then
                local advanced = piece.state.adapter == "advanced"
                spec = specFor(advanced and Circuit.ADVANCED_CABINET_ITEM or Circuit.CABINET_ID)
            end
            out[#out + 1] = { id = piece.id, piece = piece, object = object, square = square, spec = spec }
        end
    end
    return out
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

function Placement.freePorts(entry)
    local piece = entry.piece
    local out = {}
    if piece.kind == "cable" then
        local count = 0
        for _ in pairs(piece.links) do count = count + 1 end
        if count < Network.MAX_CABLE_LINKS then out[1] = false end
    elseif not piece.definitionUnavailable then
        for name, link in pairs(piece.ports) do
            if link == false then out[#out + 1] = name end
        end
        table.sort(out)
    end
    return out
end

function Placement.hasFreeEnd(entry, port)
    if not entry then return false end
    for _, candidate in ipairs(Placement.freePorts(entry)) do
        if port == candidate then return true end
    end
    return false
end

local function linkDistance(first, second, secondKind)
    local steps = distance(first.square, second)
    if first.piece.kind == "cable" and secondKind == "cable" then
        return steps == 1 and clearBetween(first.square, second)
    end
    return steps <= 1 and clearBetween(first.square, second)
end

function Placement.canJoin(network, first, firstPort, second, secondPort)
    if not Placement.hasFreeEnd(first, firstPort) or not Placement.hasFreeEnd(second, secondPort)
        or first.id == second.id then return false end
    local a, b = first.piece.kind, second.piece.kind
    if a ~= "cable" and b ~= "cable" then return false end
    if not linkDistance(first, second.square, b) then return false end
    -- Free ends on the same chain cannot be joined into a loop.
    local firstNet = network:networkOf(first.id, firstPort or nil)
    local secondNet = network:networkOf(second.id, secondPort or nil)
    if firstNet == secondNet then return false end
    return #network.nets[firstNet].sources == 0 or #network.nets[secondNet].sources == 0
end

local function link(registry, first, firstPort, second, secondPort)
    if first.piece.kind == "cable" then
        return registry:link(first.id, second.id, secondPort or nil)
    end
    return registry:link(second.id, first.id, firstPort or nil)
end

local function tileAvailable(square, spec)
    if not square:TreatAsSolidFloor() or square:isSolid() or square:isSolidTrans() then
        return false, "Choose a clear floor tile."
    end
    if spec.definitionId == Switch.ID and not Switch.mount(square) then
        return false, "Choose a tile next to a wall for the switch."
    end
    if spec.kind == "endpoint" then
        for _, object in ipairs(squareObjects(square)) do
            local tag = tagOf(object)
            if tag and tag.kind == "endpoint" then return false, "There is already a device here." end
        end
    end
    return true
end

function Placement.canPlace(square, itemType)
    local spec = specFor(itemType)
    return spec ~= nil and loadedSquare(square) and tileAvailable(square, spec)
end

local function canExtend(entry, port, square)
    return square ~= nil and Placement.hasFreeEnd(entry, port) and linkDistance(entry, square, "cable")
end

function Placement.canLay(entry, port, square)
    return canExtend(entry, port, square) and tileAvailable(square, items[2])
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

local function place(registry, character, square, item, anchor, anchorPort, laying, mount)
    local inventory = character:getInventory()
    local spec = item and specFor(item:getFullType())
    if not spec or item:getContainer() ~= inventory or not inventory:contains(item) then
        return false, "That item is no longer in your main inventory."
    end
    if laying and spec.kind ~= "cable" then return false, "Choose a wire to extend this run." end
    local valid, why = tileAvailable(square, spec)
    if not valid then return false, why end
    if laying and not canExtend(anchor, anchorPort, square) then
        return false, "Select a free end on this tile or a neighboring tile."
    end
    if spec.definitionId == Switch.ID then
        local facing = Placement.switchMount(square, item, mount)
        if mount and mount ~= facing then return false, "That wall is no longer available." end
        mount = facing
    end
    local sprite = Placement.previewSprite(square, item, mount)
    if not getSprite(sprite) then return false, "The ZedComm sprite is missing." end
    if spec.definitionId and spec.definitionId ~= Circuit.CABINET_ID and not definitions.get(spec.definitionId) then
        return false, "The device definition is missing."
    end
    local retained = retainedState(item, spec)
    local id = chooseId(registry, square, retained)
    if not id then return false, "A device with this identity is already placed." end

    local object = IsoObject.new(square, sprite, item:getName())
    local state = retained and retained.state
    if spec.adapter then
        state = { adapter = spec.adapter, circuit = state and state.circuit or { modules = {}, links = {} },
            portLabels = state and state.portLabels, fixtureName = state and state.fixtureName }
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

local function pickUp(registry, character, entry)
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

local function installRelay(registry, square, lamp, character, adapterItem)
    if not getDebug() or not Relay.isEligible(lamp) or not onSquare(lamp, square) then
        return false, "Choose a placed, modifiable lamp in debug singleplayer."
    end
    local data = lamp:getModData()
    if data.zedcomm ~= nil then return false, "This fixture already has a ZedComm device." end
    for _, object in ipairs(squareObjects(square)) do
        local tag = tagOf(object)
        if tag and tag.kind == "endpoint" then return false, "There is already a device on this tile." end
    end
    local id = chooseId(registry, square)
    local state = { module = { id = Relay.MODULE, config = {} } }
    local inventory
    if adapterItem then
        inventory = character:getInventory()
        if adapterItem:getFullType() ~= "ZedComm.AdvancedAdapter"
            or adapterItem:getContainer() ~= inventory or not inventory:contains(adapterItem) then
            return false, "The Advanced Adapter is no longer in your main inventory."
        end
        state.circuit = { modules = {}, links = {} }
        inventory:Remove(adapterItem)
    end
    data.zedcomm = { id = id, kind = "endpoint", definitionId = Relay.ID, state = state }
    local called, ok, reason = pcall(registry.addPiece, registry, lamp)
    if not called or not ok then
        if registry.network.pieces[id] then registry:removePiece(id) end
        data.zedcomm = nil
        if inventory then inventory:AddItem(adapterItem) end
        return false, called and reason or tostring(ok)
    end
    Relay.writeInstallation(data, id, state)
    return true, id
end

function Placement.canUpgradeCabinet(character, entry, adapter)
    if not entry or entry.piece.definitionId ~= Circuit.CABINET_ID then return false, "That cabinet is no longer available." end
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
    if not entry or entry.object ~= target.object or not Placement.canReach(character, entry.square) then
        return false, "That device is no longer within reach."
    end
    local state = entry.piece.state
    local cabinet = Circuit.profileFor(entry.piece.definitionId)
    if (not cabinet and entry.piece.definitionId ~= Relay.ID) or not state
        or type(expected) ~= "table" or state.circuit ~= expected then
        return false, "The circuit changed. Reopen the editor."
    end
    local valid, errorMessage = Circuit.compile(layout, cabinet, cabinet and state.adapter or nil)
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
    if not entry or entry.object ~= target.object or not Placement.canReach(character, entry.square)
        or not entry.piece.state or entry.piece.state.circuit ~= expected then
        return false, "The circuit changed or is out of reach."
    end
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

function Placement.perform(character, command)
    local registry = Placement.getRegistry()
    if not registry or registry.network ~= command.network then return false, "This circuit is no longer loaded." end
    if not Placement.canReach(character, command.square) then
        return false, "Move onto or next to the target tile."
    end
    if command.kind == "install-relay" then
        return installRelay(registry, command.square, command.object)
    end
    if command.kind == "install-advanced-adapter" and command.item then
        return installRelay(registry, command.square, command.object, character, command.item)
    end
    if command.kind == "install-door-contact" then
        if not onSquare(command.object, command.square) then return false, "That door is no longer on the tile." end
        return ZedComm.DoorInstallation.installContact(character, registry, command.object, chooseId(registry, command.square))
    end
    if command.kind == "install-door" then
        if not onSquare(command.object, command.square) then return false, "That door is no longer on the tile." end
        return ZedComm.DoorInstallation.fit(character, registry, command.object,
            chooseId(registry, command.square), command.tier,
            command.contact and chooseId(registry, command.square) or nil)
    end
    if command.kind == "place" or command.kind == "lay" then
        return place(registry, character, command.square, command.item,
            Placement.resolve(registry, command.anchorId), command.anchorPort, command.kind == "lay", command.mount)
    end
    local target = Placement.resolve(registry, command.targetId)
    if not target or target.square ~= command.square or target.object ~= command.object then
        return false, "That device or wire is no longer on the tile."
    end
    if command.kind == "disconnect-relay" and target.spec.nativePickup then
        local cable = target.piece.ports.signal
        if not cable then return false, "The relay lamp has no connected wire." end
        return registry:unlink(cable, target.id)
    end
    if command.kind == "disconnect-port" and target.piece.board then
        local cable = target.piece.ports[command.port]
        if not cable or cable ~= command.cableId then return false, "That jack connection changed." end
        return registry:unlink(cable, target.id)
    end
    if command.kind == "remove-door-contact" and target.piece.definitionId == ZedComm.DoorContact.ID then
        if not character:getInventory():getFirstType("Base.Screwdriver") then return false, "Bring a screwdriver." end
        return ZedComm.DoorInstallation.removeContact(character, registry, target)
    end
    if command.kind == "remove-door-adapters" and target.piece.definitionId == Circuit.DOOR_ID then
        if not character:getInventory():getFirstType("Base.Screwdriver") then return false, "Bring a screwdriver." end
        return ZedComm.DoorInstallation.remove(character, registry, target)
    end
    if command.kind == "upgrade-cabinet" and target.piece.board then
        return upgradeCabinet(registry, character, target, command.item)
    end
    if (command.kind == "set-network-switch" or command.kind == "toggle-network-switch")
        and target.piece.definitionId == Switch.ID then
        local state = registry.network:record(target.id).state or { mount = Switch.mount(target.square) }
        if command.kind == "toggle-network-switch" then
            state.on = not state.on
        else
            if type(command.on) ~= "boolean" then return false, "Choose an on or off state." end
            state.on = command.on
        end
        return registry:setDeviceState(target.id, state)
    end
    if command.kind == "pickup" then
        if target.spec.nativePickup then return false, "Use the normal moveable pickup for this lamp." end
        return pickUp(registry, character, target)
    end
    if command.kind == "join" then
        local anchor = Placement.resolve(registry, command.anchorId)
        if not Placement.canJoin(registry.network, anchor, command.anchorPort, target, command.port) then
            return false, "Choose an adjacent, compatible free end."
        end
        return link(registry, anchor, command.anchorPort, target, command.port)
    end
    return false, "Unknown placement action."
end

ZedComm.PlayerPlacement = Placement
return Placement
