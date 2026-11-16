-- Native numeric display behavior (ADR-102 and ADR-303).
require "ZedComm/DeviceDefinitions"
require "ZedComm/SignalModules"

local function register(id, module, apply)
    local ok, reason = ZedComm.DeviceDefinitions.register({
        id = id,
        role = "receiver",
        ports = { "signal" },
        match = function(object, context)
            return context.getDefinitionId(object) == id
        end,
        receiverModule = module,
        bindFixture = function(object, context)
            return {
                apply = function(_, value)
                    apply(context, object, value)
                    return "applied"
                end,
                release = function() context.clearDisplay(object) end,
            }
        end,
    })
    if not ok then error(id .. ": " .. reason) end
end

register("ZedComm.NumericDisplay", ZedComm.SignalModules.BYTE_READOUT, function(context, object, value)
    context.setDisplay(object, value, value ~= nil and value ~= 0)
end)
register("ZedComm.AdvancedDisplay", ZedComm.SignalModules.ADVANCED_READOUT, function(context, object, packet)
    context.setDisplayPacket(object, packet)
end)
