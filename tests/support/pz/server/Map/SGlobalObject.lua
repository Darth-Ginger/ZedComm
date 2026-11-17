-- Stand-in for the game's server/Map/SGlobalObject.lua. See SGlobalObjectSystem.lua.
SGlobalObject = ISBaseObject:derive("SGlobalObject")
function SGlobalObject:new(luaSystem, globalObject)
    local o = globalObject:getModData()
    setmetatable(o, self)
    self.__index = self
    o.luaSystem = luaSystem
    o.globalObject = globalObject
    return o
end
