require "ZedComm/InternalCircuit"

local Parts = {}
local Circuit = ZedComm.InternalCircuit

function Parts.discard(inventory, items)
    for _, item in ipairs(items) do inventory:Remove(item) end
end

function Parts.recover(character, state, adapterCount)
    local inventory, items = character:getInventory(), {}
    local function add(itemType, source)
        local item = instanceItem(itemType)
        if not item or not inventory:hasRoomFor(character, item) then
            Parts.discard(inventory, items)
            return false
        end
        if source then
            item:getModData().zedcommCharge = source.charge
            item:getModData().zedcommSourceLevel = source.level
        end
        inventory:AddItem(item)
        items[#items + 1] = item
        return true
    end

    local adapter = state.adapter == "advanced" and Circuit.ADVANCED_ADAPTER_ITEM or Circuit.BASIC_ADAPTER_ITEM
    for _ = 1, adapterCount do
        if not add(adapter) then return nil end
    end
    local modules = type(state.circuit) == "table" and state.circuit.modules
    if type(modules) == "table" then
        for _, part in pairs(modules) do
            local kind = type(part) == "table" and Circuit.kinds[part.kind]
            if kind and kind.item and not add(kind.item, kind.source and part) then return nil end
        end
    end
    return items
end

return Parts
