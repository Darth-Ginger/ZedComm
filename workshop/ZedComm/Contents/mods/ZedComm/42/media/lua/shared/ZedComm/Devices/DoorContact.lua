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
    [Contact.ID] = { name = "Door Contact", edge = true, matchHost = Door.isEligible,
        canFit = Door.isEligible, prefix = "zedcomm_contact_01_",
        isClosed = function(door) return not door:isOpen() end },
    [Contact.WINDOW_ID] = { name = "Window Contact", edge = true, matchHost = windowHost,
        canFit = function(window) return windowHost(window) and windowIntact(window) end,
        prefix = "zedcomm_window_contact_01_",
        isClosed = function(window) return windowIntact(window) and not window:isOpen() end },
}

function Contact.host(object, edgeOnly)
    local square = object:getSquare()
    local tag = object:hasModData() and object:getModData().zedcomm
    local profile = tag and Contact.profiles[tag.definitionId]
    if not square or not profile or (edgeOnly and not profile.edge) then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local candidate = objects:get(i)
        if candidate:hasModData() and candidate:getModData().zedcommContact == tag.id
            and profile.matchHost(candidate) then return candidate end
    end
end

function Contact.fixtureForHost(host)
    local id = host:hasModData() and host:getModData().zedcommContact
    local square = id and host:getSquare()
    if not square then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local fixture = objects:get(i)
        local tag = ZedComm.DeviceDefinitions.readFixtureTag(fixture)
        if tag and tag.id == id and Contact.profiles[tag.definitionId] then return fixture, id end
    end
end

function Contact.canFit(object, id)
    local profile = Contact.profiles[id]
    if not profile or not profile.canFit(object) then return false end
    if not object:getModData().zedcommContact then return true end
    -- Vanilla moveables can copy the old host marker before removing its fixture.
    return not profile.edge and not Contact.fixtureForHost(object)
end

function Contact.register(id, profile)
    local ok, reason = ZedComm.DeviceDefinitions.register({
        id = id, role = "source", ports = { "signal" },
        match = function(object, context) return context.getDefinitionId(object) == id end,
        sample = function(object, context, state)
            local host = Contact.host(object)
            if not host then return nil end
            if profile.sample then return profile.sample(host, context, state) end
            if profile.canFit(host) then return profile.isClosed(host) and 255 or 0 end
        end,
    })
    if not ok then error(id .. ": " .. reason) end
    Contact.profiles[id] = profile
end
for id, profile in pairs(Contact.profiles) do Contact.register(id, profile) end
ZedComm.DoorContact = Contact
return Contact
