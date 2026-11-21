package.path = "workshop/ZedComm/Contents/mods/ZedComm/42/media/lua/shared/?.lua;" .. package.path
require "ZedComm/InternalCircuit"
require "ZedComm/Network"
local Circuit, Packet = ZedComm.InternalCircuit, ZedComm.SignalModules.Packet
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local columns, rows = Circuit.dimensions("door")
check(columns == 6 and rows == 3, "shared board is 6x3")
local layout = Circuit.doorPreset()
local run, reason, board = Circuit.compilePackets(layout, "door", "basic")
assert(run, reason)
check(board.directions.lock == "sink" and board.directions.open == "sink"
    and board.directions.lockAction == nil and board.actions.lockAction, "only two physical input jacks")
local outputs = run({ lock = Packet.basic(1), open = Packet.basic(0) })
check(outputs.lockAction.value == 255 and outputs.openAction.value == 0, "direct actions are boolean")
check(not run({}).lockAction, "unavailable input remains unavailable")
layout.modules.wait = { kind = "wait", column = 2, row = 1, rotation = 0, seconds = 1 }
layout.modules.invert = { kind = "not", column = 3, row = 1, rotation = 0 }
layout.modules.gate = { kind = "and", column = 4, row = 1, rotation = 0 }
layout.links = {
    { from = "lock", output = "out", to = "lockAction", input = "in" },
    { from = "lock", output = "out", to = "wait", input = "in" },
    { from = "wait", output = "out", to = "invert", input = "in" },
    { from = "invert", output = "out", to = "gate", input = "b" },
    { from = "open", output = "out", to = "gate", input = "a" },
    { from = "gate", output = "out", to = "openAction", input = "in" },
}
local valid, rejection = Circuit.validate(layout, "door", "basic")
check(not valid and rejection == "Door logic requires Advanced Adapters", "Basic adapters reject programmable logic")
run, reason, board = Circuit.compilePackets(layout, "door", "advanced")
assert(run, reason)
check(board.dependencies.openAction.lock and board.dependencies.openAction.open, "action tracks both connected ancestors")
local environment = { now = 0, timers = {} }
local input = { lock = Packet.basic(0), open = Packet.basic(255) }
check(run(input, environment).openAction.value == 255, "example circuit permits opening while unlocked")
input.lock = Packet.basic(255)
check(run(input, environment).openAction.value == 255, "wait initially preserves opener ON")
environment.now = 1
outputs = run(input, environment)
check(outputs.openAction.value == 0 and outputs.lockAction.value == 255, "one second later opener closes and lock stays requested")
layout.modules.gate.row = 3
check(not Circuit.compilePackets(layout, "door", "advanced"), "bottom boundary uses actual row count")
layout.modules.gate.row = 1
layout.modules.extra = { kind = "inputExtension", column = 1, row = 3, rotation = 0 }
check(not Circuit.compilePackets(layout, "door", "advanced"), "door board cannot add physical jacks")
local network = ZedComm.Network.new()
check(network:addEndpoint("door", 1, 1, 0, "sink", nil, Circuit.DOOR_ID,
    { adapter = "advanced", circuit = Circuit.doorPreset() }), "door compiles in network model")
assert(network:addCable("a", 0, 1, 0)); assert(network:addCable("b", 2, 1, 0))
assert(network:link("a", "door", "lock")); assert(network:link("b", "door", "open"))
check(network:networkOf("door", "lock") ~= network:networkOf("door", "open"), "door jacks do not merge runs")
local restored = ZedComm.Network.new()
check(#restored:load(network:records()) == 0, "door board round trips through network records")
print(checks .. " checks, 0 failed")
