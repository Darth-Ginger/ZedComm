-- Draw the casing, digits and indicator as one floor sprite in singleplayer.
if isClient() or isServer() then return end

local definitionId = "ZedComm.NumericDisplay"
local spritePrefix = "zedcomm_devices_01_"
local casingName = spritePrefix .. "431"
local facePrefix = "zedcomm_display_01_"
local firstLegacyGlyph, lastLegacyGlyph = 432, 465
local active = setmetatable({}, { __mode = "k" })
local missing = {}

local function refresh(object, value, attached)
    if not object:getSquare() then
        active[object] = nil
        return
    end
    local name = casingName
    if attached then
        -- Frame 0 is signal loss. Valid byte values use frames 1 to 256.
        name = facePrefix .. (value == nil and 0 or value + 1)
    end
    if active[object] == name then return end

    local sprite = getSprite(name)
    if not sprite then
        if not missing[name] then
            missing[name] = true
            print("[ZedComm] missing display sprite " .. name)
        end
        return
    end
    if object:getSprite() ~= sprite then object:setSprite(sprite) end
    active[object] = attached and name or nil
end

local function removeLegacyGlyphs(object)
    local children = object:getAttachedAnimSprite()
    if not children then return end
    for i = children:size() - 1, 0, -1 do
        local sprite = children:get(i):getParentSprite()
        local name = sprite and sprite:getName()
        local frame = name and tonumber(name:match("^" .. spritePrefix .. "(%d+)$"))
        if frame and frame >= firstLegacyGlyph and frame <= lastLegacyGlyph then
            object:RemoveAttachedAnim(i)
        end
    end
end

local function refreshLoadedObject(object)
    local tag = object:hasModData() and object:getModData().zedcomm
    if type(tag) ~= "table" or tag.kind ~= "endpoint"
        or (tag.definitionId ~= definitionId and tag.definitionId ~= "ZedComm.AdvancedDisplay") then return end
    active[object] = nil
    removeLegacyGlyphs(object)
    local runtime = ZedComm and ZedComm.DeviceRuntime
    if runtime then
        local value, _, attached = runtime.getDisplay(object)
        refresh(object, value, attached)
    else
        refresh(object, nil, false)
    end
end

Events.OnObjectAdded.Add(refreshLoadedObject)
Events.LoadGridsquare.Add(function(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do refreshLoadedObject(objects:get(i)) end
end)
Events.OnTick.Add(function()
    local runtime = ZedComm and ZedComm.DeviceRuntime
    if not runtime then return end
    runtime.forEachDisplay(function(object, value) refresh(object, value, true) end)
    for object in pairs(active) do
        local _, _, attached = runtime.getDisplay(object)
        if not attached then refresh(object, nil, false) end
    end
end)
