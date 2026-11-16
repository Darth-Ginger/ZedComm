-- Render a clip-on module using the wire attached to its port.
require "ZedComm/WireShape"

local ModuleVisuals = {}
local prefix = "zedcomm_devices_01_"
local floorStart, mountStart = 14, 32
local directionFrame = { [0] = 1, [1] = 2, [2] = 3, [4] = 4, [8] = 5 }
local missing = {}

local function isHousing(name)
    local index = name and tonumber(string.match(name, "^zedcomm_devices_01_(%d+)$"))
    return index and ((index >= 14 and index <= 19) or (index >= 26 and index < 140))
end

local function firstFrame(object)
    local sprite = object:getSprite()
    local texture = sprite and sprite:getTextureForCurrentFrame(object:getDir())
    if not texture then return floorStart end
    local x = texture:getOffsetX() + texture:getWidth() / 2
    local bottom = texture:getOffsetY() + texture:getHeight()
    if bottom >= 208 and math.abs(x - 64) <= 8 and object:getRenderYOffset() <= 0 then
        return floorStart
    end

    -- Child sprites inherit the lamp's furniture offset. Select a compact
    -- mount near the base of its unraised texture in Build 42 tile pixels.
    local column = math.max(0, math.min(2, math.floor((x - 52 + 6) / 12)))
    local row = math.max(0, math.min(5, math.floor((bottom - 152 + 8) / 16)))
    return mountStart + (row * 3 + column) * 6
end

function ModuleVisuals.refresh(object, network, piece, port)
    local direction = ZedComm.WireShape.portDirection(network, piece, port)
    local name = prefix .. (firstFrame(object) + (directionFrame[direction] or 0))
    local sprite = getSprite(name)
    if not sprite then
        if not missing[name] then
            missing[name] = true
            print("[ZedComm] missing module housing sprite " .. name)
        end
        return
    end
    -- Preserve the fixture's own attachments and replace only our housing.
    local kept = false
    local children = object:getAttachedAnimSprite()
    if children then
        for i = children:size() - 1, 0, -1 do
            local parent = children:get(i):getParentSprite()
            local current = parent and parent:getName()
            if isHousing(current) then
                if current == name and not kept then
                    kept = true
                else
                    object:RemoveAttachedAnim(i)
                end
            end
        end
    end
    if not kept then object:addAttachedAnimSprite(sprite) end
end

ZedComm.ModuleVisuals = ModuleVisuals
return ModuleVisuals
