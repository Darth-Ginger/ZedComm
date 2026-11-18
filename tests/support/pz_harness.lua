return function()
    local testState = {}
    -- Kahlua may omit the standard Lua next global.
    next = nil
    next = nil

    local MEDIA = "workshop/ZedComm/Contents/mods/ZedComm/42/media/"
    local LUA = MEDIA .. "lua/"
    local PZ = os.getenv("PZ_LUA")
    local GAME = PZ ~= nil and PZ ~= ""
    PZ = GAME and PZ or "tests/support/pz"

    package.path = LUA .. "shared/?.lua;" .. LUA .. "server/?.lua;" .. LUA .. "client/?.lua;"
        .. PZ .. "/shared/?.lua;" .. PZ .. "/server/?.lua;" .. package.path

    local realPrint = print -- the registry's log lines are captured below
    local failures, checks = 0, 0
    local function check(cond, what)
        checks = checks + 1
        if not cond then
            failures = failures + 1
            realPrint("FAIL: " .. what)
        end
    end


    local function list(items)
        return {
            size = function() return #items end,
            get = function(_, i) return items[i + 1] end,
            set = function(_, i, item) items[i + 1] = item end,
        }
    end

    -- Squares and world objects.
    IsoFlagType = { solid = "solid", solidtrans = "solidtrans", solidfloor = "solidfloor",
        WallOverlay = "WallOverlay", FloorOverlay = "FloorOverlay" }
    FBORenderChunk = { DIRTY_OBJECT_ADD = 64 }
    local squares = {}
    local loaded = {} -- key -> true when the square is "loaded"
    local function key(x, y, z) return x .. "," .. y .. "," .. z end

    local function square(x, y, z)
        local k = key(x, y, z)
        if not squares[k] then
            local objects = {}
            local sq = { objects = objects }
            function sq.getX() return x end
            function sq.getY() return y end
            function sq.getZ() return z end
            function sq.getObjects() return list(objects) end
            function sq.getFloor() return sq.floor end
            function sq.getWorldObjects() return list(sq.looseItems or {}) end
            function sq.getStaticMovingObjects() return list(sq.staticActors or {}) end
            function sq.getWall(_, north)
                if north then return sq.northWall end
                return sq.westWall
            end
            function sq.getWallType()
                local south = squares[key(x, y + 1, z)]
                local east = squares[key(x + 1, y, z)]
                return (sq.northWall and 1 or 0) + (south and south.northWall and 2 or 0)
                    + (sq.westWall and 4 or 0) + (east and east.westWall and 8 or 0)
            end
            function sq.getVehicleContainer() return sq.overlappingVehicle end
            function sq.isCouldSee() return true end
            squares[k] = sq
            loaded[k] = true
        end
        return squares[k]
    end

    local function worldObject(sq, tag)
        local data = { zedcomm = tag }
        local o = {}
        function o.hasModData() return true end
        function o.getModData() return data end
        function o.getSquare() return sq end
        function o.getProperties() return nil end
        function o.getSprite() return nil end
        function o.getName() return tag and tag.id or "ZedComm device" end
        sq.objects[#sq.objects + 1] = o
        return o
    end

    local function takeOff(sq, o)
        for i = #sq.objects, 1, -1 do
            if sq.objects[i] == o then table.remove(sq.objects, i) end
        end
    end

    local drags = {}
    function getCell()
        return {
            getDrag = function(_, index) return drags[index] end,
            setDrag = function(_, drag, index)
                if triggerEvent then triggerEvent("SetDragItem", drag, index) end
                local old = drags[index]
                if old == drag then return end
                local deactivate = old and rawget(old, "deactivate")
                if deactivate then deactivate(old) end
                drags[index] = drag
            end,
            getGridSquare = function(_, x, y, z)
                local k = key(x, y, z)
                return loaded[k] and squares[k] or nil
            end,
        }
    end

    -- The Java global object system: one record per x,y,z.
    local function javaSystem(saved)
        local sys = { mod = saved and saved.modData or {}, objects = {}, order = {} }
        local function newGlobal(x, y, z, data)
            local g = { data = data or {} }
            function g.getModData() return g.data end
            function g.getX() return x end
            function g.getY() return y end
            function g.getZ() return z end
            sys.objects[key(x, y, z)] = g
            sys.order[#sys.order + 1] = g
            return g
        end
        function sys.getModData() return sys.mod end
        function sys.setModDataKeys(_, keys) sys.modKeys = keys end
        function sys.setObjectModDataKeys(_, keys) sys.objectKeys = keys end
        function sys.getObjectCount() return #sys.order end
        function sys.getObjectByIndex(_, i) return sys.order[i + 1] end
        function sys.newObject(_, x, y, z) return newGlobal(x, y, z) end
        function sys.getObjectAt(_, x, y, z) return sys.objects[key(x, y, z)] end
        function sys.removeObject(_, g)
            sys.objects[key(g.getX(), g.getY(), g.getZ())] = nil
            for i = #sys.order, 1, -1 do if sys.order[i] == g then table.remove(sys.order, i) end end
        end
        function sys.getObjectsInChunk(_, wx, wy)
            local out = {}
            for _, g in ipairs(sys.order) do
                if math.floor(g.getX() / 8) == wx and math.floor(g.getY() / 8) == wy then out[#out + 1] = g end
            end
            return list(out)
        end
        function sys.finishedWithList() end
        for _, rec in ipairs(saved or {}) do newGlobal(rec.x, rec.y, rec.z, rec.data) end
        return sys
    end

    -- "Save": keep only the declared system and object keys, deep-copied as the game would.
    local function deepCopy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = deepCopy(x) end
        return out
    end
    local function save(sys)
        local out = { modData = {} }
        for _, k in ipairs(sys.modKeys or {}) do out.modData[k] = deepCopy(sys.mod[k]) end
        for _, g in ipairs(sys.order) do
            local data = {}
            for _, k in ipairs(sys.objectKeys or {}) do data[k] = deepCopy(g.data[k]) end
            out[#out + 1] = { x = g.getX(), y = g.getY(), z = g.getZ(), data = data }
        end
        return out
    end

    local nextJava = nil
    SGlobalObjects = {
        registerSystem = function() return nextJava end,
        getSystemCount = function() return 0 end,
    }

    local handlers = {}
    Events = setmetatable({}, {
        __index = function(t, name)
            local e = { Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end }
            rawset(t, name, e)
            return e
        end,
    })
    local function fire(name, ...)
        for _, fn in ipairs(handlers[name] or {}) do fn(...) end
    end

    isClient = function() return false end
    isServer = function() return false end
    getDebug = function() return false end
    testState.logged = {}
    print = function(msg) testState.logged[#testState.logged + 1] = tostring(msg) end


    ZedComm = nil
    ItemTag = { register = function(name) return name end }
    dofile(MEDIA .. "registries.lua")
    require("ZedComm/Simulation")
    require("ZedComm/Registry")
    local Packet = ZedComm.SignalModules.Packet

    local function start(saved)
        nextJava = javaSystem(deepCopy(saved))
        SZedCommSystem.instance = nil
        fire("OnSGlobalObjectSystemInit")
        return SZedCommSystem.instance, nextJava
    end

    local function tileIds(sys, x, y, z)
        local g = sys:getObjectAt(x, y, z)
        if not g then return nil end
        local ids = {}
        for id in pairs(g.data.pieces or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        return table.concat(ids, ",")
    end

    testState.MEDIA = MEDIA
    testState.LUA = LUA
    testState.PZ = PZ
    testState.GAME = GAME
    testState.Packet = Packet
    testState.check = check
    testState.list = list
    testState.square = square
    testState.worldObject = worldObject
    testState.takeOff = takeOff
    testState.deepCopy = deepCopy
    testState.save = save
    testState.fire = fire
    testState.start = start
    testState.tileIds = tileIds
    testState.loaded = loaded
    testState.handlers = handlers
    testState.key = key
    testState.realPrint = realPrint
    testState.finish = function()
        print = realPrint
        print(string.format("%d checks, %d failed", checks, failures))
        if failures > 0 then os.exit(1) end
        return checks, failures
    end
    return testState
end
