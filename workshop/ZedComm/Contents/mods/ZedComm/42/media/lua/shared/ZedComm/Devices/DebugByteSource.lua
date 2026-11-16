-- Development source for the byte contract (ADR-102).
require "ZedComm/DeviceDefinitions"

local id = "ZedComm.DebugByteSource"
local ok, reason = ZedComm.DeviceDefinitions.register({
    id = id,
    role = "source",
    ports = { "signal" },
    match = function(object, context)
        return context.getDefinitionId(object) == id
    end,
    sample = function(object, context)
        return context.getDebugByte(object)
    end,
})
if not ok then error(id .. ": " .. reason) end
