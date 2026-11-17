-- Contract tests run on Lua 5.1, including the missing-next regression.
next = nil
local path = "workshop/ZedComm/Contents/mods/ZedComm/42/media/lua/shared/ZedComm/DeviceDefinitions.lua"
local checks, failures = 0, 0
local function check(value, message)
    checks = checks + 1
    if not value then failures = failures + 1; print("FAIL: " .. message) end
end
local function fresh() return dofile(path) end
local function source(id)
    return { id = id or "ZedComm.PressureSensor", role = "source", ports = { "signal" },
        match = function(o) return o.kind == "sensor" end,
        sample = function() return 255 end }
end
local function receiver(id)
    return { id = id or "Example.Lamp", role = "receiver", ports = { "input" },
        match = function(o) return o.kind == "lamp" end,
        receiverModule = "Example.Module", bindFixture = function() return {} end }
end
local d = fresh()
local original = source()
check(d.register(original), "native definition registers")
check(d.register(receiver()), "extension uses identical registration")
local weightSource = source("Example.Weight")
weightSource.readingKind = "weight"
check(d.register(weightSource), "a source can opt in to sampling weight")
weightSource.readingKind = "invalid"
local registeredWeight = d.get("Example.Weight")
check(registeredWeight and registeredWeight.readingKind == "weight", "reading kind is copied into the registry")
check(d.get("ZedComm.PressureSensor").readingKind == nil, "byte-only sources keep their existing contract")
local invalidKind = source("Example.InvalidKind")
invalidKind.readingKind = "text"
check(not d.register(invalidKind), "unimplemented source reading kinds are rejected")
local receiverKind = receiver("Example.ReceiverKind")
receiverKind.readingKind = "weight"
check(not d.register(receiverKind), "receivers cannot set a source reading kind")
check(d.get("missing") == nil, "unknown ID is absent")
check(d.get(nil) == nil, "nil ID is absent")
local ok, err = d.register(source())
check(not ok and string.find(err, "duplicate", 1, true), "duplicate rejected")
original.ports[1] = "changed"; original.role = "receiver"
check(d.get("ZedComm.PressureSensor").ports[1] == "signal", "registration snapshots ports")
check(d.get("ZedComm.PressureSensor").role == "source", "registration snapshots role")
local found = d.get("ZedComm.PressureSensor")
found.ports[1] = "changed"; found.sample = nil
check(d.get(found.id).ports[1] == "signal" and type(d.get(found.id).sample) == "function", "lookup cannot mutate registry")
local obj = { kind = "lamp" }
found, err = d.match(obj)
check(found and found.id == "Example.Lamp" and err == nil, "unique match resolves extension")
check(obj.received == nil and obj.zedcomm == nil, "matching does not invoke receiver or install a tag")
check(d.match({ kind = "other" }) == nil, "no match returns nil")
check(d.match(nil) == nil, "nil object returns nil")
local observed
local def = source("Example.Context")
def.match = function(o, context) observed = context; return false end
d.register(def)
d.match({}, "context")
check(observed == "context", "context forwarded to predicate")

local function invalid(change, description)
    local registry, candidate = fresh(), source()
    change(candidate)
    local accepted, reason = registry.register(candidate)
    check(not accepted and type(reason) == "string", description)
    check(registry.get("ZedComm.PressureSensor") == nil, description .. " leaves registry unchanged")
end
check(not fresh().register(nil), "nil definition rejected")
check(not fresh().register("bad"), "non-table rejected")
invalid(function(v) v.id = "sensor" end, "unqualified ID rejected")
invalid(function(v) v.id = "Example.Bad#id" end, "unsafe ID rejected")
invalid(function(v) v.role = "sink" end, "internal sink role rejected at public boundary")
invalid(function(v) v.role = "infrastructure" end, "infrastructure outside endpoint contract")
invalid(function(v) v.match = true end, "invalid predicate rejected")
invalid(function(v) v.sample = nil end, "source must sample")
invalid(function(v) v.receiverModule = "Example.Module" end, "source cannot receive")
invalid(function(v) v.extra = true end, "unknown fields rejected")
invalid(function(v) v.ports = nil end, "missing ports rejected")
invalid(function(v) v.ports = {} end, "empty ports rejected")
invalid(function(v) v.ports = { "signal", "signal" } end, "duplicate ports rejected")
invalid(function(v) v.ports = { [1] = "one", [3] = "three" } end, "sparse ports rejected")
invalid(function(v) v.ports = { named = "signal" } end, "map ports rejected")
invalid(function(v) v.ports = { "bad#port" } end, "unsafe port rejected")
invalid(function(v) v.ports = { false } end, "non-string port rejected")
local badReceiver = receiver(); badReceiver.bindFixture = nil
check(not fresh().register(badReceiver), "receiver must bind a fixture")
badReceiver = receiver(); badReceiver.sample = function() end
check(not fresh().register(badReceiver), "receiver cannot sample")

local function ambiguity(reverse)
    local registry = fresh()
    local a, b = receiver("A.Lamp"), receiver("B.Lamp")
    registry.register(reverse and b or a); registry.register(reverse and a or b)
    local result, reason = registry.match({kind = "lamp"})
    check(result == nil, "ambiguous match never chooses a winner")
    return reason
end
check(ambiguity(false) == "ambiguous match: A.Lamp, B.Lamp", "ambiguity names sorted candidates")
check(ambiguity(false) == ambiguity(true), "registration order cannot change ambiguity")
d = fresh(); def = source(); def.match = function() error("broken") end; d.register(def)
found, err = d.match({})
check(found == nil and string.find(err, "match failed", 1, true), "predicate exception becomes explicit failure")
d = fresh(); def = source(); def.match = function() return 1 end; d.register(def)
found, err = d.match({})
check(found == nil and string.find(err, "boolean", 1, true), "truthy non-boolean predicate rejected")
print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
