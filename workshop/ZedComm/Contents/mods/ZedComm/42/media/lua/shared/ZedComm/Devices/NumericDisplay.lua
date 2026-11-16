-- Native numeric display behavior (ADR-102 and ADR-303).
require "ZedComm/DeviceDefinitions"
require "ZedComm/SignalModules"

local id = "ZedComm.NumericDisplay"
local ok, reason = ZedComm.DeviceDefinitions.register({
    id = id,
    role = "receiver",
    ports = { "signal" },
    match = function(object, context)
        return context.getDefinitionId(object) == id
    end,
    receiverModule = ZedComm.SignalModules.BYTE_READOUT,
    bindFixture = function(object, context)
        return {
            apply = function(_, value)
                context.setDisplay(object, value, value ~= nil and value ~= 0)
                return "applied"
            end,
            release = function() context.clearDisplay(object) end,
        }
    end,
})
if not ok then error(id .. ": " .. reason) end
