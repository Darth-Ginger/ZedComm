local testState = dofile("tests/support/menu_harness.lua")()
local LUA = testState.LUA
local check = testState.check
local worldObject = testState.worldObject
local save = testState.save
local fire = testState.fire
local start = testState.start
local loaded = testState.loaded
local placement = testState.placement
local runtime = testState.runtime
local carried = testState.carried
local give = testState.give
local floorTile = testState.floorTile
local runPlacement = testState.runPlacement
local target = testState.target
local placedReading = testState.placedReading
local lay = testState.lay
local join = testState.join
local menu = testState.menu
local menuAt = testState.menuAt

dofile(testState.LUA .. "client/ZedComm/WireVisuals.lua")

-- Use the live menu callbacks to spawn, set and disconnect a byte rig.
do
    testState.registry, testState.java = start()
    local debugBefore = getDebug
    local oldBox, oldLoader = ISTextBox, package.preload["ISUI/ISTextBox"]
    local box, confirm, playerIndex
    local input = "170"
    package.preload["ISUI/ISTextBox"] = function()
        ISTextBox = {
            new = function(_, _, _, _, _, _, _, _, onClick, playerNum)
                playerIndex = playerNum
                box = {
                    entry = { getText = function() return input end },
                    initialise = function() end,
                    addToUIManager = function() end,
                }
                confirm = function() onClick(nil, { internal = "OK", parent = box }) end
                return box
            end,
        }
    end
    dofile(LUA .. "client/ZedComm/DebugCircuits.lua")
    local sourceTile, wireTile, displayTile = floorTile(140, 125), floorTile(141, 125), floorTile(142, 125)
    check(menuAt(sourceTile).children.Debug == nil, "debug controls stay hidden during ordinary play")
    getDebug = function() return true end
    local debugMenu = assert(menuAt(sourceTile).children.Debug)
    assert(debugMenu.options["Place wired byte test rig"])()
    local source, display = sourceTile:getObjects():get(0), displayTile:getObjects():get(0)
    assert(source and display and wireTile:getObjects():size() == 1, testState.logged[#testState.logged])
    local function rigReading()
        fire("OnTick")
        return runtime.getDisplay(display)
    end
    check(source:getModData().zedcomm.definitionId == "ZedComm.DebugByteSource" and rigReading() == 0,
        "the debug menu places a linked byte source, wire and display")
    local wire = wireTile:getObjects():get(0)
    local wireId = wire:getModData().zedcomm.id
    local entry = placement.resolve(testState.registry, wireId)
    check(entry and entry.spec.itemType == "ZedComm.SignalWire" and wire.sprite == "zedcomm_devices_01_8",
        "the rig wire uses the normal placement tag and connected straight-wire sprite")
    debugMenu = assert(menuAt(sourceTile).children.Debug)
    assert(debugMenu.options["Set test byte"])()
    confirm()
    check(playerIndex == 0 and rigReading() == 170, "the byte dialog updates its own rig")
    assert(debugMenu.options["Toggle test source link"])()
    local value, _, attached = rigReading()
    check(value == nil and attached and wire.sprite == "zedcomm_devices_01_4",
        "cutting the debug source exposes the wire's free end and leaves the receiver attached")
    assert(debugMenu.options["Toggle test source link"])()
    check(rigReading() == 170, "the debug source restores its held byte")
    testState.registry, testState.java = start(save(testState.java))
    fire("LoadGridsquare", wireTile)
    check(rigReading() == 170 and wire.sprite == "zedcomm_devices_01_8"
        and placement.resolve(testState.registry, wireId),
        "reload restores the debug signal and renders its wire through the normal path")
    local lampTile = floorTile(143, 125)
    local lamp = worldObject(lampTile, nil)
    lamp.class = "IsoLightSwitch"
    function lamp.getCanBeModified() return true end
    function lamp.getSprite() return nil end
    assert(runPlacement(lampTile, { kind = "install-relay", object = lamp }))
    local lampId = lamp:getModData().zedcomm.id
    local install = assert(menuAt(lampTile).children.Lamp.options["Install test lamp threshold"])
    install()
    check(testState.registry.network:record(lampId).state.circuit.modules.threshold.threshold == 50,
        "the debug menu installs a saved threshold preset")
    local edit = assert(menuAt(lampTile).children.Lamp.options["Set test lamp threshold"])
    edit()
    input = "120"
    confirm()
    install()
    check(testState.registry.network:record(lampId).state.circuit.modules.threshold.threshold == 120,
        "the threshold dialog persists changes and an old preset action cannot reset it")
    edit()
    input = "256"
    confirm()
    check(testState.registry.network:record(lampId).state.circuit.modules.threshold.threshold == 120,
        "the threshold dialog rejects values outside the byte range")
    getDebug = debugBefore
    ISTextBox, package.preload["ISUI/ISTextBox"] = oldBox, oldLoader
    package.loaded["ISUI/ISTextBox"] = nil
end

-- Select the weight sender through the debug menu and inspect its live packet.
do
    testState.registry, testState.java = start()
    local debugBefore = getDebug
    local plateTile, wireTile, displayTile = floorTile(145, 125), floorTile(146, 125), floorTile(147, 125)
    local placed, plateId = runPlacement(plateTile, { kind = "place", item = give("ZedComm.WeightPlate") })
    assert(placed, plateId)
    local displayPlaced, displayId = runPlacement(displayTile, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(displayPlaced, displayId)
    local laid, wireId = lay(wireTile, give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid, wireId)
    assert(join(displayTile, wireId, false, displayId, "signal"))

    local mass = 1150
    local vehicle = { getMass = function() return mass end }
    plateTile.overlappingVehicle = vehicle
    check(placedReading(displayId) == 115, "the default weight sender delivers the existing byte")
    local initial = runtime.inspect(wireId)
    check(initial.sourcePacket and initial.sourcePacket.type == "signal.basic"
        and initial.sourcePacket.value == 115, "the inspector reports the default basic packet")
    check(not menuAt(plateTile).children.Plate.children["Weight plate sender (Basic Sender)"],
        "the fixture's sender selector is debug-only")
    getDebug = function() return true end
    local function modeMenu(label)
        return assert(menuAt(plateTile).children.Plate.children["Weight plate sender (" .. label .. ")"])
    end

    assert(testState.registry:setDeviceState(plateId, { label = "Road plate" }))
    assert(modeMenu("Basic Sender").options["Advanced Sender"])()
    check(placedReading(displayId) == 115, "switching to advanced keeps the byte display at the same value")
    local advanced = runtime.inspect(wireId)
    check(advanced.sourcePacket.type == "signal.advanced" and advanced.sourcePacket.value.amount == 1150
        and advanced.sourcePacket.value.unit == "kg" and advanced.sourcePacket.basicValue == 115
        and advanced.receivers[1].value == 115, "the inspector reports full weight, units, fallback and receiver byte")
    assert(menuAt(wireTile).children.Debug.options["Inspect circuit"])()
    local output = testState.logged[#testState.logged]
    check(string.find(output, "signal.advanced", 1, true) and string.find(output, "1150 kg", 1, true)
        and string.find(output, "fallback 115", 1, true) and string.find(output, "receiver 115", 1, true),
        "the actual inspect menu reports the advanced payload and the delivered byte")
    mass = 1151
    check(placedReading(displayId) == 115 and runtime.inspect(wireId).sourcePacket.value.amount == 1151,
        "a changed full reading reaches the inspector even when the fallback stays steady")
    check(not runtime.setWeightPlateSender(testState.registry, displayId, "ZedComm.AdvancedSender")
        and not runtime.setWeightPlateSender(testState.registry, plateId, "Example.UnknownSender")
        and testState.registry.network:record(plateId).state.senderModule.id == "ZedComm.AdvancedSender",
        "invalid targets and sender IDs preserve the selected sender")

    assert(modeMenu("Advanced Sender").options["Basic Sender"])()
    check(placedReading(displayId) == 115 and runtime.inspect(wireId).sourcePacket.type == "signal.basic"
        and testState.registry.network:record(plateId).state.senderModule == nil
        and testState.registry.network:record(plateId).state.label == "Road plate",
        "selecting Basic Sender clears only the override and restores the basic packet")

    assert(testState.registry:setDeviceState(plateId, { label = "Road plate", senderModule = { id = "Example.UnknownSender" } }))
    testState.registry, testState.java = start(save(testState.java))
    local value, _, attached = placedReading(displayId)
    check(value == nil and attached and runtime.inspect(wireId).sourcePacket == nil
        and testState.registry.network:record(plateId).state.senderModule.id == "Example.UnknownSender",
        "an unsupported saved sender stays installed and the linked display sees no live signal")
    assert(modeMenu("unavailable").options["Advanced Sender"])()
    check(placedReading(displayId) == 115, "choosing a supported module repairs the circuit")

    mass = 1200
    testState.registry, testState.java = start(save(testState.java))
    check(placedReading(displayId) == 120 and runtime.inspect(wireId).sourcePacket.value.amount == 1200
        and testState.registry.network:record(plateId).state.senderModule.id == "ZedComm.AdvancedSender",
        "same-build reload preserves wiring and sender selection and samples the new load")
    plateTile.overlappingVehicle = nil
    check(placedReading(displayId) == 0 and runtime.inspect(wireId).sourcePacket.basicValue == 0,
        "an empty advanced plate publishes a valid zero fallback")
    plateTile.overlappingVehicle = vehicle
    assert(testState.registry:unlink(wireId, plateId))
    value, _, attached = placedReading(displayId)
    check(value == nil and attached, "disconnecting the source clears the attached display")
    assert(testState.registry:link(wireId, plateId, "signal"))
    check(placedReading(displayId) == 120, "reconnect restores the current advanced fallback")

    local stale = assert(modeMenu("Advanced Sender").options["Basic Sender"])
    assert(target(plateTile, plateId, "pickup"))
    local item = carried[#carried]
    check(item:getModData().zedcommPlacement.state.senderModule.id == "ZedComm.AdvancedSender",
        "native placement state carries the installed sender through pickup")
    local replaced, sameId = runPlacement(plateTile, { kind = "place", item = item })
    assert(replaced and sameId == plateId)
    stale()
    assert(join(plateTile, wireId, false, plateId, "signal"))
    check(placedReading(displayId) == 120 and runtime.inspect(wireId).sourcePacket.type == "signal.advanced",
        "replacement keeps the module and rejects a stale action aimed at the picked-up object")
    getDebug = debugBefore
end

testState.finish()
