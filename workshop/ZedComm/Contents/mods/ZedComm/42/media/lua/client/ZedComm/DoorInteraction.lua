if isClient() or isServer() then return end

require "TimedActions/ISOpenCloseDoor"

local isValid = ISOpenCloseDoor.isValid
local complete = ISOpenCloseDoor.complete

function ISOpenCloseDoor:isValid()
    return not ZedComm.DeviceRuntime.blocksManualDoorOpening(self.item) and isValid(self)
end

function ISOpenCloseDoor:complete()
    if ZedComm.DeviceRuntime.blocksManualDoorOpening(self.item) then return false end
    return complete(self)
end
