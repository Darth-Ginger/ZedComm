-- Retrofit transactions preserve the native door and unrelated mod data.
require "ZedComm/Devices/Door"
local Installation = {}
local Circuit, Door = ZedComm.InternalCircuit, ZedComm.Door

function Installation.materials(character, tier)
    if tier ~= "basic" and tier ~= "advanced" then return nil, "Choose Basic or Advanced Adapters." end
    local requiredLevel = tier == "advanced" and 3 or 1
    if character:getPerkLevel(Perks.Electricity) < requiredLevel then
        return nil, "Door installation requires Electrical " .. requiredLevel .. "."
    end
    local inventory, adapters = character:getInventory(), {}
    local itemType = tier == "advanced" and Circuit.ADVANCED_ADAPTER_ITEM or Circuit.BASIC_ADAPTER_ITEM
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == itemType and #adapters < 2 then adapters[#adapters + 1] = item end
    end
    if #adapters ~= 2 or not inventory:getFirstType("Base.Screwdriver") then
        return nil, "Bring two matching adapters and a screwdriver in your main inventory."
    end
    return adapters
end

function Installation.install(character, registry, object, id, tier)
    if not Door.isEligible(object) then return false, "Choose a single-panel door." end
    local data = object:getModData()
    if data.zedcomm ~= nil then return false, "This fixture already has a ZedComm device." end
    local adapters, reason = Installation.materials(character, tier)
    if not adapters then return false, reason end
    local inventory = character:getInventory()
    for _, item in ipairs(adapters) do inventory:Remove(item) end
    data.zedcomm = { id = id, kind = "endpoint", definitionId = Door.ID, state = {
        adapter = tier, circuit = Circuit.doorPreset(), doorMount = Door.visualMount(object, character),
        nativeLock = { locked = object:isLocked(), keyed = object:isLockedByKey() },
    } }
    local called, ok, errorMessage = pcall(registry.addPiece, registry, object)
    if not called or not ok then
        if registry.network.pieces[id] then registry:removePiece(id) end
        data.zedcomm = nil
        for _, item in ipairs(adapters) do inventory:AddItem(item) end
        return false, called and errorMessage or tostring(ok)
    end
    return true, id, adapters
end

function Installation.contactMaterials(character)
    if character:getPerkLevel(Perks.Electricity) < 1 then return nil, "Contact fitting requires Electrical 1." end
    local inventory = character:getInventory()
    local item = inventory:getFirstType(ZedComm.DoorContact.ITEM)
    if not item or not inventory:getFirstType("Base.Screwdriver") then
        return nil, "Bring a Door Contact and a screwdriver in your main inventory."
    end
    return item
end

function Installation.installContact(character, registry, door, id)
    if not Door.isEligible(door) or door:getModData().zedcommContact then return false, "Choose a door without a contact sensor." end
    local item, reason = Installation.contactMaterials(character)
    if not item then return false, reason end
    local square = door:getSquare()
    local object = IsoObject.new(square, "zedcomm_door_floor_01_0", "ZedComm door contact")
    object:getModData().zedcomm = { id = id, kind = "endpoint", definitionId = ZedComm.DoorContact.ID }
    character:getInventory():Remove(item)
    door:getModData().zedcommContact = id
    local called, ok, errorMessage = pcall(function()
        square:AddTileObject(object)
        return registry:addPiece(object)
    end)
    if not called or not ok then
        if registry.network.pieces[id] then registry:removePiece(id) end
        door:getModData().zedcommContact = nil
        object:getModData().zedcomm = nil
        pcall(square.transmitRemoveItemFromSquare, square, object)
        character:getInventory():AddItem(item)
        return false, called and errorMessage or tostring(ok)
    end
    return true, id
end

function Installation.removeContact(character, registry, entry)
    local item = instanceItem(ZedComm.DoorContact.ITEM)
    local inventory = character:getInventory()
    if not item or not inventory:hasRoomFor(character, item) then return false, "There is no room for the contact sensor." end
    local door = ZedComm.DoorContact.host(entry.object)
    local record = registry.network:record(entry.id)
    local cable = entry.piece.ports.signal
    pcall(entry.square.transmitRemoveItemFromSquare, entry.square, entry.object)
    local objects = entry.square:getObjects()
    for i = 0, objects:size() - 1 do
        if objects:get(i) == entry.object then
            if not registry.network.pieces[entry.id] then
                entry.object:getModData().zedcomm.state = record.state
                registry:addPiece(entry.object)
                if cable then registry:link(cable, entry.id, "signal") end
            end
            return false, "Could not remove the contact sensor."
        end
    end
    if registry.network.pieces[entry.id] then registry:removePiece(entry.id) end
    if door then door:getModData().zedcommContact = nil end
    entry.object:getModData().zedcomm = nil
    inventory:AddItem(item)
    return true
end

function Installation.remove(character, registry, entry)
    if not Door.isEligible(entry.object) then return false, "That door is no longer available." end
    local state = entry.piece.state
    local inventory, recovered = character:getInventory(), {}
    local function recover(itemType, part)
        local item = instanceItem(itemType)
        if not item or not inventory:hasRoomFor(character, item) then return false end
        if part and Circuit.kinds[part.kind].source then
            item:getModData().zedcommCharge = part.charge
            item:getModData().zedcommSourceLevel = part.level
        end
        inventory:AddItem(item)
        recovered[#recovered + 1] = item
        return true
    end
    local itemType = state.adapter == "advanced" and Circuit.ADVANCED_ADAPTER_ITEM or Circuit.BASIC_ADAPTER_ITEM
    local room = recover(itemType) and recover(itemType)
    for _, part in pairs(state.circuit.modules) do
        if room then room = recover(Circuit.kinds[part.kind].item, part) end
    end
    if not room then
        for _, item in ipairs(recovered) do inventory:Remove(item) end
        return false, "There is no room for the adapters and modules."
    end
    local ok, reason = registry:removePiece(entry.id)
    if not ok then
        for _, item in ipairs(recovered) do inventory:Remove(item) end
        return false, reason
    end
    ZedComm.DeviceRuntime.releaseBoard(entry.id)
    entry.object:getModData().zedcomm = nil
    return true
end

ZedComm.DoorInstallation = Installation
return Installation
