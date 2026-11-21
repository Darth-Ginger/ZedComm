require "ZedComm/Devices/Door"

local Door = ZedComm.Door
local Contact = { ID = "ZedComm.DoorContact", WINDOW_ID = "ZedComm.WindowContact" }

local function windowHost(object)
    return object and instanceof(object, "IsoWindow") and object:getSquare() ~= nil
end

local function windowIntact(window)
    return not window:isDestroyed() and not window:isSmashed() and not window:isGlassRemoved()
end

Contact.profiles = {
    [Contact.ID] = { name = "Door Contact", matchHost = Door.isEligible,
        canFit = Door.isEligible, prefix = "zedcomm_contact_01_",
        isClosed = function(door) return not door:isOpen() end },
    [Contact.WINDOW_ID] = { name = "Window Contact", matchHost = windowHost,
        canFit = function(window) return windowHost(window) and windowIntact(window) end,
        prefix = "zedcomm_window_contact_01_",
        isClosed = function(window) return windowIntact(window) and not window:isOpen() end },
}

function Contact.host(object)
    local square = object:getSquare()
    local tag = object:hasModData() and object:getModData().zedcomm
    local profile = tag and Contact.profiles[tag.definitionId]
    if not square or not profile then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local candidate = objects:get(i)
        if profile.matchHost(candidate) and candidate:hasModData()
            and candidate:getModData().zedcommContact == tag.id then return candidate end
    end
end

function Contact.canFit(object, id)
    local profile = Contact.profiles[id]
    return profile and profile.canFit(object) and not object:getModData().zedcommContact
end

local function register(id, profile)
    local ok, reason = ZedComm.DeviceDefinitions.register({
        id = id, role = "source", ports = { "signal" },
        match = function(object, context) return context.getDefinitionId(object) == id end,
        sample = function(object)
            local host = Contact.host(object)
            if host and profile.canFit(host) then return profile.isClosed(host) and 255 or 0 end
        end,
    })
    if not ok then error(id .. ": " .. reason) end
end
for id, profile in pairs(Contact.profiles) do register(id, profile) end
ZedComm.DoorContact = Contact
return Contact
