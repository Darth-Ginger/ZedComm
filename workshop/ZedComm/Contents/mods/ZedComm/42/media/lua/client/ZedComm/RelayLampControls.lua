-- The vanilla context menu and keyboard prompt queue this same action.
if isClient() or isServer() then return end
require "TimedActions/ISToggleLightAction"
require "ZedComm/Devices/RelayLamp"

if ISToggleLightAction.zedcommRelayGuard then return end
ISToggleLightAction.zedcommRelayGuard = true
local valid, complete = ISToggleLightAction.isValid, ISToggleLightAction.complete
local Relay = ZedComm.RelayLamp

function ISToggleLightAction:isValid()
    if Relay.isWired(self.object) then return false end
    return valid(self)
end

function ISToggleLightAction:complete()
    -- Recheck after queuing in case a wire was attached in the meantime.
    if Relay.isWired(self.object) then return true end
    return complete(self)
end
