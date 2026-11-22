-- Device definition contract (ADR-302, ADR-308). No world mutation here.
-- register(def) -> true, or false, reason. get(id) -> definition copy or nil.
-- match(object, context) -> definition copy or nil, optional error reason.
-- match predicates must be pure and return a boolean. Multiple matches fail.
-- Sources sample a byte, or a raw reading for their declared readingKind.
-- Receivers name a receiver module and bind it to their fixture.
-- Receiver boards bind an action controller with adapter(action), flush() and
-- release(). Single-port fixtures bind one adapter directly.
-- Callbacks stay in code, never in saved records. Runtime invocation is separate.

ZedComm = ZedComm or {}
local Definitions = {}

function Definitions.readObjectTag(object)
    if not object or not object.hasModData or not object:hasModData() then return nil end
    local data = object:getModData()
    local tag = data and data.zedcomm
    return type(tag) == "table" and tag or nil, data
end

function Definitions.readFixtureTag(object)
    local tag, data = Definitions.readObjectTag(object)
    return tag and type(tag.id) == "string" and tag or nil, data
end
local entries, ids = {}, {}
local fields = { id = true, role = true, ports = true, match = true,
    sample = true, sampleInterval = true, readingKind = true, receiverModule = true, bindFixture = true }

local function copy(def)
    local out = { id = def.id, role = def.role, match = def.match,
        sample = def.sample, sampleInterval = def.sampleInterval, readingKind = def.readingKind,
        receiverModule = def.receiverModule, bindFixture = def.bindFixture, ports = {} }
    for i = 1, #def.ports do out.ports[i] = def.ports[i] end
    return out
end

function Definitions.register(def)
    if type(def) ~= "table" then return false, "definition must be a table" end
    for key in pairs(def) do
        if not fields[key] then return false, "unknown definition field: " .. tostring(key) end
    end
    if type(def.id) ~= "string" or not string.match(def.id, "^[%a_][%w_]*%.[%a_][%w_]*$") then
        return false, "id must be Namespace.Name"
    end
    if entries[def.id] then return false, "duplicate definition: " .. def.id end
    if def.role ~= "source" and def.role ~= "receiver" then
        return false, "role must be source or receiver"
    end
    if type(def.match) ~= "function" then return false, "match must be a function" end
    if def.role == "source" then
        if type(def.sample) ~= "function" then return false, "source requires sample" end
        local interval = def.sampleInterval
        if interval ~= nil and (type(interval) ~= "number" or interval - interval ~= 0 or interval <= 0) then
            return false, "source sampleInterval must be positive finite seconds"
        end
        if def.readingKind ~= nil and def.readingKind ~= "weight" and def.readingKind ~= "fluidVolume" then
            return false, "unsupported source reading kind"
        end
        if def.receiverModule ~= nil or def.bindFixture ~= nil then
            return false, "source cannot define receiver behavior"
        end
    else
        if def.sample ~= nil or def.sampleInterval ~= nil or def.readingKind ~= nil then
            return false, "receiver cannot define source sampling"
        end
        if type(def.receiverModule) ~= "string" or def.receiverModule == ""
            or type(def.bindFixture) ~= "function" then
            return false, "receiver requires a module ID and fixture binding"
        end
    end
    if type(def.ports) ~= "table" then return false, "ports must be a nonempty list" end
    local count, seen = 0, {}
    for key, name in pairs(def.ports) do
        if type(key) ~= "number" or key < 1 or math.floor(key) ~= key then
            return false, "ports must be a dense list"
        end
        if type(name) ~= "string" or not string.match(name, "^[%a_][%w_]*$") then
            return false, "invalid port name"
        end
        if seen[name] then return false, "duplicate port: " .. name end
        seen[name] = true
        count = count + 1
    end
    if count == 0 then return false, "ports must be a nonempty list" end
    for i = 1, count do
        if def.ports[i] == nil then return false, "ports must be a dense list" end
    end
    entries[def.id] = copy(def)
    ids[#ids + 1] = def.id
    table.sort(ids)
    return true
end

function Definitions.get(id)
    local def = entries[id]
    if def then return copy(def) end
    return nil
end

function Definitions.match(object, context)
    if object == nil then return nil end
    local matches = {}
    -- Sorted IDs make ambiguity messages and predicate order reproducible.
    for i = 1, #ids do
        local def = entries[ids[i]]
        local ok, matched = pcall(def.match, object, context)
        if not ok then return nil, "match failed: " .. def.id .. ": " .. tostring(matched) end
        if type(matched) ~= "boolean" then
            return nil, "match must return boolean: " .. def.id
        end
        if matched then matches[#matches + 1] = def.id end
    end
    if #matches > 1 then return nil, "ambiguous match: " .. table.concat(matches, ", ") end
    if #matches == 1 then return Definitions.get(matches[1]) end
    return nil
end

ZedComm.DeviceDefinitions = Definitions
return Definitions
