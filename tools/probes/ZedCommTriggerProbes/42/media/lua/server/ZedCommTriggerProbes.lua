if isClient() or isServer() then return end

require "ZedComm/DeviceDefinitions"

local Definitions = ZedComm.DeviceDefinitions
local buttonId, tripwireId = "ZedCommProbe.MomentaryButton", "ZedCommProbe.Tripwire"
local now, byObject = 0, setmetatable({}, { __mode = "k" })

local function getState(object)
    local state = byObject[object]
    if not state then
        state = { expires = 0 }
        byObject[object] = state
    end
    return state
end

local function press(state)
    if now >= state.expires then state.expires = now + 1 end
end

local function occupied(square)
    local actors = square:getMovingObjects()
    for i = 0, actors:size() - 1 do
        local actor = actors:get(i)
        if (instanceof(actor, "IsoZombie")
            or (instanceof(actor, "IsoPlayer") and not instanceof(actor, "IsoAnimal") and not actor:getVehicle()))
            and not actor:isDead() then
            return true
        end
    end
    return false
end

local function register(id)
    assert(Definitions.register({
        id = id,
        role = "source",
        ports = { "signal" },
        match = function(object, context) return context.getDefinitionId(object) == id end,
        sample = function(object)
            local state = getState(object)
            if id == tripwireId then
                local crossed = occupied(object:getSquare())
                if crossed and state.clear then press(state) end
                state.clear = not crossed
            end
            return now < state.expires and 255 or 0
        end,
    }))
end

register(buttonId)
register(tripwireId)

Events.OnTick.Add(function()
    local elapsed = getGameTime():getRealworldSecondsSinceLastUpdate()
    if elapsed > 0 then now = now + elapsed end
end)

Events.OnObjectLeftMouseButtonDown.Add(function(object)
    local tag = Definitions.readFixtureTag(object)
    local player = getSpecificPlayer(0)
    if tag and tag.definitionId == buttonId and player and not getCell():getDrag(0)
        and ZedComm.PlayerPlacement.canReach(player, object:getSquare(), object) then
        press(getState(object))
    end
end)

ZedCommTriggerProbes = {}
function ZedCommTriggerProbes.place(kind, square)
    local id = kind == "button" and buttonId or kind == "tripwire" and tripwireId
    assert(id and square, "Choose button or tripwire and a loaded square.")
    local label = kind == "button" and "Momentary Button Probe" or "Tripwire Probe"
    local object = IsoObject.new(square, "zedcomm_devices_01_431", label)
    local tag = string.format("%s-%d-%d-%d", kind, square:getX(), square:getY(), square:getZ())
    local registry = ZedComm.Registry.instance
    assert(not registry.network.pieces[tag], "A probe of this kind is already on that square.")
    object:getModData().zedcomm = { id = tag, kind = "endpoint", definitionId = id }
    square:AddTileObject(object)
    triggerEvent("OnObjectAdded", object)
    assert(registry.network.pieces[tag], "The probe did not register.")
    return tag
end
