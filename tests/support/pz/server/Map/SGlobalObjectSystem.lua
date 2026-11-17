-- Stand-in for the game's server/Map/SGlobalObjectSystem.lua, used by
-- tests/registry_test.lua when the game's own Lua is not available (CI).
-- It covers only what server/ZedComm/Registry.lua calls. The game's file is
-- the authority: run the suite with PZ_LUA set before an in-game check.
ISBaseObject = ISBaseObject or {}
ISBaseObject.Type = "ISBaseObject"
function ISBaseObject:derive(type)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.Type = type
    return o
end

SGlobalObjectSystem = ISBaseObject:derive("SGlobalObjectSystem")

function SGlobalObjectSystem:noise() end

function SGlobalObjectSystem:new(name)
    local system = SGlobalObjects.registerSystem(name)
    local o = system:getModData()
    setmetatable(o, self)
    self.__index = self
    o.system = system
    o.systemName = name
    o:initSystem()
    o:initLuaObjects()
    return o
end

function SGlobalObjectSystem:initSystem() end

function SGlobalObjectSystem:initLuaObjects()
    for i = 1, self.system:getObjectCount() do
        self:newLuaObject(self.system:getObjectByIndex(i - 1))
    end
end

function SGlobalObjectSystem:getLuaObjectCount() return self.system:getObjectCount() end
function SGlobalObjectSystem:getLuaObjectByIndex(index)
    return self.system:getObjectByIndex(index - 1):getModData()
end
function SGlobalObjectSystem:getLuaObjectAt(x, y, z)
    local g = self.system:getObjectAt(x, y, z)
    return g and g:getModData() or nil
end
function SGlobalObjectSystem:newLuaObjectAt(x, y, z)
    return self:newLuaObject(self.system:newObject(x, y, z))
end
function SGlobalObjectSystem:removeLuaObject(luaObject)
    self.system:removeObject(luaObject.globalObject)
end
function SGlobalObjectSystem:OnObjectAdded(isoObject)
    if self:isValidIsoObject(isoObject) then self:loadIsoObject(isoObject) end
end

function SGlobalObjectSystem.RegisterSystemClass(class)
    Events.OnSGlobalObjectSystemInit.Add(function() class.instance = class:new() end)
    Events.OnObjectAdded.Add(function(o) if class.instance then class.instance:OnObjectAdded(o) end end)
    Events.OnObjectAboutToBeRemoved.Add(function(o)
        if class.instance then class.instance:OnObjectAboutToBeRemoved(o) end
    end)
end
