-- Keep readouts on the display's floor sprite so they share its occlusion.
if isClient() or isServer() then return end

if not ZedComm.ModuleVisuals then require "ZedComm/ModuleVisuals" end

local definitionId = "ZedComm.NumericDisplay"
local spritePrefix = "zedcomm_devices_01_"
local casingName = spritePrefix .. "431"
local facePrefix = "zedcomm_display_01_"
local weightPrefix = "zedcomm_weight_face_01_"
local glyphsPerSlot, faceSlots = 12, 5
local decimalFrame, indicatorFrame = 60, 61
local active = setmetatable({}, { __mode = "k" })
local missing = {}

local function weightFace(amount)
    if amount >= 99999.5 then return "HI" end
    local tenths = math.floor(amount * 10 + 0.5)
    if tenths < 100000 and tenths % 10 ~= 0 then
        return tostring(math.floor(tenths / 10)) .. "." .. tostring(tenths % 10)
    end
    return tostring(math.floor(amount + 0.5))
end

local function isWeightGlyph(name)
    return name and name:sub(1, #weightPrefix) == weightPrefix
end

local function changeWeightGlyphs(object, text, lit)
    local removed = ZedComm.ModuleVisuals.setAttachment(object, nil, isWeightGlyph)
    if not text then
        if removed then object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_ADD) end
        return
    end
    local digits, decimal = text:gsub("%.", "")
    local slot = faceSlots - #digits
    for digit in digits:gmatch(".") do
        local index = tonumber(digit) or (digit == "H" and 10 or 11)
        local sprite = getSprite(weightPrefix .. (slot * glyphsPerSlot + index))
        if sprite then object:addAttachedAnimSprite(sprite) end
        slot = slot + 1
    end
    if decimal > 0 then
        local sprite = getSprite(weightPrefix .. decimalFrame)
        if sprite then object:addAttachedAnimSprite(sprite) end
    end
    if lit then
        local sprite = getSprite(weightPrefix .. indicatorFrame)
        if sprite then object:addAttachedAnimSprite(sprite) end
    end
    object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_ADD)
end

local function refresh(object, value, attached, weight)
    if not object:getSquare() then
        active[object] = nil
        return
    end
    local name = casingName
    local face = weight and weightFace(weight)
    local lit = weight and weight > 0
    if attached and not face then
        -- Frame 0 is signal loss. Valid byte values use frames 1 to 256.
        name = facePrefix .. (value == nil and 0 or value + 1)
    end
    local key = face and weightPrefix .. face .. (lit and ":on" or "") or name
    local previous = active[object]
    if previous == key then return end

    local sprite = getSprite(name)
    if not sprite then
        if not missing[name] then
            missing[name] = true
            print("[ZedComm] missing display sprite " .. name)
        end
        return
    end
    if object:getSprite() ~= sprite then object:setSprite(sprite) end
    if face or isWeightGlyph(previous) then changeWeightGlyphs(object, face, lit) end
    active[object] = attached and key or nil
end

local function refreshLoadedObject(object)
    local tag = object:hasModData() and object:getModData().zedcomm
    if type(tag) ~= "table" or tag.kind ~= "endpoint"
        or (tag.definitionId ~= definitionId and tag.definitionId ~= "ZedComm.AdvancedDisplay") then return end
    ZedComm.ModuleVisuals.setAttachment(object, nil, isWeightGlyph)
    active[object] = nil
    local runtime = ZedComm and ZedComm.DeviceRuntime
    if runtime then
        local value, _, attached, packet = runtime.getDisplay(object)
        local weight = packet and packet.type == "signal.advanced" and packet.value.amount
        refresh(object, value, attached, weight)
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
    runtime.forEachDisplay(function(object, value, _, weight) refresh(object, value, true, weight) end)
    runtime.forEachTestSource(function(object, value) refresh(object, value, true) end)
    for object in pairs(active) do
        local _, _, attached = runtime.getDisplay(object)
        if not attached and runtime.getTestSourceValue(object) == nil then refresh(object, nil, false) end
    end
end)
