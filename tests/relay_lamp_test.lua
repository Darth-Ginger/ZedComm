local testState = dofile("tests/support/menu_harness.lua")()
local LUA = testState.LUA
local check = testState.check
local list = testState.list
local worldObject = testState.worldObject
local takeOff = testState.takeOff
local deepCopy = testState.deepCopy
local save = testState.save
local fire = testState.fire
local start = testState.start
local loaded = testState.loaded
local placement = testState.placement
local runtime = testState.runtime
local player = testState.player
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local target = testState.target
local lay = testState.lay
local join = testState.join
local menu = testState.menu
local optionsAt = testState.optionsAt

dofile(testState.LUA .. "client/ZedComm/WireVisuals.lua")
do
    local debugBefore = getDebug
    getDebug = function() return true end
    testState.registry, testState.java = start()
    local relay = ZedComm.RelayLamp
    local srcSquare, wireSquare, lampSquare = floorTile(90, 90), floorTile(91, 90), floorTile(92, 90)
    local newLampSquare = floorTile(91, 91)

    local function lampAt(tile, eligible, movableData)
        local lamp = worldObject(tile, nil)
        lamp.class = "IsoLightSwitch"
        lamp.powered, lamp.active, lamp.switches = true, false, 0
        lamp:getModData().movableData = movableData
        function lamp.getCanBeModified() return eligible end
        function lamp.getSprite() return nil end
        function lamp.canSwitchLight() return lamp.powered end
        function lamp.isActivated() return lamp.active end
        function lamp.setActive(_, value)
            if lamp.powered and lamp.active ~= value then
                lamp.active = value
                lamp.switches = lamp.switches + 1
            end
            return lamp.active
        end
        function lamp.toggle() return lamp:setActive(not lamp.active) end
        lamp.attachments = { { getParentSprite = function() return { getName = function() return "vanilla" end } end } }
        function lamp.getAttachedAnimSprite() return list(lamp.attachments) end
        function lamp.addAttachedAnimSprite(_, sprite)
            lamp.attachments[#lamp.attachments + 1] = { getParentSprite = function() return sprite end }
        end
        function lamp.RemoveAttachedAnim(_, index) table.remove(lamp.attachments, index + 1) end
        return lamp
    end

    local function housingIs(lamp, index)
        return #lamp.attachments == 2
            and lamp.attachments[1]:getParentSprite():getName() == "vanilla"
            and lamp.attachments[2]:getParentSprite():getName() == "zedcomm_devices_01_" .. index
    end

    local plain = lampAt(floorTile(93, 90), false)
    local fixture = lampAt(lampSquare, true, { zedcommDevice = { def = "SpikeLamp" } })
    check(not optionsAt(plain:getSquare())["Install test relay"]
        and not runPlacement(plain:getSquare(), { kind = "install-relay", object = plain }),
        "ineligible lights do not get a retrofit action and reject direct installation")
    local options = optionsAt(lampSquare)
    testState.queued = nil
    assert(options["Install test relay"])()
    assert(testState.queued and testState.queued:isValid() and testState.queued:complete())
    fire("OnTick")
    check(housingIs(fixture, 14) and #plain.attachments == 1, "only the installed lamp gets an unplugged housing")
    local id = fixture:getModData().zedcomm.id
    local installed = testState.registry.network:record(id).state.module
    check(installed.id == relay.MODULE and fixture:getModData().movableData.zedcommRelay.id == id
        and fixture:getModData().movableData.zedcommDevice.def == "SpikeLamp",
        "test install creates the relay endpoint and preserves unrelated moveable data")
    check(not runPlacement(lampSquare, { kind = "install-relay", object = fixture })
        and testState.registry.network:record(id).state.module.id == relay.MODULE,
        "reinstall is rejected without changing the installed relay")
    check(optionsAt(lampSquare)["Select relay lamp free end"] and not optionsAt(lampSquare)["Pick up relay lamp"],
        "relay lamp can wire through the player menu and retains native pickup")

    local ok, plateId = runPlacement(srcSquare, { kind = "place", item = give("ZedComm.PressurePlate") })
    assert(ok, plateId)
    local laid, wireId = lay(wireSquare, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid, wireId)
    assert(join(lampSquare, wireId, false, id, "signal"))
    fire("OnTick")
    check(relay.isWired(fixture) and not fixture.active, "wired lamp follows the clear plate")
    fire("LoadGridsquare", lampSquare)
    check(housingIs(fixture, 18), "the west lead is attached once, preserving the vanilla child sprite")
    srcSquare.actors = { { class = "IsoPlayer" } }
    fire("OnTick")
    fire("OnTick")
    check(fixture.active and fixture.switches == 1, "steady high drives the lamp once without strobing")

    package.loaded["TimedActions/ISToggleLightAction"] = true
    ISToggleLightAction = {
        isValid = function() return true end,
        complete = function(self) self.object:toggle(); return true end,
    }
    dofile(LUA .. "client/ZedComm/RelayLampControls.lua")
    local manual = setmetatable({ object = fixture }, { __index = ISToggleLightAction })
    check(not manual:isValid() and manual:complete() and fixture.active and fixture.switches == 1,
        "wired manual toggle is blocked both at validation and at completion")

    assert(testState.registry:unlink(wireId, plateId))
    fire("OnTick")
    check(not fixture.active and fixture.switches == 2 and relay.isWired(fixture),
        "loss of source turns an attached lamp off without releasing native control")
    check(housingIs(fixture, 18), "physical cable direction persists during signal loss")
    fixture.powered = false
    assert(testState.registry:link(wireId, plateId))
    fire("OnTick")
    check(not fixture.active and fixture.switches == 2, "unpowered lamp does not apply the on request")
    fixture.powered = true
    srcSquare.actors = {}
    fire("OnTick")
    check(not fixture.active and fixture.switches == 2,
        "power restoration plus a same-tick OFF never applies the stale ON")
    fixture.powered = false
    srcSquare.actors = { { class = "IsoZombie" } }
    fire("OnTick")
    fixture.powered = true
    fire("OnTick")
    fire("OnTick")
    check(fixture.active and fixture.switches == 3,
        "power restoration applies the held ON without a new source change")

    options = optionsAt(lampSquare)
    testState.queued = nil
    assert(options["Disconnect relay wire"])()
    assert(testState.queued and testState.queued:isValid() and testState.queued:complete())
    fire("OnTick")
    check(not relay.isWired(fixture) and manual:isValid() and manual:complete()
        and not fixture.active and fixture.switches == 4, "disconnect restores vanilla manual switching")
    check(housingIs(fixture, 14), "disconnect restores the empty socket")
    assert(testState.registry:link(wireId, id))
    fire("OnTick")
    check(fixture.active, "reconnect applies current source without a new sample")

    local durable = { module = { id = relay.MODULE, config = { label = "workbench" } } }
    assert(testState.registry:setDeviceState(id, durable))
    fixture:RemoveAttachedAnim(1)
    testState.registry, testState.java = start(save(testState.java))
    fire("OnTick")
    check(housingIs(fixture, 18), "saved wire restores the attachment after reload")
    check(relay.isWired(fixture) and fixture.active
        and testState.registry.network:record(id).state.module.config.label == "workbench",
        "registry reload restores wiring and the installed module configuration")

    -- Simulate vanilla copying movableData before it removes the world object.
    local picked = deepCopy(fixture:getModData().movableData)
    fire("OnObjectAboutToBeRemoved", fixture)
    takeOff(lampSquare, fixture)
    fire("OnTick")
    check(not testState.registry.network.pieces[id] and testState.registry.network.pieces[wireId]
        and picked.zedcommRelay.state.module.config.label == "workbench",
        "native pickup carries durable installation data while leaving the cable")
    local restored = lampAt(newLampSquare, true, picked)
    local tabletopTexture = {
        getOffsetX = function() return 59 end, getWidth = function() return 30 end,
        getOffsetY = function() return 95 end, getHeight = function() return 58 end,
    }
    function restored.getSprite()
        return { getTextureForCurrentFrame = function() return tabletopTexture end, getProperties = function() return nil end }
    end
    function restored.getDir() return "N" end
    function restored.getRenderYOffset() return 18 end
    fire("OnObjectAdded", restored)
    fire("OnTick")
    check(restored:getModData().zedcomm.id == id and testState.registry.network:record(id).state.module.config.label == "workbench"
        and not relay.isWired(restored) and testState.registry.network.pieces[id].ports.signal == false,
        "native replacement rebuilds the same endpoint and leaves the cable disconnected")
    check(housingIs(restored, 44), "native replacement mounts the unplugged housing at the tabletop sprite base")
    restored:RemoveAttachedAnim(1)
    fire("OnObjectAdded", restored)
    fire("OnTick")
    check(housingIs(restored, 44), "native placement refreshes the housing even when topology has not changed")
    assert(testState.registry:link(wireId, id))
    fire("OnTick")
    check(restored.active and restored.switches == 1, "replaced lamp responds after an explicit reconnect")
    check(housingIs(restored, 49), "the raised housing follows the same wire from its new side")

    assert(testState.registry:unlink(wireId, id))
    for _, test in ipairs({ { 92, 91, 46 }, { 91, 92, 47 }, { 91, 91, 45 } }) do
        local cableId = "visual-cable-" .. test[3]
        local cable = worldObject(floorTile(test[1], test[2]), { id = cableId, kind = "cable" })
        fire("OnObjectAdded", cable)
        assert(testState.registry:link(cableId, id))
        fire("OnTick")
        check(housingIs(restored, test[3]), "housing follows selected cable for frame " .. test[3])
        assert(testState.registry:unlink(cableId, id))
    end

    assert(testState.registry:link(wireId, id))
    local Circuit = ZedComm.InternalCircuit
    local load = 80
    assert(target(srcSquare, plateId, "pickup"))
    local weightPlaced, weightId = runPlacement(srcSquare, { kind = "place", item = give("ZedComm.WeightPlate") })
    assert(weightPlaced and testState.registry:link(wireId, weightId))
    srcSquare.actors = {}
    srcSquare.overlappingVehicle = { getMass = function() return load end }
    local function tickLamp(byte, active, message)
        fire("OnTick")
        local report = runtime.inspect(wireId)
        check(report.sourceByte == byte and restored.active == active, message)
    end
    local layout = Circuit.thresholdPreset()
    assert(runtime.setLampCircuit(testState.registry, id, layout))
    tickLamp(8, false, "lamp threshold leaves a player reading unchanged on the wire and turns off")
    load = 500
    tickLamp(50, true, "lamp threshold includes the exact trip point")
    load = 1150
    tickLamp(115, true, "a vehicle reading reaches the lamp and clears the threshold")
    local switches = restored.switches
    tickLamp(115, true, "the held byte keeps the lamp on")
    check(restored.switches == switches, "steady threshold output never toggles the lamp")
    layout.modules.threshold.threshold = 120
    assert(runtime.setLampCircuit(testState.registry, id, layout))
    tickLamp(115, false, "changing the threshold reevaluates a steady input")
    layout.modules.threshold.threshold = 50
    assert(runtime.setLampCircuit(testState.registry, id, layout))
    tickLamp(115, true, "lowering the threshold turns the lamp back on")
    local invalid = Circuit.thresholdPreset()
    invalid.modules.threshold.column = 1
    check(not runtime.setLampCircuit(testState.registry, id, invalid)
        and testState.registry.network:record(id).state.circuit.modules.threshold.column == 2,
        "invalid layouts leave the saved circuit intact")
    layout.links[2] = nil
    assert(runtime.setLampCircuit(testState.registry, id, layout))
    tickLamp(115, false, "a broken internal link turns off the lamp with live wire input")
    local damagedState = testState.registry.network:record(id).state
    damagedState.circuit = false
    assert(testState.registry:setDeviceState(id, damagedState))
    testState.registry, testState.java = start(save(testState.java))
    tickLamp(115, false, "an invalid saved circuit fails off instead of bypassing its logic")
    check(testState.registry.network:record(id).state.circuit == false,
        "an invalid saved circuit stays available for repair")

    restored.powered = false
    assert(runtime.setLampCircuit(testState.registry, id, Circuit.thresholdPreset()))
    tickLamp(115, false, "restoring the link while unpowered retains an ON request")
    restored.powered = true
    load = 80
    tickLamp(8, false, "power recovery uses the current threshold result")
    load = 1150
    tickLamp(115, true, "the lamp turns on when the threshold is satisfied again")
    assert(testState.registry:unlink(wireId, weightId))
    tickLamp(nil, false, "source loss clears the lamp without detaching its wire")
    check(relay.isWired(restored), "source loss keeps the lamp under network control")
    assert(testState.registry:link(wireId, weightId))
    tickLamp(115, true, "source reconnect reevaluates the restored input")

    testState.registry, testState.java = start(save(testState.java))
    load = 80
    tickLamp(8, false, "reload restores the circuit and samples current load")
    local savedCircuit = testState.registry.network:record(id).state.circuit
    check(savedCircuit.modules.threshold.threshold == 50 and #savedCircuit.links == 2,
        "reload retains the installed module and terminal links")
    local advancedMarker = deepCopy(restored:getModData().movableData)
    fire("OnObjectAboutToBeRemoved", restored)
    takeOff(newLampSquare, restored)
    check(testState.registry.network.pieces[wireId] ~= nil
        and advancedMarker.zedcommRelay.state.circuit.modules.threshold.threshold == 50,
        "native lamp pickup keeps the internal circuit and leaves its exterior wire")
    restored = lampAt(newLampSquare, true, advancedMarker)
    fire("OnObjectAdded", restored)
    local nextManual = setmetatable({ object = restored }, { __index = ISToggleLightAction })
    check(not relay.isWired(restored) and nextManual:isValid() and nextManual:complete(),
        "the replaced lamp can use its native switch while unwired")
    assert(testState.registry:link(wireId, id))
    tickLamp(8, false, "reconnecting uses the retained threshold instead of direct on/off")

    getDebug = debugBefore
end

testState.finish()
