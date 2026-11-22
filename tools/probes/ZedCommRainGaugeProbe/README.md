# Rain Gauge probe

Use a disposable singleplayer world with the integrated ZedComm build and its EnvironmentalSensors module. Copy the ZedCommRainGaugeProbe directory beside the local ZedComm mod, enable both, and start the game with debug mode. This probe uses the native component constructor from vanilla server/ClientCommands.lua (object.addWaterContainer). No recipe or art is required.

1. Stand outdoors on a clear tile. Run `gauge = ZedCommRainGaugeProbe.place(getPlayer():getSquare())` in the Lua debugger. The ID includes the coordinates. Use the existing Inspect circuit action to read the source.
2. Place an Advanced Display and a wire with a free end beside the probe. Inspect the wire ID. In the debugger run `ZedComm.Registry.instance:link("WIRE-ID", gauge, "signal")`. Verify an empty gauge shows 0 and Read full signal reports 0 L. A basic display on the same network should show signal loss.
3. Use debug weather to establish steady rain. At intensity 1 the fixture adds 1/60 L of tainted water per game minute, up to 1 L. Compare normal speed and fast-forward over equal game minutes. Pause, dry weather, shelter and snow should add zero. Place a second probe under a roof for comparison.
4. Use the game's fluid menu to transfer into a bottle. Verify both volumes change by the same amount. Empty the probe and check for 0 L. Record missing actions if the engine does not expose the native component on this object.
5. Part-fill the gauge, record the exact liters, then unload its chunk during rain. Return in dry weather and compare. Save, exit and reload in dry weather. Check the native content, exact packet, wiring and fluid menu again. The prototype tracks no elapsed time and stores no duplicate volume.
6. Record the build, observed amounts and actions. Component persistence, exterior behavior, fast-forward, UI accessibility and the saved wire require live verification before adding a craftable gauge.
