-- ZedComm dispatch adapters (ADR-302): where the simulation pass sends each
-- recomputed network's packet. The pass itself is the same in every mode.
--
--   Local  - singleplayer: delivered inside the game process, this tick.
--   Server - multiplayer server: delivered on the server and counted.
--            Nothing is sent to clients (ADR-305, step 7).

ZedComm = ZedComm or {}

local Dispatch = {}

-- Subscribers are called as fn(networkId, packet).
local listeners = {}

function Dispatch.subscribe(fn) listeners[#listeners + 1] = fn end

local function notify(networkId, packet)
    for i = 1, #listeners do listeners[i](networkId, packet) end
end

Dispatch.Local = {
    name = "singleplayer",
    deliver = notify,
}

Dispatch.Server = {
    name = "server",
    sent = 0,
    deliver = function(networkId, packet)
        Dispatch.Server.sent = Dispatch.Server.sent + 1
        notify(networkId, packet)
    end,
}

-- For tests only.
function Dispatch.reset()
    listeners = {}
    Dispatch.Server.sent = 0
end

ZedComm.Dispatch = Dispatch
return Dispatch
