require "ZedComm/DeviceDefinitions"

local IR = { ID = "ZedComm.IRSensor", defaults = { radius = 5, target = "both", mode = "fixed", byte = 255 } }
ZedComm.IRSensor = IR

function IR.validate(field, input)
    if field == "radius" or field == "byte" then
        local value = tonumber(input)
        local minimum, maximum = 0, 255
        if field == "radius" then minimum, maximum = 1, 10 end
        if value and value >= minimum and value <= maximum and math.floor(value) == value then return value end
    elseif field == "target" and (input == "both" or input == "player" or input == "zombie") then
        return input
    elseif field == "mode" and (input == "fixed" or input == "nearest" or input == "count") then
        return input
    end
end

function IR.setting(state, field)
    return state and IR.validate(field, state[field]) or IR.defaults[field]
end

local function openEdge(from, to)
    return to and not from:isDoorBlockedTo(to) and (from:isDoorTo(to) or not from:isWallTo(to))
end

-- Trace between tile centers. At an exact corner either pair of open
-- cardinal edges admits a ray. An unloaded intermediate tile blocks that path.
local function visible(cell, origin, dx, dy)
    local x, y, z = origin:getX(), origin:getY(), origin:getZ()
    local nx, ny = math.abs(dx), math.abs(dy)
    local sx, sy = dx < 0 and -1 or 1, dy < 0 and -1 or 1
    local ix, iy, current = 0, 0, origin
    while ix < nx or iy < ny do
        local cross = (2 * ix + 1) * ny - (2 * iy + 1) * nx
        local nextSquare
        if cross == 0 then
            local horizontal = cell:getGridSquare(x + sx, y, z)
            local vertical = cell:getGridSquare(x, y + sy, z)
            x, y, ix, iy = x + sx, y + sy, ix + 1, iy + 1
            nextSquare = cell:getGridSquare(x, y, z)
            if not ((openEdge(current, horizontal) and openEdge(horizontal, nextSquare))
                or (openEdge(current, vertical) and openEdge(vertical, nextSquare))) then return false end
        else
            if cross < 0 then x, ix = x + sx, ix + 1 else y, iy = y + sy, iy + 1 end
            nextSquare = cell:getGridSquare(x, y, z)
            if not openEdge(current, nextSquare) then return false end
        end
        current = nextSquare
    end
    return true
end

local function eligible(actor, target)
    local zombie = instanceof(actor, "IsoZombie")
    local player = instanceof(actor, "IsoPlayer") and not instanceof(actor, "IsoAnimal")
    return ((zombie and target ~= "player") or (player and target ~= "zombie"))
        and not actor:isDead() and not actor:getVehicle()
end

function IR.sample(object, _, state)
    local origin = object:getSquare()
    local cell = origin:getCell()
    local radius, target = IR.setting(state, "radius"), IR.setting(state, "target")
    local mode, count, nearest = IR.setting(state, "mode"), 0, radius * radius
    for dx = -radius, radius do
        local limit = math.floor(math.sqrt(radius * radius - dx * dx))
        for dy = -limit, limit do
            local square = cell:getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
            local actors = square and square:getMovingObjects()
            if actors and actors:size() > 0 then
                local clear
                for i = 0, actors:size() - 1 do
                    if eligible(actors:get(i), target) then
                        if clear == nil then clear = visible(cell, origin, dx, dy) end
                        if not clear then break end
                        if mode == "fixed" then return IR.setting(state, "byte") end
                        count = count + 1
                        if mode == "count" and count >= 255 then return 255 end
                        nearest = math.min(nearest, dx * dx + dy * dy)
                    end
                end
            end
        end
    end
    if count == 0 then return 0 end
    if mode == "nearest" then return 255 - math.floor(254 * math.sqrt(nearest) / radius + 0.5) end
    return count
end

local ok, reason = ZedComm.DeviceDefinitions.register({
    id = IR.ID, role = "source", ports = { "signal" }, sampleInterval = 0.25,
    match = function(object, context) return context.getDefinitionId(object) == IR.ID end,
    sample = IR.sample,
})
if not ok then error(IR.ID .. ": " .. reason) end
