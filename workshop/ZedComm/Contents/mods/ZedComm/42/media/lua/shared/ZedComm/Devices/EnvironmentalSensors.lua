require "ZedComm/DeviceDefinitions"

local Definitions = ZedComm.DeviceDefinitions
local Sensors = {
    CLOCK = "ZedComm.TimeOfDaySensor",
    POWER = "ZedComm.PowerSensor",
    DAYLIGHT = "ZedComm.DaylightSensor",
    RAIN = "ZedComm.RainIntensitySensor",
}

local function unit(value)
    if type(value) == "number" and value - value == 0 then
        return math.max(0, math.min(1, value))
    end
end

local function toByte(value)
    local level = unit(value)
    return level and math.floor(level * 255 + 0.5)
end

function Sensors.isExposed(square)
    return square and square:isOutside() and not square:haveRoofFull()
end

function Sensors.rainIntensity(square, climate)
    if not square or not climate then return nil end
    if not Sensors.isExposed(square) or climate:getPrecipitationIsSnow() then return 0 end
    return unit(climate:getRainIntensity())
end

function Sensors.parseTime(text)
    local hours, minutes = tostring(text):match("^%s*(%d%d):(%d%d)%s*$")
    hours, minutes = tonumber(hours), tonumber(minutes)
    if hours and hours < 24 and minutes and minutes < 60 then return hours * 60 + minutes end
end

function Sensors.formatTime(minutes)
    return string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
end

function Sensors.scheduleValue(minute, first, last)
    if first == last then return 0 end
    local offset = (minute - first) % 1440
    return offset < (last - first) % 1440 and 255 or 0
end

function Sensors.configureSchedule(registry, id, input)
    local piece = registry.network.pieces[id]
    if not piece or piece.definitionId ~= Sensors.CLOCK then return false, "That is not a Time-of-day Sensor." end
    local first, last = tostring(input):match("^([^,]+),([^,]+)$")
    first, last = Sensors.parseTime(first), Sensors.parseTime(last)
    if not first or not last then return false, "Enter two times in HH:MM, HH:MM format." end
    local state = registry.network:record(id).state or {}
    state.startMinute, state.endMinute = first, last
    return registry:setDeviceState(id, state)
end

local function register(id, sample)
    local ok, reason = Definitions.register({
        id = id,
        role = "source",
        ports = { "signal" },
        match = function(object, context) return context.getDefinitionId(object) == id end,
        sample = sample,
        sampleInterval = 1,
    })
    if not ok then error(id .. ": " .. reason) end
end

register(Sensors.CLOCK, function(_, context, state)
    local minute = context.getClockMinute()
    if minute ~= nil then
        return Sensors.scheduleValue(minute, state and state.startMinute or 0, state and state.endMinute or 0)
    end
end)

register(Sensors.POWER, function(object, context)
    return context.isSensorPowered(object) and 255 or 0
end)

register(Sensors.DAYLIGHT, function(object, context)
    if not Sensors.isExposed(object:getSquare()) then return 0 end
    local climate = context.getClimate()
    return climate and toByte(climate:getDayLightStrength())
end)

register(Sensors.RAIN, function(object, context)
    return toByte(Sensors.rainIntensity(object:getSquare(), context.getClimate()))
end)

ZedComm.EnvironmentalSensors = Sensors
return Sensors
