-- Offline contract checks for the reusable sender and fixture receivers.
next = nil
local shared = "workshop/ZedComm/Contents/mods/ZedComm/42/media/lua/shared/"
package.path = shared .. "?.lua;" .. package.path
local modules = require("ZedComm/SignalModules")
local sender = modules.Sender
local checks, failures = 0, 0
local function check(ok, description)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL: " .. description)
    end
end

local Packet = modules.Packet
local volume = assert(sender.encode(0.1875, "fluidVolume", modules.ADVANCED_SENDER))
local copy = Packet.copy(volume)
check(Packet.validate(volume) and copy.value.kind == "fluidVolume" and copy.value.unit == "L"
    and copy.value.amount == 0.1875 and copy.value ~= volume.value and Packet.equal(copy, volume),
    "volume copies retain exact liters independently")
check(not Packet.equal(volume, Packet.weight(0.1875)) and Packet.basicValue(volume) == nil
    and sender.encode(1, "fluidVolume", modules.BASIC_SENDER) == nil, "volume has no byte representation")
copy.basicValue = 0
check(not Packet.validate(copy) and Packet.basicValue(copy) == nil, "volume cannot claim a fallback")
copy.basicValue, copy.value.unit = nil, "kg"
check(not Packet.validate(copy) and Packet.fluidVolume(math.huge) == nil and Packet.fluidVolume(-1) == nil
    and Packet.fluidVolume(0).value.amount == 0, "volume requires finite nonnegative liters")
check(sender.fromBoolean(false) == 0 and sender.fromBoolean(true) == 255,
    "occupancy maps to the existing 0/255 byte values")
check(sender.fromBoolean(0) == nil, "Lua truthiness cannot silently turn byte zero into true")
for _, value in ipairs({ 0, 85, 170, 255 }) do
    local packet = sender.encode(value)
    check(packet.type == "signal.basic" and Packet.basicValue(packet) == value,
        "sender encodes the exact basic byte " .. value)
end
local missing, reason = sender.encode(nil)
check(missing == nil and reason == nil, "no source reading produces an unavailable signal")
for _, invalid in ipairs({ -1, 256, 0.5, "85", false, {}, math.huge, 0 / 0 }) do
    local encoded, errorMessage = sender.encode(invalid)
    check(encoded == nil and errorMessage, "invalid source reading is rejected")
end
local weight = assert(Packet.weight(1150, 115))
check(Packet.validate(weight) and weight.value.amount == 1150 and Packet.basicValue(weight) == 115,
    "typed weight packets preserve the full estimate and sender fallback")
check(Packet.basicValue(assert(Packet.weight(0, 0))) == 0, "a zero fallback is valid")
check(Packet.basicValue(assert(Packet.weight(1150))) == nil, "an omitted fallback has no byte projection")
check(Packet.basicValue(assert(Packet.weight(1150, 256))) == nil, "an invalid fallback has no byte projection")

for _, sample in ipairs({ { 0, 0 }, { 2, 1 }, { 74, 7 }, { 75, 8 }, { 1150, 115 }, { 3000, 255 } }) do
    local basic = assert(sender.encode(sample[1], "weight"))
    local advanced = assert(sender.encode(sample[1], "weight", "ZedComm.AdvancedSender"))
    check(basic.type == "signal.basic" and basic.value == sample[2], "basic weight byte for " .. sample[1])
    check(advanced.type == "signal.advanced" and advanced.value.amount == sample[1]
        and advanced.value.unit == "kg" and advanced.basicValue == sample[2],
        "full weight and equivalent fallback for " .. sample[1])
end
local exact = assert(sender.encode(1150.25, "weight", "ZedComm.AdvancedSender"))
check(exact.value.amount == 1150.25 and exact.basicValue == 115, "advanced weight retains its fractional amount")
check(sender.encode(85, nil, "ZedComm.BasicSender").value == 85, "explicit Basic Sender carries a plain byte")
for _, invalid in ipairs({ -1, "85", math.huge, 0 / 0 }) do
    local packet, message = sender.encode(invalid, "weight", "ZedComm.AdvancedSender")
    check(packet == nil and message, "advanced sender rejects invalid weights")
end
local incompatible, reason = sender.encode(85, nil, "ZedComm.AdvancedSender")
check(incompatible == nil and reason, "Advanced Sender rejects a byte-only source")
local unknown, errorMessage = sender.encode(85, "weight", "Example.UnknownSender")
check(unknown == nil and errorMessage, "unknown sender modules cannot silently fall back to Basic Sender")

local lamp = { powered = true, on = false, calls = 0, toggles = 0, released = 0 }
function lamp:apply(desired)
    self.calls = self.calls + 1
    if not self.powered then return "unavailable", "no power" end
    if self.on ~= desired then
        self.on = not self.on
        self.toggles = self.toggles + 1
    end
    return "applied"
end
function lamp:release() self.released = self.released + 1 end
local relay = assert(modules.newReceiver(modules.ON_OFF, lamp))
check(relay:receive(85) == "applied" and lamp.on and lamp.toggles == 1,
    "a nonzero byte requests on through the lamp fixture")
check(relay:receive(170) == "applied" and relay.input == 170
    and lamp.calls == 1 and lamp.toggles == 1, "different nonzero bytes keep one held on request")
check(relay:receive(nil) == "applied" and not lamp.on and lamp.toggles == 2,
    "attached signal loss requests off")
check(relay:receive(0) == "applied" and relay.input == 0 and lamp.calls == 2,
    "valid zero updates the held input without repeating off")

lamp.powered = false
check(relay:receive(255) == "unavailable" and relay.request == true, "an unpowered fixture holds the latest on request")
local calls = lamp.calls
check(relay:receive(85) == "unavailable" and lamp.calls == calls, "held on does not retry a fixture every tick")
check(relay:receive(0) == "unavailable" and relay.request == false, "a newer off replaces pending on")
lamp.powered = true
check(relay:reconcile() == "applied" and not lamp.on and lamp.toggles == 2,
    "recovery applies the latest off rather than replaying a stale on")
lamp.powered = false
check(relay:receive(255) == "unavailable", "fixture can become unavailable again")
lamp.powered = true
check(relay:reconcile() == "applied" and lamp.on and lamp.toggles == 3,
    "availability event applies the held on without a source change")
check(relay:detach() == "detached" and relay.request == nil and relay.input == nil and lamp.released == 1,
    "detach discards held state and releases fixture control")
check(relay:reconcile() == "detached" and relay:detach() == "detached" and lamp.released == 1,
    "detached state is inert and release is not repeated")
calls = lamp.calls
check(relay:receive(255) == "applied" and lamp.calls == calls + 1 and lamp.toggles == 3,
    "reattach reapplies held input without toggling an already correct lamp")

local noise = { playing = false, cycles = 0, requests = 0 }
function noise:startIfWanted()
    if self.wanted and not self.playing then
        self.playing = true
        self.cycles = self.cycles + 1
    end
end
function noise:apply(desired)
    self.requests = self.requests + 1
    self.wanted = desired
    self:startIfWanted()
    return "applied"
end
function noise:finished()
    self.playing = false
    self:startIfWanted()
end
function noise:release() self.wanted = false end
local alarm = assert(modules.newReceiver(modules.ON_OFF, noise))
alarm:receive(255)
alarm:receive(170)
check(noise.playing and noise.cycles == 1 and noise.requests == 1,
    "same on/off module starts a Noisemaker once while it is already playing")
noise:finished()
check(noise.playing and noise.cycles == 2 and noise.requests == 1,
    "Noisemaker repeats from local completion without a new network request")
alarm:receive(0)
check(noise.playing and noise.cycles == 2, "off leaves the current cycle playing")
noise:finished()
check(not noise.playing and noise.cycles == 2, "off leaves no queued repeat")
alarm:receive(255)
alarm:detach()
noise:finished()
check(not noise.playing and noise.cycles == 3, "detach lets a current cycle finish without repeating")

local screen = { samples = {}, releases = 0 }
function screen:apply(value)
    self.samples[#self.samples + 1] = { value = value }
    return "applied"
end
function screen:release() self.releases = self.releases + 1 end
local readout = assert(modules.newReceiver(modules.BYTE_READOUT, screen))
readout:receive(85)
readout:receive(170)
readout:receive(170)
readout:receive(0)
readout:receive(nil)
check(#screen.samples == 4 and screen.samples[1].value == 85 and screen.samples[2].value == 170,
    "readout forwards exact changed bytes and ignores a repeat")
check(screen.samples[3].value == 0 and screen.samples[4].value == nil
    and readout.attached, "valid zero and no signal stay distinct while attached")
local result = readout:receive(256)
check(result == nil and readout.attached and readout.input == nil and #screen.samples == 4,
    "invalid input does not change a readout or clear its attachment")
readout:detach()
check(screen.releases == 1 and not readout.attached, "detach is distinct from attached no signal")
readout:receive(nil)
check(#screen.samples == 5 and screen.samples[5].value == nil and readout.attached,
    "first input after reattach is delivered even when unavailable")

local unsupported = { calls = 0 }
function unsupported:apply()
    self.calls = self.calls + 1
    return "unsupported", "wrong fixture capability"
end
local incompatible = assert(modules.newReceiver(modules.ON_OFF, unsupported))
local status, reason = incompatible:receive(255)
check(status == "unsupported" and reason == "wrong fixture capability"
    and incompatible:reconcile() == "unsupported" and unsupported.calls == 1,
    "unsupported requests stay distinct from temporary unavailability and are not retried")
local flaky = { broken = true }
function flaky:apply()
    if self.broken then error("fixture error") end
    return "applied"
end
local resilient = assert(modules.newReceiver(modules.ON_OFF, flaky))
check(resilient:receive(255) == "unavailable", "an adapter exception is isolated with the request retained")
flaky.broken = false
check(resilient:reconcile() == "applied", "a later event can recover from the adapter exception")

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
