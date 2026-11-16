-- A latched source with one wire jack.
require "ZedComm/DeviceDefinitions"
require "ZedComm/WireShape"

local Switch = {
    ID = "ZedComm.NetworkSwitch",
    OFF_NORTH = "zedcomm_devices_01_467",
}

local offFrames = { north = 467, west = 469, south = 471, east = 473 }
local facings = { "north", "west", "south", "east" }
local leadFrames = { [0] = 0, [1] = 1, [2] = 2, [4] = 3, [8] = 4 }
local southWall, eastWall = 2, 8 -- IsoGridSquare.getWallType() masks

function Switch.mounts(square)
    if not square then return {} end
    -- The south and east edges can belong to the next square's wall.
    local walls = square:getWallType()
    local eligible = { not not square:getWall(true), not not square:getWall(false),
        math.floor(walls / southWall) % 2 == 1, math.floor(walls / eastWall) % 2 == 1 }
    local mounts = {}
    for index, facing in ipairs(facings) do
        if eligible[index] then mounts[#mounts + 1] = facing end
    end
    return mounts
end

function Switch.mount(square, preferred)
    local mounts = Switch.mounts(square)
    for _, facing in ipairs(mounts) do
        if facing == preferred then return facing end
    end
    return mounts[1]
end

function Switch.nextMount(square, current)
    local mounts = Switch.mounts(square)
    for i, facing in ipairs(mounts) do
        if facing == current then return mounts[i % #mounts + 1] end
    end
    return mounts[1]
end

function Switch.sprite(mount, on, direction)
    local frame = (offFrames[mount] or offFrames.north) + (on and 1 or 0)
    if leadFrames[direction] then
        return "zedcomm_switch_01_" .. ((frame - 467) * 5 + leadFrames[direction])
    end
    return "zedcomm_devices_01_" .. frame
end

function Switch.updateSprite(object, state, network, piece)
    if not state then return end
    local direction = ZedComm.WireShape.portDirection(network, piece, "signal")
    local sprite = getSprite(Switch.sprite(state.mount, state.on, direction))
    if sprite and object:getSprite() ~= sprite then object:setSprite(sprite) end
end

local ok, reason = ZedComm.DeviceDefinitions.register({
    id = Switch.ID,
    role = "source",
    ports = { "signal" },
    match = function(object, context)
        return context.getDefinitionId(object) == Switch.ID
    end,
    sample = function(object, context)
        return context.isNetworkSwitchOn(object) and 255 or 0
    end,
})
if not ok then error(Switch.ID .. ": " .. reason) end
ZedComm.NetworkSwitch = Switch
return Switch
