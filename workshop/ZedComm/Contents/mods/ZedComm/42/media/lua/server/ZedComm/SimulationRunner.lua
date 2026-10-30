-- Registers the shared simulation pass on Events.OnTick (ADR-305).
--
-- server/ scripts load in singleplayer and on a multiplayer server. A
-- multiplayer client must not run the simulation, so it returns early; the
-- server picks the Server adapter and singleplayer the Local one. OnTick does
-- not fire while the game is paused, so the simulation freezes with it.

require "ZedComm/Simulation"
require "ZedComm/Dispatch"

if isClient() then return end

local Simulation = ZedComm.Simulation
local Dispatch = ZedComm.Dispatch
local adapter = isServer() and Dispatch.Server or Dispatch.Local
Simulation.setAdapter(adapter)

local announced = false
local function onTick()
    Simulation.tick()
    if not announced then
        announced = true
        print("[ZedComm] simulation pass running (" .. adapter.name .. ")")
    end
end

Events.OnTick.Add(onTick)
print("[ZedComm] simulation entry point registered (" .. adapter.name .. ")")
