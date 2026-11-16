-- Tests for the network model (shared/ZedComm/Network.lua), run outside the
-- game with a Lua 5.1 interpreter.
--
-- Usage: lua5.1 tests/network_test.lua   (from the repo root)

local LUA = "workshop/ZedComm/Contents/mods/ZedComm/42/media/lua/"
package.path = LUA .. "shared/?.lua;" .. package.path

local failures, checks = 0, 0
local function check(cond, what)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL: " .. what)
    end
end

ZedComm = nil
local Network = require("ZedComm/Network")
local Packet = ZedComm.SignalModules.Packet

-- A stub simulation that records dirty marks.
local function stubSim()
    local sim = { marks = {} }
    function sim.markDirty(id) sim.marks[id] = (sim.marks[id] or 0) + 1 end
    function sim.setRecompute(fn) sim.recompute = fn end
    function sim.clear() sim.marks = {} end
    function sim.count()
        local n = 0
        for _ in pairs(sim.marks) do n = n + 1 end
        return n
    end
    return sim
end

-- The acceptance layout: a sensor, a cable run with a bend, a display.
--
--   S(0,0) - c1(1,0) - c2(2,0)
--                        |
--                      c3(2,1)
--                        |
--                      D(2,2)
local function layout()
    local net = Network.new()
    assert(net:addEndpoint("S", 0, 0, 0, "source"))
    assert(net:setPacket("S", Packet.basic(0)))
    assert(net:addEndpoint("D", 2, 2, 0, "sink"))
    assert(net:addCable("c1", 1, 0, 0))
    assert(net:addCable("c2", 2, 0, 0))
    assert(net:addCable("c3", 2, 1, 0))
    return net
end

local function wire(net)
    assert(net:link("c1", "S"))
    assert(net:link("c1", "c2"))
    assert(net:link("c2", "c3"))
    assert(net:link("c3", "D"))
end

-- A run across several squares with a bend carries the byte end to end.
do
    local net = layout()
    wire(net)
    local id = net:networkOf("S")
    check(id ~= nil and id == net:networkOf("D"), "sensor and display share a network across a bent run")
    check(net:networkOf("c2") == id, "every cable piece is on the run's network")
    check(net:status(id) == Network.OK, "a run with one source is OK")
    check(Packet.basicValue(net:recompute(id)) == 0, "a clear sensor delivers valid zero, not disconnected")
    net:setPacket("S", Packet.basic(255))
    check(Packet.basicValue(net:recompute(id)) == 255, "an occupied sensor delivers 255")
    net:setPacket("S", Packet.basic(170))
    check(Packet.basicValue(net:recompute(id)) == 170, "mixed byte patterns pass unchanged")
    local sinks = net:sinksOf(id)
    check(#sinks == 1 and sinks[1] == "D", "the display is the run's only receiver")
    check(net:networkCount() == 1, "one connected run is one network")
end

-- Adjacency alone never connects.
do
    local net = layout()
    -- Every piece sits next to the next one, but nothing is linked.
    check(net:networkOf("S") ~= net:networkOf("D"), "unlinked neighbours are separate networks")
    check(net:recompute(net:networkOf("D")) == nil, "an unlinked display is disconnected")
    check(net:status(net:networkOf("D")) == Network.NO_SOURCE, "an unlinked display has no source")
    assert(net:link("c1", "c2")); assert(net:link("c2", "c3"))
    check(net:networkOf("c3") ~= net:networkOf("D"), "a cable ending next to the display does not reach its port")
    assert(net:link("c3", "D"))
    check(net:networkOf("c3") == net:networkOf("D"), "an explicit termination reaches the port")
end

-- Link rules.
do
    local net = Network.new()
    net:addCable("a", 0, 0, 0)
    net:addCable("diag", 1, 1, 0)
    net:addCable("far", 2, 0, 0)
    net:addCable("up", 0, 1, 1)
    net:addCable("b", 1, 0, 0)
    net:addCable("c", 0, 1, 0)
    net:addCable("d", -1, 0, 0)
    net:addEndpoint("E", 0, 0, 0, "sink")
    net:addEndpoint("F", 3, 0, 0, "sink")
    check(not net:link("a", "diag"), "cables on diagonal squares cannot link")
    check(not net:link("a", "far"), "cables two squares apart cannot link")
    check(not net:link("a", "up"), "cables on different levels cannot link")
    check(not net:link("a", "a"), "a cable cannot link to itself")
    check(not net:link("E", "a"), "a link starts from a cable")
    check(not net:link("a", "F"), "an endpoint out of reach cannot be terminated")
    check(not net:link("a", "E", "nope"), "an unknown port is refused")
    check(net:link("a", "E"), "a cable can terminate on an endpoint on its own square")
    check(not net:link("b", "E"), "a port holds one cable")
    check(net:link("a", "b"), "a cable's second end links")
    check(not net:link("a", "c"), "a cable has only two ends")
    check(not net:link("a", "b"), "the same link is refused twice")
    local ok, err = net:link("a", "d")
    check(not ok and err == "cable has no free end", "a full cable reports why it refused")
end

-- One source per network (MVP: reject unsupported arrangements).
do
    local net = Network.new()
    net:addEndpoint("S1", 0, 0, 0, "source")
    net:addEndpoint("S2", 3, 0, 0, "source")
    net:addCable("c1", 1, 0, 0)
    net:addCable("c2", 2, 0, 0)
    assert(net:link("c1", "S1"))
    assert(net:link("c2", "S2"))
    local ok, err = net:link("c1", "c2")
    check(not ok and err == "would join two sources", "joining two sourced runs is refused")
    assert(net:unlink("c2", "S2"))
    check(net:link("c1", "c2"), "the join works once one source is gone")
    local ok2, err2 = net:link("c2", "S2")
    check(not ok2 and err2 == "network already has a source", "a second source cannot terminate on a run")
end

-- Removing a cable segment changes reachability without duplicates.
do
    local net = layout()
    wire(net)
    net:setPacket("S", Packet.basic(255))
    check(net:networkCount() == 1, "the wired layout starts as one network")
    assert(net:remove("c2"))
    check(net:networkOf("S") ~= net:networkOf("D"), "removing a middle segment splits the run")
    check(net:recompute(net:networkOf("D")) == nil, "the cut-off display is disconnected")
    check(Packet.basicValue(net:recompute(net:networkOf("S"))) == 255, "the sensor side still carries its byte")
    check(net:networkCount() == 2, "the split leaves exactly two networks")
    check(not net:link("c1", "c3"), "the gap cannot be bridged without a cable")
    assert(net:addCable("c2", 2, 0, 0))
    assert(net:link("c1", "c2")); assert(net:link("c2", "c3"))
    check(Packet.basicValue(net:recompute(net:networkOf("D"))) == 255, "relaying the segment restores the current value with no new toggle")
    check(net:networkCount() == 1, "the repaired run is one network again")
    assert(net:unlink("c2", "c3"))
    check(net:networkOf("S") ~= net:networkOf("D"), "unlinking breaks reachability like removal")
end

-- Picking up equipment leaves the cable run placed (ADR-304).
do
    local net = layout()
    wire(net)
    assert(net:remove("D"))
    check(net.pieces.c3 ~= nil and net.pieces.c3.links.c2 == true, "the run stays placed after the display is picked up")
    check(net.pieces.c3.links.D == nil, "the picked-up display's termination is gone")
    check(net:networkOf("c3") == net:networkOf("S"), "the rest of the run keeps its network")
    assert(net:addEndpoint("D", 3, 1, 0, "sink"))
    check(net:networkOf("D") ~= net:networkOf("S"), "placing the display again does not reconnect it")
    check(net:link("c3", "D"), "the free cable end can be terminated again")
    check(net:networkOf("D") == net:networkOf("S"), "the reconnected display is back on the run")
end

-- Records: rebuild from saved state, without duplicate registration.
do
    local net = layout()
    wire(net)
    net:setPacket("S", Packet.basic(85))
    local records = net:records()
    check(#records == 5, "one record per piece")

    local loaded = Network.new()
    local dropped = loaded:load(records)
    check(#dropped == 0, "a clean save loads with nothing dropped")
    check(loaded:networkOf("S") == loaded:networkOf("D"), "connectivity is derived again from the records")
    check(net:record("S").packet == nil and net:record("S").value == nil
        and loaded:recompute(loaded:networkOf("D")) == nil, "the live packet is absent from saved records")
    assert(loaded:setPacket("S", Packet.basic(85)))
    check(Packet.basicValue(loaded:recompute(loaded:networkOf("D"))) == 85,
        "the restored circuit carries the source's first live sample")

    local again = loaded:load(records)
    check(#again == 0, "loading the same records twice reports nothing")
    local n = 0
    for _ in pairs(loaded.pieces) do n = n + 1 end
    check(n == 5 and loaded:networkCount() == 1, "loading twice registers nothing twice")
    local free = 0
    for _ in pairs(loaded.pieces.c2.links) do free = free + 1 end
    check(free == 2, "loading twice adds no extra links")

    -- A link only one side remembers is dropped, not half-made.
    for i = 1, #records do
        if records[i].id == "D" then records[i].ports.signal = false end
    end
    local partial = Network.new()
    local d = partial:load(records)
    check(#d == 1 and string.find(d[1], "one-sided", 1, true), "a one-sided link is dropped and reported")
    check(partial:networkOf("D") ~= partial:networkOf("S"), "the dropped link does not connect")

    local clash = Network.new()
    clash:addCable("S", 9, 9, 0)
    local c = clash:load(net:records())
    check(#c > 0, "a record whose id is already another piece is reported")
end

-- Dirty marking: changes mark networks, never recompute (ADR-305).
do
    local sim = stubSim()
    local net = Network.new()
    net:attach(sim)
    check(type(sim.recompute) == "function", "attach registers the recompute step")
    net:addEndpoint("S", 0, 0, 0, "source")
    net:addEndpoint("D", 2, 2, 0, "sink")
    net:addCable("c1", 1, 0, 0); net:addCable("c2", 2, 0, 0); net:addCable("c3", 2, 1, 0)
    wire(net)
    assert(net:setPacket("S", Packet.basic(0)))
    sim.clear()

    net:setPacket("S", Packet.basic(0))
    check(sim.count() == 0, "an unchanged value marks nothing")
    net:setPacket("S", Packet.basic(255))
    check(sim.marks[net:networkOf("S")] == 1 and sim.count() == 1, "a value change marks only its network")

    sim.clear()
    net:remove("c2")
    check(sim.marks[net:networkOf("S")] and sim.marks[net:networkOf("D")], "a cut marks both halves")
    check(sim.recompute(net:networkOf("D")) == nil, "the recompute step reports the cut side disconnected")

    sim.clear()
    net:addCable("c2", 2, 0, 0)
    net:link("c1", "c2"); net:link("c2", "c3")
    check(sim.marks[net:networkOf("D")], "a repair marks the joined network")
    check(Packet.basicValue(sim.recompute(net:networkOf("D"))) == 255, "the recompute step delivers the current byte")
end

-- ADR-309 packet ownership, validation and semantic change detection.
do
    local sim, net = stubSim(), layout()
    net:attach(sim)
    wire(net)
    local id = net:networkOf("D")
    local packet = { type = "signal.advanced", value = { kind = "weight", amount = 1150, unit = "kg" },
        basicValue = 115 }
    assert(net:setPacket("S", packet))
    check(net:recompute(id).value.amount == 1150, "the wire delivers a complete advanced payload")
    packet.value.amount, packet.basicValue = 0, 0
    local read = net:recompute(id)
    read.value.amount = 0
    local current = net:recompute(id)
    check(current.value.amount == 1150 and current.basicValue == 115,
        "mutation of a published packet or recompute result cannot change the held packet")

    sim.clear()
    assert(net:setPacket("S", current))
    check(sim.count() == 0, "equal packets in fresh tables do not dirty the network")
    current.value.amount = 1151
    assert(net:setPacket("S", current))
    check(sim.marks[id] == 1 and net:recompute(id).value.amount == 1151,
        "a payload change dirties the network even with the same fallback")
    check(not net:setPacket("S", { type = "signal.basic", value = 256 })
        and net:recompute(id).value.amount == 1151, "malformed basic packets leave the prior signal intact")
    check(not net:setPacket("S", { type = "signal.advanced",
        value = { kind = "weight", amount = math.huge, unit = "kg" } }),
        "nonfinite weight payloads are rejected")
    assert(net:setPacket("S", nil))
    check(Packet.basicValue(net:recompute(id)) == nil and net:status(id) == Network.NO_SOURCE,
        "clearing a packet makes the attached network unavailable")
end

-- End to end with the real simulation pass and local dispatch.
do
    ZedComm.Simulation = nil
    package.loaded["ZedComm/Simulation"] = nil
    package.loaded["ZedComm/Dispatch"] = nil
    local Sim = require("ZedComm/Simulation")
    local Dispatch = require("ZedComm/Dispatch")
    Sim.setAdapter(Dispatch.Local)

    local net = layout()
    net:attach(Sim)
    wire(net)
    local shown = {}
    Dispatch.subscribe(function(networkId, packet)
        local value = Packet.basicValue(packet)
        local sinks = net:sinksOf(networkId)
        for i = 1, #sinks do shown[sinks[i]] = value == nil and "off" or value end
    end)
    Sim.tick()
    check(shown.D == 0, "after wiring, the display shows valid zero")
    net:setPacket("S", Packet.basic(255))
    Sim.tick()
    check(shown.D == 255, "a sensor change reaches the display in one pass")
    net:remove("c3")
    Sim.tick()
    check(shown.D == "off", "a cut turns the display off")
    net:addCable("c3", 2, 1, 0)
    net:link("c2", "c3"); net:link("c3", "D")
    Sim.tick()
    check(shown.D == 255, "reconnecting adopts the current value")
end

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
