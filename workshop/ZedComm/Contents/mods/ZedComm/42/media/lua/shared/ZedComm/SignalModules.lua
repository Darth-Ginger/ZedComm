-- Wire-facing modules. Fixtures supply readings and apply device requests.
ZedComm = ZedComm or {}
local Modules = {
    ON_OFF = "ZedComm.OnOffReceiver",
    BYTE_READOUT = "ZedComm.ByteReadoutReceiver",
    BASIC_SENDER = "ZedComm.BasicSender",
    ADVANCED_SENDER = "ZedComm.AdvancedSender",
}
local Sender = {}
local Receiver = {}
Receiver.__index = Receiver

local Packet = {}
local BASIC, ADVANCED = "signal.basic", "signal.advanced"

local function isByte(value)
    return type(value) == "number" and value >= 0 and value <= 255 and math.floor(value) == value
end

local function isPlainTable(value)
    return type(value) == "table" and getmetatable(value) == nil
end

function Packet.basic(value)
    if not isByte(value) then return nil, "expected a byte from 0 to 255" end
    return { type = BASIC, value = value }
end

local function isWeight(amount)
    return type(amount) == "number" and amount >= 0 and amount - amount == 0
end

function Packet.weight(amount, basicValue)
    if not isWeight(amount) then
        return nil, "expected a finite, nonnegative weight"
    end
    return {
        type = ADVANCED,
        value = { kind = "weight", amount = amount, unit = "kg" },
        basicValue = isByte(basicValue) and basicValue or nil,
    }
end

function Packet.validate(packet)
    if packet == nil then return true end
    if not isPlainTable(packet) then return false, "expected a signal packet" end
    if packet.type == BASIC then
        if isByte(packet.value) then return true end
        return false, "invalid basic packet byte"
    end
    if packet.type == ADVANCED then
        local value = packet.value
        if isPlainTable(value) and value.kind == "weight" and value.unit == "kg"
            and isWeight(value.amount) then
            return true
        end
        return false, "invalid advanced weight payload"
    end
    return false, "unknown signal packet type"
end

function Packet.basicValue(packet)
    if packet == nil then return nil end
    if packet.type == BASIC then return packet.value end
    if packet.type == ADVANCED and isByte(packet.basicValue) then return packet.basicValue end
end

-- Call with validated packets. Normalize an invalid optional fallback to
-- unavailable so it does not change what either receiver can use.
function Packet.equal(first, second)
    if first == second then return true end
    if first == nil or second == nil or first.type ~= second.type then return false end
    if first.type == BASIC then return first.value == second.value end
    return first.value.amount == second.value.amount and Packet.basicValue(first) == Packet.basicValue(second)
end

function Packet.copy(packet)
    if packet == nil then return nil end
    if packet.type == BASIC then return Packet.basic(packet.value) end
    return Packet.weight(packet.value.amount, packet.basicValue)
end

function Sender.fromBoolean(active)
    if type(active) ~= "boolean" then return nil, "expected a boolean reading" end
    return active and 255 or 0
end

function Sender.supports(moduleId, readingKind)
    if moduleId == Modules.BASIC_SENDER then return readingKind == nil or readingKind == "weight" end
    return moduleId == Modules.ADVANCED_SENDER and readingKind == "weight"
end

-- A sender chooses its wire representation without consulting any receiver.
function Sender.encode(reading, readingKind, moduleId)
    if moduleId == nil then moduleId = Modules.BASIC_SENDER end
    if not Sender.supports(moduleId, readingKind) then return nil, "incompatible sender module" end
    if reading == nil then return nil end
    if readingKind == nil then return Packet.basic(reading) end
    if not isWeight(reading) then return nil, "expected a finite, nonnegative weight" end

    local byte = 0
    if reading > 0 then
        byte = math.min(255, math.max(1, math.floor(reading / 10 + 0.5)))
    end
    if moduleId == Modules.ADVANCED_SENDER then return Packet.weight(reading, byte) end
    return Packet.basic(byte)
end

-- An adapter supplies apply(request) and optionally release(). A receiver
-- instance belongs to one installation, with no durable state in this object.
function Modules.newReceiver(moduleId, adapter)
    if moduleId ~= Modules.ON_OFF and moduleId ~= Modules.BYTE_READOUT then
        return nil, "unknown receiver module"
    end
    if type(adapter) ~= "table" or type(adapter.apply) ~= "function"
        or (adapter.release ~= nil and type(adapter.release) ~= "function")
        or (adapter.isAvailable ~= nil and type(adapter.isAvailable) ~= "function") then
        return nil, "invalid fixture adapter"
    end
    return setmetatable({ moduleId = moduleId, adapter = adapter, attached = false }, Receiver)
end

local function apply(self)
    local ok, status, reason = pcall(self.adapter.apply, self.adapter, self.request)
    if not ok then
        status, reason = "unavailable", "fixture application failed: " .. tostring(status)
    elseif status ~= "applied" and status ~= "unavailable" and status ~= "unsupported" then
        status, reason = "unsupported", "invalid fixture result"
    end
    self.result, self.reason = status, reason
    return status, reason
end

function Receiver:receive(value, reconcile)
    if value ~= nil and not isByte(value) then return nil, "expected a byte or unavailable input" end
    local request = value
    if self.moduleId == Modules.ON_OFF then request = value ~= nil and value ~= 0 end

    local changed = not self.attached or request ~= self.request
    self.attached, self.input, self.request = true, value, request
    if changed or (reconcile and self.result ~= "unsupported") then return apply(self) end
    return self.result, self.reason
end

-- An explicit fixture event calls this after an availability change. A quiet
-- wire does not retry on every tick, and only the latest request can apply.
function Receiver:reconcile()
    if not self.attached then return "detached" end
    if self.result == "unsupported" then return self.result, self.reason end
    return apply(self)
end

function Receiver:detach()
    if not self.attached then return "detached" end
    self.attached, self.input, self.request = false, nil, nil
    self.result, self.reason = nil, nil
    if self.adapter.release then
        local ok, err = pcall(self.adapter.release, self.adapter)
        if not ok then return "detached", "fixture release failed: " .. tostring(err) end
    end
    return "detached"
end

Modules.Packet = Packet
Modules.Sender = Sender
ZedComm.SignalModules = Modules
return Modules
