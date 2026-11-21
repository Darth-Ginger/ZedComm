# Device definition contract

The shared registry at `ZedComm/DeviceDefinitions` holds the descriptors and callbacks used by native devices and extensions.

```lua
require "ZedComm/DeviceDefinitions"
local Definitions = ZedComm.DeviceDefinitions
local ok, reason = Definitions.register({
    id = "Example.PressureSensor",
    role = "source",
    ports = { "signal" },
    match = function(object, context)
        return context.isPressureSensor(object)
    end,
    sample = function(object, context)
        return context.isOccupied(object) and 255 or 0
    end,
})
```

The example shows registration. `DeviceRuntime` supplies the callbacks for the built-in devices.

- IDs use `Namespace.Name`, with each component beginning with a letter/underscore and continuing with letters, digits or underscores. Duplicate IDs are rejected, never overwritten.
- Roles are `source` or `receiver`. The server registry maps receiver to the model's `sink`; infrastructure is outside this endpoint contract.
- Ports are a nonempty, dense list of unique names using letters, digits and underscores, beginning with a letter/underscore. Their declared order is preserved.
- All definitions require a pure `match(object, context)` predicate returning a boolean. It must not mutate the world or register more definitions.
- Sources require `sample(object, context)`. A source returns a byte by default or a raw estimate when it declares `readingKind = "weight"`. The sender encodes the reading. A receiver names a receiver module (`receiverModule`) and supplies `bindFixture(object, context, config)`, which returns the fixture's `apply`, and optionally `isAvailable` and `release`. Receivers do not declare source sampling.
- Unknown definition fields are rejected so misspellings cannot silently pass.

`register(def)` returns `true`, or `false, reason`. Validation failures leave the registry unchanged. Registration copies the descriptor and port list; callbacks remain function references.

`get(id)` returns a descriptor copy or nil. Changing the returned descriptor or its ports does not modify the registry.

`match(object, context)` checks definitions in sorted ID order. It returns a descriptor copy for one match, nil without an error for no match (including a nil object), or `nil, reason` for ambiguity, a predicate exception, or a non-boolean predicate result. An error stops matching and never picks a partial winner. Ambiguity messages list matching IDs in sorted order. Callers must check the error return; it is not equivalent to no match.

Save records store definition IDs and durable state. Definitions and callbacks stay in code, and Lua's `require` cache keeps the registry loaded.

## Phase A verification

2026-11-09: 54 definition-contract checks and the existing 105 checks pass in Lua 5.1 with `next = nil`; registry tests use installed PZ Lua wrappers. Coverage includes native/extension registration, malformed definitions, duplicate IDs, defensive copies, unique/no/ambiguous matching, context forwarding and predicate errors. The Phase A tests cover registration only.

## Native definitions

`ZedComm/NativeDevices` loads the pressure sensor, occupancy plate, weight plate, numeric display, and other native definitions. Each calls the same `register` function available to extensions. The module reports a registration error with the device ID if the registry rejects the definition.

| Definition ID | Role | Port | Behaviour |
| --- | --- | --- | --- |
| `ZedComm.PressureSensor` | Source | `signal` | Emits its configured value (1 to 255, default 1) while an eligible actor, body, overlapping vehicle, loose item, or floor-level furniture occupies its tile. Eligible actors include players, zombies, and animals. Emits 0 when clear. |
| `ZedComm.OccupancyPlate` | Source | `signal` | Emits the number of players and zombies on its tile, capped at 255. Emits 0 with no counted actors. |
| `ZedComm.WeightPlate` | Source | `signal` | Samples estimated tile load. Basic Sender publishes rounded 10 kg steps, capped at 255. Advanced Sender publishes the full load and that same byte as a fallback. Empty is 0. |
| `ZedComm.NumericDisplay` | Receiver | `signal` | Forwards the byte unchanged and lights the indicator for nonzero values. Valid zero displays 0 with the indicator off. Attached unavailable input shows three dashes and turns the indicator off. See the [on-face display](numeric-display-face.md). |

These predicates compare the object's explicit definition ID. The runtime supplies these callbacks to connect definitions to world objects.

- `getDefinitionId(object)` returns the object's stable definition ID or nil. A native definition matches only its own ID.
- `getOccupantCount(object)` counts players and zombies on the loaded square up to 255. It excludes animals and avoids building a list of occupants.
- `isPressurePlateOccupied(object)` tests for actors, bodies, vehicle footprints, loose items and floor-level furniture on the basic plate's tile.
- `getWeightPlateLoad(object)` returns the estimated mass from eligible on-foot actors, a vehicle that intersects the tile, bodies, loose items, and qualifying furniture including stored contents. See [weight plate calibration and smoke test](weight-plate.md).
- `setDisplay(object, value, lit)` applies the reading and indicator. `value` is an integer from 0 to 255 for available input or nil for unavailable input. `lit` is a boolean. The display callback forwards nil separately from zero so the adapter can distinguish them.

Placed devices are registered by their world tags. The client renders a Numeric Display from its runtime reading.

### Phase B verification

2026-11-09. All 176 Lua 5.1 checks passed with `next = nil`, including 17 new native-device checks. The new suite loads the bootstrap and checks registration, identity matching, empty and occupied tiles, zero, mixed bytes, signal loss, and recovery. The registry suite used the installed PZ Lua wrappers. This phase used an in-memory fixture adapter.

## Relay retrofit architecture

Vanilla moveable data preserves the fitted lamp adapter through pickup and replacement.

- **Fixture adapter.** Eligible `IsoLightSwitch` lamps accept one Basic or Advanced Adapter using the same on/off receiver. The binding toggles only when the requested state differs from the lamp's switch state. The lamp uses its own power.
- **Reusable receiver module.** The basic on/off module owns the `signal` input. A valid nonzero byte requests on, and valid zero requests off. An attached cable with unavailable input requests off. With no cable attached, the lamp uses its normal controls. The module caches its last requested boolean per installation, so a change from 255 to 90 sends no additional request. Reconcile on attach or reload, and provide a retry path when a request could not be applied. A request and the fixture's actual state are separate.
- **Persistent installation.** Save the installed module identity and any durable configuration on the fixture. Derive the player-facing networked status from the installed module. Pickup retains the installation, while cable connections stay in the world. The last requested boolean is transient and can be rebuilt from the current input.
- **Circuit logic.** A cabinet can combine signals with AND, OR or XOR and drive a downstream run. An Advanced lamp adapter can apply local logic before the receiver acts.
- **Visual treatment.** An attached relay box follows the fitted adapter through power changes and cable disconnects.

The wire controls the lamp while attached. Signal loss requests OFF, and cable detach restores native switch control.

## Endpoint roadmap

An endpoint is a world device that supplies a reading, carries out an action, or supports both. The fixture adapter reads or acts on that particular device. A module owns the ports and the wire-facing behaviour. A sender publishes a reading. A receiver translates a signal into a fixture request. Infrastructure such as gates, switches, repeaters and hubs processes or distributes signals between segments. A network cabinet is an infrastructure host that can hold several modules. The medium carries signals and currently means wire.

| Candidate group | Endpoints | Role in the design |
| --- | --- | --- |
| Receive only | Lamp, Noisemaker, TV | Lamp actuation and numeric readouts are implemented. Noisemaker and TV are candidates for expanding receiver support. |
| Send only | Basic, occupancy and weight plates, switch, button, tripwire, PIR sensor | The fixture adapter supplies a reading or event for a sender module to publish. A player-operated switch is an endpoint here. A network switch that routes signals is infrastructure. |
| Send, receive, or both | Doors, windows, ladder | Doors have Lock and Open actuator inputs and a separate Contact source. Windows have a Contact source. Ladder behavior remains open. |

See [player workflows](terminology-and-player-workflows.md) for adapter, cabinet and wiring interactions.

## Persistence

The server registry loads native definitions before registering placed devices. A defined endpoint's world tag uses `id`, `kind = "endpoint"` and `definitionId`. An optional `state` table seeds the first registration. The definition supplies the role and port names. The registry maps `receiver` to the network model's `sink`. Placement writes the tag and the runtime resolves the loaded fixture from it.

The square record saves the definition ID, durable state and topology. Sources sample their live inputs after reload. After the first registration, the square record owns durable state. Loading the same world object again leaves that state intact. `registry:setDeviceState(id, state)` replaces the state and writes the square record. Passing nil clears the state. The registry copies state on input and when exporting a network record. State accepts plain tables with string or finite numeric keys and string, finite numeric, boolean or nested table values. Cycles, metatables, unsupported values and nesting beyond 32 tables are rejected before the record changes. Definition callbacks stay in code.

When a definition is missing on load, the registry reports it and preserves the saved role, ports, state and cable links. The unavailable sender yields no signal, and an unavailable receiver is omitted from delivery. The saved topology continues to reserve its connected ports. Reloading after the definition returns restores that topology and state. A world tag referencing a missing definition with no saved record is reported and can register after the definition returns. Legacy endpoints without a definition ID and existing cable records use their original format.

### Phase C verification

2026-11-09. All 203 Lua 5.1 checks passed with `next = nil`. The 27 new checks exercise registry save/load using the installed PZ Lua wrappers and an in-memory stand-in for the Java save store. They cover the native definition IDs, nested state, repeat registration, invalid state, legacy cable compatibility and missing-definition recovery. The test does not exercise the game's binary serializer. See the [combined smoke test](combined-smoke-test.md) for live checks.

## Runtime

The server tick prepares device bindings before draining dirty networks. The runtime caches definition copies, loaded fixture bindings, and delivery groups. Network topology changes refresh the source, receiver, and board lists. Registry load callbacks invalidate bindings on reused squares, and a missing square clears the corresponding transient reading.

Sources sample live inputs each tick. For example, weight plates still inspect furniture and its contents, and contact sensors check their native host. The sender encodes only a changed reading, module selection, or unavailable-to-available transition. The cache compares the full sensor value, so two different weights with the same fallback byte still reach an advanced receiver. An unloaded or failing source clears its signal and retains its saved topology.

One dispatch subscription delivers to loaded, attached receivers and cabinet inputs. A receiver that attaches, reloads, or regains power reconciles against the current signal. An attached display with no source reports no signal. Detaching clears its transient reading. Boards retain their input routing and reevaluate when a signal, timer, or power state changes.

### Phase D verification

2026-11-09. All 223 Lua 5.1 checks passed with `next = nil`. The 20 new registry checks run the actual tick handler against the installed PZ Lua wrappers with stubbed world objects and save data. They cover player and zombie activation, steady and zero input, cuts and reconnects, source and receiver unload, reload without duplicate subscriptions, and a sample callback failure. The test menu compiles in Lua 5.1. See the [combined smoke test](combined-smoke-test.md) for subsequent live results.

### Singleplayer smoke test

The pressure-rig placement menu used in the original Phase D test has been retired. To retest the pressure sensor with a player-built circuit, use the placement, signal, and reconnect steps in the [player placement guide](player-placement.md). Use the [display smoke test](numeric-display-face.md) for the byte rig and for signal-loss and reload checks.

Capture `console.txt` after the run. Relevant lines begin with `[ZedComm] display`, `[ZedComm] device`, or `[ZedComm debug]`.
