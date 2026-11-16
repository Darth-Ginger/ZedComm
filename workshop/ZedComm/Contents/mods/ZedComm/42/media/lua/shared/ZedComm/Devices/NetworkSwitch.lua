-- A latched source with one wire jack.
require "ZedComm/DeviceDefinitions"

local Switch = {
    ID = "ZedComm.NetworkSwitch",
    OFF_NORTH = "zedcomm_devices_01_467",
}

local offFrames = { north = 467, west = 469, south = 471, east = 473 }
local southWall, eastWall = 2, 8 -- IsoGridSquare.getWallType() masks

function Switch.mount(square)
    if square:getWall(true) then return "north" end
    if square:getWall(false) then return "west" end
    -- The south and east edges can belong to the next square's wall.
    local walls = square:getWallType()
    if math.floor(walls / southWall) % 2 == 1 then return "south" end
    if math.floor(walls / eastWall) % 2 == 1 then return "east" end
end

function Switch.sprite(mount, on)
    return "zedcomm_devices_01_" .. ((offFrames[mount] or offFrames.north) + (on and 1 or 0))
end

function Switch.updateSprite(object, state)
    if not state then return end
    local sprite = getSprite(Switch.sprite(state.mount, state.on))
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
