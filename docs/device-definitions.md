# Device definition contract

Phase A implements a shared, code-only registry at `ZedComm/DeviceDefinitions`. It does not install tags, sample devices, deliver signals, or change save data. Native devices and extensions use exactly the same registration API.

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

The example context is illustrative; its game adapter will be defined in later phases.

- IDs use `Namespace.Name`, with each component beginning with a letter/underscore and continuing with letters, digits or underscores. Duplicate IDs are rejected, never overwritten.
- Roles are `source` or `receiver`. The later integration layer maps receiver to the model's `sink`; infrastructure is outside this endpoint contract.
- Ports are a nonempty, dense list of unique names using letters, digits and underscores, beginning with a letter/underscore. Their declared order is preserved.
- All definitions require a pure `match(object, context)` predicate returning a boolean. It must not mutate the world or register more definitions.
- Sources require `sample(object, context)`. A source returns a byte by default or a raw estimate when it declares `readingKind = "weight"`. The sender encodes the reading. A receiver names a receiver module (`receiverModule`) and supplies `bindFixture(object, context, config)`, which returns the fixture's `apply`, and optionally `isAvailable` and `release`. Receivers do not declare source sampling.
- Unknown definition fields are rejected so misspellings cannot silently pass.

`register(def)` returns `true`, or `false, reason`. Validation failures leave the registry unchanged. Registration copies the descriptor and port list; callbacks remain function references.

`get(id)` returns a descriptor copy or nil. Changing the returned descriptor or its ports does not modify the registry.

`match(object, context)` checks definitions in sorted ID order. It returns a descriptor copy for one match, nil without an error for no match (including a nil object), or `nil, reason` for ambiguity, a predicate exception, or a non-boolean predicate result. An error stops matching and never picks a partial winner. Ambiguity messages list matching IDs in sorted order. Callers must check the error return; it is not equivalent to no match.

Definitions and callbacks are not save records. Phase B adds native registration. Persistence of definition IDs and state follows in Phase C. Runtime sampling and delivery follow in Phase D. No public hot-reload/reset API is provided; standard require caching preserves the registry during normal loading.

## Phase A verification

2026-11-09: 54 definition-contract checks and the existing 105 checks pass in Lua 5.1 with `next = nil`; registry tests use installed PZ Lua wrappers. Coverage includes native/extension registration, malformed definitions, duplicate IDs, defensive copies, unique/no/ambiguous matching, context forwarding and predicate errors. In-game device integration remains untested because it is not part of Phase A.

## Phase B native definitions

`ZedComm/NativeDevices` loads the pressure sensor, occupancy plate, weight plate, numeric display, and other native definitions. Each calls the same `register` function available to extensions. The module reports a registration error with the device ID if the registry rejects the definition.

| Definition ID | Role | Port | Behaviour |
| --- | --- | --- | --- |
| `ZedComm.PressureSensor` | Source | `signal` | Emits its configured value (1 to 255, default 1) while an eligible actor, overlapping vehicle, or floor-level furniture occupies its tile. Eligible actors include players, zombies, and animals. Emits 0 when clear. |
| `ZedComm.OccupancyPlate` | Source | `signal` | Emits the number of players and zombies on its tile, capped at 255. Emits 0 with no counted actors. |
| `ZedComm.WeightPlate` | Source | `signal` | Samples estimated tile load. Basic Sender publishes rounded 10 kg steps, capped at 255. Advanced Sender publishes the full load and that same byte as a fallback. Empty is 0. |
| `ZedComm.NumericDisplay` | Receiver | `signal` | Forwards the byte unchanged and lights the indicator for nonzero values. Valid zero displays 0 with the indicator off. Attached unavailable input shows three dashes and turns the indicator off. See the [on-face display](numeric-display-face.md). |

These predicates compare the object's explicit definition ID. The game adapter will supply these callbacks to connect the definitions to real objects.

- `getDefinitionId(object)` returns the object's stable definition ID or nil. A native definition matches only its own ID.
- `getOccupantKinds(object)` returns a dense Lua list of occupant kinds on the sensor's loaded square. The runtime identifies `player`, `zombie`, and `animal` separately. The occupancy plate counts the first two. An empty list represents no supported moving occupants. Phase D handles whether a square is loaded before calling the sensor.
- `isPressurePlateOccupied(object)` tests for a supported actor, vehicle footprint, or floor-level furniture on the basic plate's tile.
- `getWeightPlateLoad(object)` returns the estimated mass from eligible on-foot actors, a vehicle that intersects the tile, and qualifying furniture with pickup weight or stored contents. See [weight plate calibration and smoke test](weight-plate.md).
- `setDisplay(object, value, lit)` applies the reading and indicator. `value` is an integer from 0 to 255 for available input or nil for unavailable input. `lit` is a boolean. The display callback forwards nil separately from zero so the adapter can distinguish them.

The adapter, actual item and sprite bindings, and display rendering are future work. The current tests drive the definitions through an in-memory adapter.

### Phase B verification

2026-11-09. All 176 Lua 5.1 checks passed with `next = nil`, including 17 new native-device checks. The new suite loads the bootstrap and checks registration, identity matching, empty and occupied tiles, zero, mixed bytes, signal loss, and recovery. The registry suite used the installed PZ Lua wrappers. Game startup and live device behaviour still require in-game validation.

## Relay retrofit architecture

The lamp pickup spike demonstrated that a mark can survive pickup, placement and reload through vanilla movable data. The playable relay retrofit is a separate work item after the sensor-to-display MVP. The spike remains test evidence.

- **Fixture adapter.** A compatible lamp accepts one receiver module in the proposed first retrofit. One adapter can serve eligible `IsoLightSwitch` models. It reads the lamp's actual switch state and applies the requested state only when they differ. If it uses the vanilla toggle, it toggles only on that mismatch. The lamp still uses its own power. Check which fixtures are eligible and verify the chosen switch call in-game.
- **Reusable receiver module.** The basic on/off module owns the `signal` input. A valid nonzero byte requests on, and valid zero requests off. An attached cable with unavailable input requests off. With no cable attached, the lamp uses its normal controls. The module caches its last requested boolean per installation, so a change from 255 to 90 sends no additional request. Reconcile on attach or reload, and provide a retry path when a request could not be applied. A request and the fixture's actual state are separate.
- **Persistent installation.** Save the installed module identity and any durable configuration on the fixture. Derive the player-facing networked status from the installed module. Pickup retains the installation, while cable connections stay in the world. The last requested boolean is transient and can be rebuilt from the current input.
- **Circuit logic.** Use dedicated infrastructure modules to combine independent signals with AND, OR or XOR and drive a downstream segment. Receivers interpret input for their own device. Gate semantics for unavailable inputs and boolean versus bitwise operations remain future design decisions.
- **Visual treatment.** Use a shared relay box or connector as the first visual prototype. Its presence follows the installed module even when the lamp is off or disconnected. Confirm attachment and placement behavior in-game before choosing a rendering technique.

For the first lamp retrofit, the wire controls the lamp while attached. The lamp’s native switch is ignored while wired and resumes normal control on detach. An attached lamp with no signal is still under wire control and defaults off. Networked switches and buttons are separate sender devices. A switch can hold an on/off state, while a button can send a timed pulse. The Phase A and B device contract and the one-port sensor and numeric display remain the basis for Phases C and D. The retrofit does not define a new save schema for this slice.

## Endpoint roadmap

An endpoint is a world device that supplies a reading, carries out an action, or supports both. The fixture adapter reads or acts on that particular device. A module owns the ports and the wire-facing behaviour. A sender publishes a reading. A receiver translates a signal into a fixture request. Infrastructure such as gates, switches, repeaters and hubs processes or distributes signals between segments. A network cabinet is an infrastructure host that can hold several modules. The medium carries signals and currently means wire.

| Candidate group | Endpoints | Role in the design |
| --- | --- | --- |
| Receive only | Lamp, Noisemaker, TV | A receiver module asks the fixture adapter to perform a supported action. Start with the lamp and the existing in-game Noisemaker as candidates for proving reuse. Decide the TV's supported actions when it is scoped. |
| Send only | Basic, occupancy and weight plates, switch, button, tripwire, PIR sensor | The fixture adapter supplies a reading or event for a sender module to publish. A player-operated switch is an endpoint here. A network switch that routes signals is infrastructure. |
| Send, receive, or both | Doors, windows, ladder | Scope the sensing and actuation capabilities individually. For example, a door could report its open state or accept an open/close request if its adapter supports it. Ladder capabilities are open. |

These are roadmap candidates. The pressure sensor and numeric display remain the current MVP. The module and fixture refactor can prove a shared on/off receiver with a second adapter before more endpoints are implemented. The playable lamp retrofit follows separately. Review visual cues at low priority once the installed hardware can be used in-game. Defer cabinets, slots and cabinet UI until a concrete circuit needs them.

## Phase C persistence

The server registry loads native definitions before registering placed devices. A defined endpoint's world tag uses `id`, `kind = "endpoint"` and `definitionId`. An optional `state` table seeds the first registration. The definition supplies the role and port names. The registry maps `receiver` to the network model's `sink`. Placement and runtime callbacks are separate work.

The square record saves the definition ID, current state, topology and existing source byte. After the first registration, the square record owns durable state. Loading the same world object again leaves that state intact. `registry:setDeviceState(id, state)` replaces the state and writes the square record. Passing nil clears the state. The registry copies state on input and when exporting a network record. State accepts plain tables with string or finite numeric keys and string, finite numeric, boolean or nested table values. Cycles, metatables, unsupported values and nesting beyond 32 tables are rejected before the record changes. Definition callbacks stay in code.

When a definition is missing on load, the registry reports it and preserves the saved role, ports, state and cable links. The unavailable sender yields no signal, and an unavailable receiver is omitted from delivery. The saved topology continues to reserve its connected ports. Reloading after the definition returns restores that topology and state. A world tag referencing a missing definition with no saved record is reported and can register after the definition returns. Legacy endpoints without a definition ID and existing cable records use their original format.

### Phase C verification

2026-11-09. All 203 Lua 5.1 checks passed with `next = nil`. The 27 new checks exercise registry save/load using the installed PZ Lua wrappers and an in-memory stand-in for the Java save store. They cover the native definition IDs, nested state, repeat registration, invalid state, legacy cable compatibility and missing-definition recovery. The test does not exercise the game's binary serializer. The in-game smoke test follows Phase D.

## Phase D runtime

The existing server tick prepares device bindings before draining dirty networks. The runtime resolves each defined endpoint by piece ID and definition ID on its loaded square. The pressure plates inspect the square's moving objects. The basic sensor publishes its configured occupied output and the occupancy plate publishes the player and zombie count. Changed bytes mark the network for the same tick. An unloaded or failing source yields no signal while retaining its saved topology. When the source returns, its availability change schedules a fresh update even if its byte stayed the same.

A single dispatch subscription delivers to loaded, attached receivers. A display that attaches, reloads or returns to a loaded square receives the current reading even with a steady source. An attached display with no source reports no signal. Detaching the display clears its transient test reading and stops delivery. The runtime keeps display readings in memory and reports changes to the console. The test menu reads that same state. The MVP runtime handles single-port definitions. Multi-port delivery and a visual display are future work.

### Phase D verification

2026-11-09. All 223 Lua 5.1 checks passed with `next = nil`. The 20 new registry checks run the actual tick handler against the installed PZ Lua wrappers with stubbed world objects and save data. They cover player and zombie activation, steady and zero input, cuts and reconnects, source and receiver unload, reload without duplicate subscriptions, and a sample callback failure. The test menu compiles in Lua 5.1. Live PZ behavior and binary saves remain to be verified in the combined smoke test.

### Singleplayer smoke test

The pressure-rig placement menu used in the original Phase D test has been retired. To retest the pressure sensor with a player-built circuit, use the placement, signal, and reconnect steps in the [player placement guide](player-placement.md). Use the [display smoke test](numeric-display-face.md) for the byte rig and for signal-loss and reload checks.

Capture `console.txt` after the run. Relevant lines begin with `[ZedComm] display`, `[ZedComm] device`, or `[ZedComm debug]`.
