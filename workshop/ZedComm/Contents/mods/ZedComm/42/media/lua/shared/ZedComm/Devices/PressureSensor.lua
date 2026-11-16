-- Native pressure sensor behavior (ADR-102).
require "ZedComm/DeviceDefinitions"

local id = "ZedComm.PressureSensor"
local ok, reason = ZedComm.DeviceDefinitions.register({
    id = id,
    role = "source",
    ports = { "signal" },
    match = function(object, context)
        return context.getDefinitionId(object) == id
    end,
    sample = function(object, context)
        if context.isPressurePlateOccupied(object) then
            return context.getPressureOutput(object)
        end
        return 0
    end,
})
if not ok then error(id .. ": " .. reason) end
