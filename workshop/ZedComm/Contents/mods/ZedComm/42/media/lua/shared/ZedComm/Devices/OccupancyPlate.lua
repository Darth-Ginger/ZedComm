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
        local count = 0
        for _, kind in ipairs(context.getOccupantKinds(object)) do
            if kind == "player" or kind == "zombie" then
                count = count + 1
                if count == 255 then return count end
            end
        end
        return count
    end,
})
if not ok then error(id .. ": " .. reason) end
