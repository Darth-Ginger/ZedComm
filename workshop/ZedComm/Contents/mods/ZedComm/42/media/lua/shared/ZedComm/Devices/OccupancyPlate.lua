-- Native single-tile actor count.
require "ZedComm/DeviceDefinitions"

local id = "ZedComm.OccupancyPlate"
local ok, reason = ZedComm.DeviceDefinitions.register({
    id = id,
    role = "source",
    ports = { "signal" },
    match = function(object, context)
        return context.getDefinitionId(object) == id
    end,
    sample = function(object, context)
        return context.getOccupantCount(object)
    end,
})
if not ok then error(id .. ": " .. reason) end
