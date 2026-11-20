local testState = dofile("tests/support/placement_harness.lua")()
local LUA = testState.LUA
local check = testState.check
local square = testState.square
local worldObject = testState.worldObject
local save = testState.save
local fire = testState.fire
local start = testState.start
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


-- Render live bytes on the casing and leave other attachments alone.
do
    testState.registry, testState.java = start()
    local originalNew = IsoObject.new
    IsoObject.new = function(...)
        local object = originalNew(...)
        local setSprite = object.setSprite
        local attach, detach = object.addAttachedAnimSprite, object.RemoveAttachedAnim
        function object:setSprite(sprite)
            setSprite(self, sprite)
            self.faceChanges = (self.faceChanges or 0) + 1
        end
        function object:addAttachedAnimSprite(sprite)
            attach(self, sprite)
            self.faceChanges = (self.faceChanges or 0) + 1
        end
        function object:RemoveAttachedAnim(index)
            detach(self, index)
            self.faceChanges = (self.faceChanges or 0) + 1
        end
        return object
    end

    dofile(LUA .. "client/ZedComm/DisplayReadout.lua")
    local srcTile, wireTile, displayTile = floorTile(130, 125), floorTile(131, 125), floorTile(132, 125)
    local sourceId = "face-test-source"
    local source = IsoObject.new(srcTile, "zedcomm_devices_01_431")
    source:getModData().zedcomm = {
        id = sourceId, kind = "endpoint", definitionId = "ZedComm.DebugByteSource",
    }
    srcTile:AddTileObject(source)
    fire("OnObjectAdded", source)
    fire("OnTick")
    check(source.sprite == "zedcomm_display_01_1", "unwired test source displays configured zero")
    local placed, displayId = runPlacement(displayTile, { kind = "place", item = give("ZedComm.NumericDisplay") })
    assert(placed, displayId)
    local display = placement.resolve(testState.registry, displayId).object
    local prefix = "zedcomm_devices_01_"
    local function faceOf(object)
        local frames = {}
        local children = object:getAttachedAnimSprite()
        for i = 0, (children and children:size() or 0) - 1 do
            local name = children:get(i):getParentSprite():getName()
            frames[#frames + 1] = tonumber(name:sub(#prefix + 1))
        end
        table.sort(frames)
        return table.concat(frames, ",")
    end
    check(display.sprite == prefix .. "431" and faceOf(display) == "",
        "a newly placed, disconnected display has a blank face")

    display:setSprite(getSprite(prefix .. "2"))
    display:addAttachedAnimSprite(getSprite(prefix .. "16"))
    fire("LoadGridsquare", displayTile)
    check(display.sprite == prefix .. "431" and faceOf(display) == "16",
        "square load restores the blank casing and keeps other attachments")

    local laid, wireId = runPlacement(wireTile, { kind = "place", item = give("ZedComm.SignalWire") })
    assert(laid, wireId)
    assert(testState.registry:link(wireId, sourceId))
    assert(join(displayTile, wireId, false, displayId, "signal"))
    local samples = {
        { 0, 1 }, { 1, 2 }, { 85, 86 }, { 170, 171 }, { 255, 256 },
    }
    for _, sample in ipairs(samples) do
        assert(runtime.setTestByte(testState.registry, sourceId, tostring(sample[1])))
        check(placedReading(displayId) == sample[1] and display.sprite == "zedcomm_display_01_" .. sample[2]
            and faceOf(display) == "16",
            "the displayed byte has the expected digits and indicator for " .. sample[1])
    end
    local changesBefore = display.faceChanges
    fire("OnTick")
    check(display.faceChanges == changesBefore, "steady signals keep the same floor sprite")

    assert(testState.registry:unlink(wireId, sourceId))
    check(placedReading(displayId) == nil and display.sprite == "zedcomm_display_01_0" and faceOf(display) == "16",
        "attached signal loss swaps the reading for dashes with the indicator off")
    check(source.sprite == "zedcomm_display_01_256", "an unwired source still shows 255")
    assert(testState.registry:link(wireId, sourceId))
    check(placedReading(displayId) == 255 and display.sprite == "zedcomm_display_01_256",
        "restoring the source redraws its held byte")
    assert(testState.registry:unlink(wireId, displayId))
    check(placedReading(displayId) == nil and display.sprite == prefix .. "431" and faceOf(display) == "16",
        "detaching the display blanks the face and keeps unrelated attachments")
    assert(testState.registry:link(wireId, displayId))
    assert(runtime.setTestByte(testState.registry, sourceId, "85"))
    fire("OnTick")
    testState.registry, testState.java = start(save(testState.java))
    fire("LoadGridsquare", displayTile)
    check(placedReading(displayId) == 85 and display.sprite == "zedcomm_display_01_86" and faceOf(display) == "16",
        "reload rebuilds the current face from the saved signal path without duplicate digits")

    assert(target(displayTile, displayId, "pickup"))
    local recovered = carried[#carried]
    local restored, idAgain = runPlacement(displayTile, { kind = "place", item = recovered })
    local replacement = placement.resolve(testState.registry, displayId).object
    check(restored and idAgain == displayId and replacement.sprite == prefix .. "431" and faceOf(replacement) == "",
        "pickup and replacement start with a clean face")
    assert(join(displayTile, wireId, false, displayId, "signal"))
    check(placedReading(displayId) == 85 and replacement.sprite == "zedcomm_display_01_86" and faceOf(replacement) == "",
        "the replacement redraws its received byte after reconnect")

    local plateTile, leadTile, advancedTile = floorTile(130, 127), floorTile(131, 127), floorTile(132, 127)
    local platePlaced, plateId = runPlacement(plateTile, { kind = "place", item = give("ZedComm.WeightPlate") })
    local displayPlaced, advancedId = runPlacement(advancedTile,
        { kind = "place", item = give("ZedComm.AdvancedDisplay") })
    assert(platePlaced and displayPlaced)
    local wirePlaced, lead = lay(leadTile, give("ZedComm.SignalWire"), plateId, "signal")
    assert(wirePlaced and join(advancedTile, lead, false, advancedId, "signal"))
    assert(runtime.setWeightPlateSender(testState.registry, plateId, ZedComm.SignalModules.ADVANCED_SENDER))
    local advancedDisplay = placement.resolve(testState.registry, advancedId).object
    local amount = 1150.25
    plateTile.overlappingVehicle = { getMass = function() return amount end }
    local function glyphs()
        local out = {}
        local children = advancedDisplay:getAttachedAnimSprite()
        for i = 0, (children and children:size() or 0) - 1 do
            local frame = children:get(i):getParentSprite():getName():match("^zedcomm_weight_face_01_(%d+)$")
            if frame then out[#out + 1] = frame end
        end
        return table.concat(out, ",")
    end
    local byte, _, _, packet = placedReading(advancedId)
    check(byte == 115 and packet.value.amount == 1150.25 and glyphs() == "1,13,29,36,51,60,61",
        "the Advanced Display face shows 1150.3 and retains the exact packet for inspection")
    amount = 1150.42
    check(placedReading(advancedId) == 115 and glyphs() == "1,13,29,36,52,60,61",
        "the Advanced Display redraws when only the full reading changes")
    assert(runtime.setWeightPlateSender(testState.registry, plateId, ZedComm.SignalModules.BASIC_SENDER))
    check(placedReading(advancedId) == 115 and advancedDisplay.sprite == "zedcomm_display_01_116"
        and glyphs() == "", "a Basic signal restores the byte face without stale weight digits")
    IsoObject.new = originalNew
end

testState.finish()
