-- Independent source fixture owned by a native door on the same square.
require "ZedComm/Devices/Door"
local Contact = { ID = "ZedComm.DoorContact", ITEM = "ZedComm.DoorContact" }

function Contact.host(object)
    local square = object:getSquare()
    local tag = object:hasModData() and object:getModData().zedcomm
    if not square or not tag then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local candidate = objects:get(i)
        if candidate:hasModData() and candidate:getModData().zedcommContact == tag.id
            and ZedComm.Door.isEligible(candidate) then return candidate end
    end
end

local ok, reason = ZedComm.DeviceDefinitions.register({
    id = Contact.ID, role = "source", ports = { "signal" },
    match = function(object, context) return context.getDefinitionId(object) == Contact.ID end,
    sample = function(object)
        local door = Contact.host(object)
        if door then return door:isOpen() and 255 or 0 end
    end,
})
if not ok then error(Contact.ID .. ": " .. reason) end
ZedComm.DoorContact = Contact
return Contact
