local shared = "workshop/ZedComm/Contents/mods/ZedComm/42/media/lua/shared/"
package.path = shared .. "?.lua;" .. package.path
next = nil
require "ZedComm/InternalCircuit"
local Circuit = ZedComm.InternalCircuit
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

local state = Circuit.thresholdPreset()
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
print(string.format("%d checks, 0 failed", checks))
