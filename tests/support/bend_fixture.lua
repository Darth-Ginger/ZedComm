return function(testState)
    local p0, w0, w1, d0 = testState.floorTile(40, 40), testState.floorTile(41, 40), testState.floorTile(41, 41), testState.floorTile(42, 41)
    local ok, plateId = testState.runPlacement(p0, { kind = "place", item = testState.give("ZedComm.PressurePlate") })
    assert(ok)
    local placed, displayId = testState.runPlacement(d0, { kind = "place", item = testState.give("ZedComm.NumericDisplay") })
    assert(placed)
    local laid, replacement = testState.lay(w0, testState.give("ZedComm.SignalWire"), plateId, "signal")
    assert(laid)
    local bent, secondWire = testState.lay(w1, testState.give("ZedComm.SignalWire"), replacement, false)
    assert(bent and testState.join(d0, secondWire, false, displayId, "signal"))
    assert(testState.runtime.setPressureOutput(testState.registry, plateId, "27"))
    p0.actors = { { class = "IsoPlayer" } }
    return p0, w0, w1, d0, plateId, displayId, replacement, secondWire
end
