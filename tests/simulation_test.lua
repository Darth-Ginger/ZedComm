-- Tests for the shared simulation entry point, run outside the game with a
-- Lua 5.1 interpreter (Kahlua follows 5.1). Stubs stand in for the game's
-- Events table and isClient/isServer, so the runner can be loaded once per
-- mode: singleplayer, multiplayer server and multiplayer client.
--
-- Usage: lua5.1 tests/simulation_test.lua   (from the repo root)

-- Regression: the game failed when the standard Lua next global was nil.
next = nil

local LUA = "workshop/ZedComm/Contents/mods/ZedComm/42/media/lua/"
package.path = LUA .. "shared/?.lua;" .. LUA .. "server/?.lua;" .. package.path

local failures, checks = 0, 0
local function check(cond, what)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL: " .. what)
    end
end

-- Load the runner as the game would in one mode, with fresh modules.
local function boot(client, server)
    ZedComm = nil
    package.loaded["ZedComm/Simulation"] = nil
    package.loaded["ZedComm/Dispatch"] = nil
    package.loaded["ZedComm/DeviceRuntime"] = nil
    package.loaded["ZedComm/NativeDevices"] = nil
    package.loaded["ZedComm/DeviceDefinitions"] = nil
    package.loaded["ZedComm/SignalModules"] = nil
    package.loaded["ZedComm/InternalCircuit"] = nil
    package.loaded["ZedComm/Devices/NetworkSwitch"] = nil
    package.loaded["ZedComm/Devices/PressureSensor"] = nil
    package.loaded["ZedComm/Devices/OccupancyPlate"] = nil
    package.loaded["ZedComm/Devices/WeightPlate"] = nil
    package.loaded["ZedComm/Devices/NumericDisplay"] = nil
    package.loaded["ZedComm/Devices/DebugByteSource"] = nil
    package.loaded["ZedComm/Devices/RelayLamp"] = nil
    package.loaded["ZedComm/Devices/Door"] = nil
    package.loaded["ZedComm/Devices/DoorContact"] = nil
    local handlers = {}
    Events = { OnTick = { Add = function(fn) handlers[#handlers + 1] = fn end },
        OnContainerUpdate = { Add = function() end } }
    isClient = function() return client end
    isServer = function() return server end
    local printed = {}
    local realPrint = print
    print = function(msg) printed[#printed + 1] = msg end
    dofile(LUA .. "server/ZedComm/SimulationRunner.lua")
    print = realPrint
    return handlers, printed
end

local function fireTick(handlers)
    for i = 1, #handlers do handlers[i]() end
end

-- Singleplayer: registered on OnTick with the Local adapter.
do
    local handlers, printed = boot(false, false)
    local Sim, Dispatch = ZedComm.Simulation, ZedComm.Dispatch
    check(#handlers == 1, "singleplayer registers one OnTick handler")
    check(Sim.getAdapter() == Dispatch.Local, "singleplayer uses the Local adapter")
    check(printed[1] and printed[1]:find("singleplayer", 1, true), "singleplayer logs its registration")

    local recomputed, delivered = {}, {}
    Sim.setRecompute(function(id)
        recomputed[id] = (recomputed[id] or 0) + 1
        return { type = "signal.basic", value = 255 }
    end)
    Dispatch.subscribe(function(id, value) delivered[id] = value end)

    fireTick(handlers)
    check(Sim.passes == 1 and Sim.processed == 0, "an idle tick runs the pass and recomputes nothing")

    Sim.markDirty("a"); Sim.markDirty("a"); Sim.markDirty("b")
    check(recomputed.a == nil, "marking never recomputes inside the event")
    fireTick(handlers)
    check(recomputed.a == 1 and recomputed.b == 1, "each marked network is recomputed once per pass")
    check(delivered.a.type == "signal.basic" and delivered.a.value == 255 and delivered.b.value == 255,
        "packets are delivered in the same pass")
    check(not Sim.hasPending(), "the pass clears the pending set")

    -- A mark made while the pass runs waits for the next tick.
    Sim.setRecompute(function(id)
        recomputed[id] = (recomputed[id] or 0) + 1
        if id == "c" then Sim.markDirty("c") end
        return { type = "signal.basic", value = 0 }
    end)
    Sim.markDirty("c")
    fireTick(handlers)
    check(recomputed.c == 1 and Sim.hasPending(), "a mark made during the pass waits for the next tick")
    fireTick(handlers)
    check(recomputed.c == 2, "the deferred mark runs on the following tick")
end

-- Multiplayer server: registered with the Server stub, which counts sends.
do
    local handlers = boot(false, true)
    local Sim, Dispatch = ZedComm.Simulation, ZedComm.Dispatch
    check(#handlers == 1, "server registers one OnTick handler")
    check(Sim.getAdapter() == Dispatch.Server, "server uses the Server adapter stub")
    Sim.setRecompute(function() return { type = "signal.basic", value = 1 } end)
    Sim.markDirty("net")
    fireTick(handlers)
    check(Dispatch.Server.sent == 1, "the pass sends through the dispatch adapter stub")
end

-- Multiplayer client: never runs the simulation.
do
    local handlers = boot(true, false)
    check(#handlers == 0, "a multiplayer client registers no OnTick handler")
end

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
