local shared = "workshop/ZedComm/Contents/mods/ZedComm/42/media/lua/shared/"
package.path = shared .. "?.lua;" .. package.path
next = nil
require "ZedComm/InternalCircuit"
local Circuit = ZedComm.InternalCircuit
local packet = ZedComm.SignalModules.Packet
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

local function compileBytes(layout, cabinet, adapter)
    local evaluate, reason, board = Circuit.compilePackets(layout, cabinet, adapter)
    if not evaluate then return nil, reason end
    return function(inputs)
        local packets, outputs = {}, {}
        for id, value in pairs(inputs) do packets[id] = packet.basic(value) end
        for id, output in pairs(evaluate(packets)) do outputs[id] = packet.basicValue(output) end
        return outputs
    end, nil, board
end

local state = Circuit.thresholdPreset()
check(Circuit.validate(state) == true, "lamp layout validates without an evaluator")
local run = assert(Circuit.compile(state))
check(run(8) == 0 and run(50) == 255 and run(115) == 255, "threshold is inclusive")
check(run(nil) == nil and run(0) == 0, "missing input is distinct from zero")
state.modules.threshold.threshold = 0
check(assert(Circuit.compile(state))(0) == 255, "zero can satisfy a zero threshold")
state.modules.threshold.threshold = 50
state.links[2] = nil
check(assert(Circuit.compile(state))(115) == nil, "an incomplete layout is valid with unavailable output")
state = Circuit.thresholdPreset()
state.modules.threshold.rotation = 90
check(not Circuit.compile(state), "rotating in place must respect fixed part footprints")
state.modules.threshold.row = 3
check(assert(Circuit.compile(state))(115) == 255, "links survive a valid rotation and move")
state.modules.threshold.column = 3
check(not Circuit.compile(state), "rotated footprint stays in bounds")
state = Circuit.thresholdPreset()
state.links[3] = { from = "input", output = "out", to = "output", input = "in" }
check(not Circuit.compile(state), "each input has at most one driver")
state = Circuit.thresholdPreset()
state.links[1].output = "in"
check(not Circuit.compile(state), "links enforce terminal direction")
state = Circuit.thresholdPreset()
state.links[1].from = "threshold"
check(not Circuit.compile(state), "feedback is rejected")
state = Circuit.thresholdPreset()
state.modules.spare = { kind = "threshold", row = 3, column = 1, rotation = 90, threshold = 10 }
state.links[3] = { from = "spare", output = "out", to = "spare", input = "in" }
check(not Circuit.compile(state), "feedback is rejected even away from the output")
state = Circuit.thresholdPreset()
state.modules.threshold.threshold = 256
check(not Circuit.compile(state), "threshold config is a byte")
state = Circuit.thresholdPreset()
state.modules.threshold.threshold = 120
check(run(115) == 255, "compiled evaluation owns its saved settings")

local board = {
    modules = {
        arm = { kind = "inputExtension", column = 2, row = 1, rotation = 90 },
        threshold = { kind = "threshold", column = 2, row = 3, rotation = 0, threshold = 50 },
        gate = { kind = "and", column = 4, row = 3, rotation = 0 },
        spare = { kind = "outputExtension", column = 6, row = 4, rotation = 180 },
    },
    links = {
        { from = "input", output = "out", to = "threshold", input = "in" },
        { from = "threshold", output = "out", to = "gate", input = "a" },
        { from = "arm", output = "out", to = "gate", input = "b" },
        { from = "gate", output = "out", to = "output", input = "in" },
        { from = "input", output = "out", to = "spare", input = "in" },
    },
}
local evaluate, err, topology = compileBytes(board, true)
assert(evaluate, err)
check(topology.directions.arm == "sink" and topology.directions.spare == "source"
    and topology.dependencies.output.arm and topology.dependencies.output.input
    and not topology.dependencies.spare.arm, "each output records its own reachable input jacks")
for _, row in ipairs({
    { input = 8, arm = 255, expected = 0 },
    { input = 49, arm = 255, expected = 0 },
    { input = 50, arm = 1, expected = 255 },
    { input = 115, arm = 255, expected = 255 },
    { input = 115, arm = 0, expected = 0 },
    { input = 0, arm = 255, expected = 0 },
    { input = 115 },
    { arm = 255 },
    { arm = 0 },
}) do
    local output = evaluate(row)
    local direct = row.input ~= nil and (row.input > 0 and 255 or 0) or nil
    check(output.output == row.expected and output.spare == direct, "cabinet threshold and AND truth table")
end
board.modules.threshold.threshold = 120
check(evaluate({ input = 115, arm = 255 }).output == 255, "cabinet evaluator snapshots module settings")
for _, fit in ipairs({ { 1, 4, 0 }, { 3, 1, 90 }, { 6, 4, 180 }, { 3, 6, 270 } }) do
    local extension = { kind = "inputExtension", column = fit[1], row = fit[2], rotation = fit[3] }
    check(Circuit.validate({ modules = { jack = extension }, links = {} }, true), "extension fits on each edge")
    extension.column = 2
    extension.row = 2
    check(not Circuit.validate({ modules = { jack = extension }, links = {} }, true), "centered jack is invalid")
end
board.links[6] = { from = "input", output = "out", to = "gate", input = "a" }
check(not Circuit.validate(board, true), "each AND terminal accepts one driver")
board.links[6].output = "in"
check(not Circuit.validate(board, true), "cabinet enforces contact direction")

local evaluatorBoard = {
    modules = {
        second = { kind = "inputExtension", column = 3, row = 6, rotation = 270 },
        module = { kind = "adder", column = 3, row = 3, rotation = 0 },
    },
    links = {
        { from = "input", output = "out", to = "module", input = "a" },
        { from = "second", output = "out", to = "module", input = "b" },
        { from = "module", output = "out", to = "output", input = "in" },
    },
}
local adder = assert(compileBytes(evaluatorBoard, true))
check(adder({ input = 60, second = 55 }).output == 115, "Adder sums its two bytes")
check(adder({ input = 200, second = 200 }).output == 255, "Adder saturates at 255")
check(adder({ input = 60, second = 0 }).output == 60, "Adder treats zero as a connected input")
check(adder({ input = 0, second = 0 }).output == 0, "Adder can publish zero")
check(adder({ input = 60 }).output == nil and adder({ second = 55 }).output == nil,
    "Adder clears when either required input is missing")

for kind, expected in pairs({ ["or"] = { 0, 255, 255, 255 }, xor = { 0, 255, 255, 0 } }) do
    evaluatorBoard.modules.module.kind = kind
    local gate = assert(compileBytes(evaluatorBoard, true))
    for i, inputs in ipairs({ { 0, 0 }, { 0, 1 }, { 170, 0 }, { 170, 1 } }) do
        check(gate({ input = inputs[1], second = inputs[2] }).output == expected[i], kind .. " boolean truth table")
    end
    check(gate({ input = 255 }).output == nil and gate({ second = 0 }).output == nil,
        kind .. " requires both bytes")
end
local inverter = Circuit.thresholdPreset()
inverter.modules.threshold = { kind = "not", column = 2, row = 1, rotation = 0 }
local invert = assert(Circuit.compile(inverter))
check(invert(0) == 255 and invert(1) == 0 and invert(255) == 0, "NOT inverts byte truth in the 3x3 adapter")
check(invert(nil) == nil, "NOT preserves unavailable input")
local cabinetInverter = assert(compileBytes(inverter, true))
check(cabinetInverter({ input = 0 }).output == 255, "the same NOT module also works in a cabinet")

evaluatorBoard.modules.module.kind = "cache"
evaluatorBoard.links[1].input = "data"
evaluatorBoard.links[2].input = "enable"
local cache = assert(Circuit.compilePackets(evaluatorBoard, true, "advanced"))
local weight = packet.weight(1150.25, 115)
check(cache({ input = weight, second = packet.basic(255) }).output.value == 115,
    "Cache forwards the sender fallback at a basic jack")
evaluatorBoard.outputModes = { output = "advanced" }
cache = assert(Circuit.compilePackets(evaluatorBoard, true, "advanced"))
check(packet.equal(cache({ input = weight, second = packet.basic(1) }).output, weight),
    "Cache preserves the full weight at an advanced jack")
check(cache({ input = weight, second = packet.basic(0) }).output == nil
    and cache({ input = weight }).output == nil, "Cache clears when enable is off or missing")
check(cache({ second = packet.basic(255) }).output == nil, "enabled Cache clears if its data is missing")
evaluatorBoard.modules.module.always = true
cache = assert(Circuit.compilePackets(evaluatorBoard, true, "advanced"))
local noFallback = packet.weight(200)
check(packet.equal(cache({ input = noFallback }).output, noFallback), "Always mode forwards weight without a fallback")
check(cache({ input = packet.basic(9) }).output.value == 9, "advanced output preserves a received basic byte")
local direct = { modules = {}, outputModes = { output = "advanced" }, links = {
    { from = "input", output = "out", to = "output", input = "in" },
} }
check(assert(Circuit.compilePackets(direct, true, "advanced"))({ input = weight }).output.value == 255,
    "a direct jack connection publishes control rather than forwarding data")

local split = { modules = {
    splitter = { kind = "splitter", column = 3, row = 1, rotation = 90 },
}, links = {
    { from = "input", output = "out", to = "splitter", input = "in" },
} }
local firstPort, secondPort = Circuit.splitterPort("splitter", 1), Circuit.splitterPort("splitter", 2)
local splitterPart = split.modules.splitter
for _, mount in ipairs({ { 1, 3, 0 }, { 3, 1, 90 }, { 6, 3, 180 }, { 5, 6, 270 } }) do
    splitterPart.column, splitterPart.row, splitterPart.rotation = mount[1], mount[2], mount[3]
    check(Circuit.compilePackets(split, true, "basic"), "splitter can mount on edge at rotation " .. mount[3])
end
splitterPart.column, splitterPart.row, splitterPart.rotation = 3, 2, 90
check(not Circuit.compilePackets(split, true, "basic"), "the cabinet rejects an interior splitter")
splitterPart.row, splitterPart.rotation = 1, 270
check(not Circuit.compilePackets(split, true, "basic"), "the cabinet rejects splitter jacks facing in")
splitterPart.rotation = 90
local basicSplit, _, splitBoard = Circuit.compilePackets(split, true, "basic")
local branches = basicSplit({ input = weight })
check(branches[firstPort].value == 115 and branches[secondPort].value == 115,
    "one internal input supplies both external jacks with the exact fallback byte")
branches = basicSplit({ input = packet.basic(0) })
check(branches[firstPort].value == 0 and branches[secondPort].value == 0, "splitter forwards connected zero")
branches = basicSplit({ input = noFallback })
check(branches[firstPort] == nil and branches[secondPort] == nil, "a Basic splitter clears both branches without a fallback")
check(splitBoard.dependencies[firstPort].input and splitBoard.dependencies[secondPort].input,
    "both splitter outputs depend on the same input run")
split.outputModes = { [firstPort] = "advanced", [secondPort] = "advanced" }
local valid, reason = Circuit.validate(split, true, "basic")
check(not valid and reason == "Advanced output requires an Advanced Cabinet",
    "validation rejects advanced output configuration on a Basic cabinet")
check(Circuit.validate(split, true, "advanced"), "validation recognizes advanced splitter outputs")
local advancedSplit = assert(Circuit.compilePackets(split, true, "advanced"))
branches = advancedSplit({ input = noFallback })
check(packet.equal(branches[firstPort], noFallback) and packet.equal(branches[secondPort], noFallback),
    "an Advanced cabinet can split the full packet even without a fallback")
split.links[2] = { from = "splitter", output = "outA", to = "output", input = "in" }
check(not Circuit.compilePackets(split, true, "advanced"), "a splitter jack cannot drive an internal link")

evaluatorBoard.links[1].input, evaluatorBoard.links[2].input = "a", "b"
evaluatorBoard.modules.module = { kind = "adder", column = 3, row = 3, rotation = 0, fullReading = true }
check(not Circuit.compilePackets(evaluatorBoard, true, "basic"), "a Basic cabinet rejects Full Reading")
local read = assert(Circuit.compilePackets(evaluatorBoard, true, "advanced"))
local sum = read({ input = packet.weight(1150.25, 115), second = packet.weight(1600, 160) }).output
check(sum.value.amount == 2750.25 and sum.basicValue == 255, "full adder sums the original weights before deriving fallback")
check(read({ input = weight, second = packet.basic(5) }).output == nil, "typed weight math rejects an untyped byte")
check(read({ input = packet.weight(1e308), second = packet.weight(1e308) }).output == nil,
    "typed arithmetic drops a non-finite result")
evaluatorBoard.modules.module.kind = "subtractor"
read = assert(Circuit.compilePackets(evaluatorBoard, true, "advanced"))
check(read({ input = packet.weight(320), second = packet.weight(80) }).output.value.amount == 240
    and read({ input = packet.weight(80), second = packet.weight(320) }).output.value.amount == 0,
    "full subtractor observes operand order and floors weight at zero")
evaluatorBoard.modules.module.kind = "multiplier"
read = assert(Circuit.compilePackets(evaluatorBoard, true, "advanced"))
local multiplied = read({ input = packet.weight(80), second = packet.basic(4) }).output
check(multiplied.value.amount == 320 and multiplied.basicValue == 32, "a basic scalar can multiply a full weight")
check(read({ input = packet.weight(80), second = packet.weight(4) }).output == nil,
    "the Factor port requires a scalar")
evaluatorBoard.modules.module.fullReading = false
local byteMath = assert(compileBytes(evaluatorBoard, true, "advanced"))
check(byteMath({ input = 120, second = 4 }).output == 255, "byte multiplication saturates")
evaluatorBoard.modules.module.kind = "subtractor"
byteMath = assert(compileBytes(evaluatorBoard, true, "advanced"))
check(byteMath({ input = 25, second = 8 }).output == 17 and byteMath({ input = 0, second = 20 }).output == 0
    and byteMath({ input = 25 }).output == nil, "byte subtraction keeps true zero separate from missing")

local timed = {
    modules = {
        wait = { kind = "wait", column = 2, row = 1, rotation = 0, seconds = 2 },
        timer = { kind = "timer", column = 1, row = 3, rotation = 90, seconds = 10 },
    },
    links = {
        { from = "input", output = "out", to = "wait", input = "in" },
        { from = "wait", output = "out", to = "timer", input = "in" },
        { from = "timer", output = "out", to = "output", input = "in" },
    },
}
local timedLamp = assert(Circuit.compile(timed))
local env = { now = 0, timers = {} }
check(timedLamp(0, env) == 0, "a clear plate arms the timer")
env.now = 1
local value, deadline = timedLamp(255, env)
check(value == 0 and deadline == 3, "Wait schedules a future output")
env.now = 3
value, deadline = timedLamp(255, env)
check(value == 255 and deadline == 13, "Timer starts once the pressure qualifies")
env.now = 4
check(timedLamp(0, env) == 255, "a valid zero lets the open window finish")
env.now = 13
check(timedLamp(0, env) == 0, "a scheduled deadline closes the door without new activity")
env.now = 14
timedLamp(255, env)
env.now = 16
check(timedLamp(255, env) == 255 and timedLamp(nil, env) == nil, "unplugging cancels an active timer")
timed.links[2] = { from = "wait", output = "out", to = "output", input = "in" }
timed.links[3] = nil
local delay = assert(Circuit.compile(timed))
env = { now = 0, timers = {} }
check(delay(255, env) == 0, "new Wait holds off")
env.now = 2
check(delay(255, env) == 255 and delay(0, env) == 0, "Wait qualifies ON and passes zero immediately")

local supply = { modules = { source = {
    kind = "mainsSource", column = 2, row = 1, rotation = 90, level = 37,
} }, links = { { from = "source", output = "out", to = "output", input = "in" } } }
local source, _, boardMeta = Circuit.compile(supply)
check(boardMeta.hasMains and source(nil, { mains = true }) == 37
    and source(nil, { mains = false }) == nil, "one-cell source uses mains power and its configured byte")
supply.modules.source.kind = "batterySource"
check(assert(Circuit.compile(supply))(nil) == nil, "empty Battery Source has no output")
supply.modules.source.charge = 0.2
check(assert(Circuit.compile(supply))(nil) == 37, "charged Battery Source has the configured byte")
supply.modules.source.charge = 0
check(assert(Circuit.compile(supply))(nil) == nil, "empty battery clears the output")
print(string.format("%d checks, 0 failed", checks))
