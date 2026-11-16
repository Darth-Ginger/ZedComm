-- Test fixture for the shared On/Off receiver (ADR-308).
require "ZedComm/DeviceDefinitions"
require "ZedComm/SignalModules"
require "ZedComm/InternalCircuit"

local Relay = {
    ID = "ZedComm.RelayLamp",
    MODULE = ZedComm.SignalModules.ON_OFF,
}

function Relay.isEligible(object)
    return object ~= nil and instanceof(object, "IsoLightSwitch") and object:getCanBeModified()
end

function Relay.writeInstallation(data, id, state)
    if type(data.movableData) ~= "table" then data.movableData = {} end
    data.movableData.zedcommRelay = { id = id, state = state }
end

-- Vanilla copies movableData to an item before the removal hook runs.
-- When it places that item again, rebuild the world tag from the marker.
function Relay.restoreTag(object, data)
    if data.zedcomm ~= nil then return nil end
    local marker = type(data.movableData) == "table" and data.movableData.zedcommRelay
    local state = type(marker) == "table" and marker.state
    if type(marker) ~= "table" or type(marker.id) ~= "string" or type(state) ~= "table"
        or type(state.module) ~= "table" or not Relay.isEligible(object) then return nil end
    local tag = { id = marker.id, kind = "endpoint", definitionId = Relay.ID, state = state }
    data.zedcomm = tag
    return tag
end

function Relay.isWired(object)
    if not Relay.isEligible(object) or not object:hasModData() then return false end
    local tag = object:getModData().zedcomm
    if type(tag) ~= "table" or tag.definitionId ~= Relay.ID then return false end
    local registry = ZedComm.Registry and ZedComm.Registry.instance
    local piece = registry and registry.network.pieces[tag.id]
    local square = object:getSquare()
    return piece ~= nil and piece.definitionId == Relay.ID and square ~= nil
        and piece.x == square:getX() and piece.y == square:getY() and piece.z == square:getZ()
        and piece.ports.signal ~= nil and piece.ports.signal ~= false
end

-- The wire stays byte-valued. Only the lamp's request uses the circuit result.
function Relay.compileCircuit(state)
    if not state or state.circuit == nil then return nil end
    local evaluate, reason = ZedComm.InternalCircuit.compile(state.circuit)
    if evaluate then return evaluate end
    return function() return nil end, reason
end

local function bindLamp(object)
    if not Relay.isEligible(object) or isClient() or isServer() then
        return { apply = function() return "unsupported", "lamp retrofit is singleplayer only" end }
    end
    return {
        isAvailable = function() return object:getSquare() ~= nil and object:canSwitchLight() end,
        apply = function(self, desired)
            if not self:isAvailable() then return "unavailable", "lamp cannot switch without power and a bulb" end
            if object:isActivated() ~= desired then object:setActive(desired) end
            if object:isActivated() ~= desired then return "unavailable", "lamp rejected the requested state" end
            return "applied"
        end,
    }
end

local ok, reason = ZedComm.DeviceDefinitions.register({
    id = Relay.ID,
    role = "receiver",
    ports = { "signal" },
    match = function(object, context)
        return context.getDefinitionId(object) == Relay.ID and Relay.isEligible(object)
    end,
    receiverModule = Relay.MODULE,
    bindFixture = bindLamp,
})
if not ok then error(Relay.ID .. ": " .. reason) end
ZedComm.RelayLamp = Relay
return Relay
