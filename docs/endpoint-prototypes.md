# Endpoint prototypes and live proof

## Noisemaker

The stock item is `Base.NoiseTrap`. Installed Build 42's `media/scripts/generated/items/weapon.txt` sets `CanBePlaced`, `CanBeReused`, `NoiseDuration = 30`, `NoiseRange = 17` and `ExplosionSound = NoiseMakerActivate`. Vanilla `ISPlaceTrap:complete` consumes the carried item and calls `IsoTrap:place()`. The probe attaches to this existing world object.

Inspection of `projectzomboid.jar` with `javap -c -private zombie.iso.objects.IsoTrap` shows that `triggerExplosion()` raises `OnThrowableExplode(trap, square)`, plays the native sound and calls the native world-sound manager. A reusable weapon survives the trigger. Native `updateSounds()` controls playback, periodically emits world sounds, and stops them using its private `noiseStartTime`. The public `isExploding()` tests separate explosion fields. A quiet gap between sound clips can occur during the native noise cycle. Neither the public class interface nor the stock Lua placement path exposes an end-of-noise event or query. The base item defines no drainable battery or mains condition. Confirm this in a normal play session with power available and after shutoff.

### Singleplayer debug experiment

Load `tools/prototypes/noisemaker.lua` as a scratch debugger script and retain its returned table as `probe`. Place the vanilla item normally and select its `IsoTrap` world object. Call `session = probe.attach(trap)`. Observe any automatic vanilla activation independently and wait for its full native cycle to finish. Call `session:sample(255, true)` once. The last argument supplies the observer's explicit idle confirmation. Record the native start event, sound, world hour and movement of an unalerted zombie toward the fixture. Keep the player out of sight. Compare against an otherwise equivalent quiet interval. After full native completion, repeat on the same placed object. Confirm output zero and signal loss give no new starts, allow an existing cycle to finish, then pick up or unload the fixture and verify the old session cannot start it. Call `session:close()` at the end.

Automated held-high replay needs a reliable native completion observation across pauses, day-length settings, unload and reload. An elapsed-duration guess could overlap a cycle that resumed from a saved native clock. The probe uses manual observations and keeps playback entirely native. Actual attraction, power behavior and safe automatic replay still require live proof.

## Other proposals

| Fixture | Minimum prototype | Evidence required before release |
| --- | --- | --- |
| Momentary button | Attach one press action to a fixture and define its simulated pulse duration. | A connected receiver sees one rising and one falling edge per press, including rapid presses, pause, reload and pickup mid-pulse. |
| Tripwire | Pair two reachable anchors, validate the segment and sample actors crossing it. | Test crossing both directions, starting on the wire, diagonal movement, vehicles, walls, different floors and either anchor unloading or being removed. |
| Television | Bind an existing vanilla television through its native device state. | Inspect power source, switching and channel behavior, save/reload and ordinary player controls. Verify the native screen and sound respond once per commanded change. |
| Building lights | Identify the native switch and the lights it owns. | Exercise multiple switches in one room, overlapping rooms, mains failure, generator restoration, removed bulbs and reloading. Other rooms must keep their own state. |
| Grouped doors | Resolve all native leaves from each tile of a double or garage door. | Prove every face resolves the same group, collision follows every leaf, one command drives one transition, and missing or replaced leaves invalidate the binding. |
| Ladder | Identify climbable native geometry, action and authority over its availability. | Exercise ascent/descent, motion interrupted by power loss, absent landing, unloading mid-climb and clearing an occupied destination. |
| Larger and wall displays | Prototype a readable mounted face, projected digits and cable lead for each facing. | Test zoom, both wall sides, light levels, occlusion and pickup/replacement. Show 0, 1, 100, 255 and disconnected distinctly. |
