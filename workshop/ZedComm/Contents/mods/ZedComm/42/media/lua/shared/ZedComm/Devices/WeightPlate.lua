-- Native load estimate on a single tile.
require "ZedComm/DeviceDefinitions"

local id = "ZedComm.WeightPlate"
local ok, reason = ZedComm.DeviceDefinitions.register({
    id = id,
    role = "source",
    readingKind = "weight",
    ports = { "signal" },
    match = function(object, context)
        return context.getDefinitionId(object) == id
    end,
    sample = function(object, context)
        return context.getWeightPlateLoad(object)
    end,
})
if not ok then error(id .. ": " .. reason) end
