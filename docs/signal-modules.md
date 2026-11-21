# Signal modules and fixture adapters

The wire carries the current signal packet. Built-in sources default to basic packets with a byte from 0 to 255. The weight plate can use an advanced sender in debug mode. Nil means no live signal. A source publishes independently of receivers. A receiver holds its latest input for one attachment and asks the fixture to apply a request.

## Chunk 1 — shared module contract

`ZedComm/SignalModules` provides one generic sender and two receivers.

- `Sender.fromBoolean(active)` maps a real boolean to 255 or 0. A source that already has a byte supplies that value directly.
- `Sender.encode(value)` wraps a byte in a basic packet and returns nil when the reading is unavailable. The network owns packet change detection and source availability. The sender stores no state and gets no receiver acknowledgement.
- `ZedComm.OnOffReceiver` maps any valid nonzero byte to true and zero or unavailable input to false.
- `ZedComm.ByteReadoutReceiver` forwards the exact byte or nil. A valid zero remains distinct from no signal.

Create one receiver per fixture attachment with `newReceiver(moduleId, adapter)`. The adapter implements `apply(request)` as a method, where request is a boolean for on/off and a byte or nil for readout. Return `applied`, `unavailable`, or `unsupported`, with an optional reason. The adapter can also implement `release()` to return control to the fixture.

`receive(value)` records the input and applies the first request or a changed request. A repeated request stays quiet even when the raw byte changes from 85 to 170 in on/off mode. `reconcile()` explicitly reapplies the latest supported request after a fixture event such as power returning. A newer OFF supersedes a pending ON. Unsupported requests are not retried by availability events. An adapter exception is reported as unavailable and retains the request for an explicit retry. `detach()` clears transient state and calls release once. Attached no signal and detach are separate states.

The lamp adapter owns guarded switching. The Noisemaker adapter owns playback completion and can repeat locally while the held request is on. It never needs the sender to issue another packet. These fixture rules are covered with offline adapters in this chunk.

## Verification and checkpoints

2026-11-10. All 329 offline Lua 5.1 checks passed with `next = nil`, including 40 new checks. They cover validation, mixed bytes, deduplication, power recovery, stale-request replacement, detach and reattach, and the two fixture behaviors.

1. **Shared primitives.** `SignalModules.lua` and `tests/signal_modules_test.lua`. Implemented and ready for review.
2. **Runtime integration.** Implemented and ready for review. The existing pressure plate, debug source and numeric display use the modules in-game. Offline tests cover the attachment lifecycle, durable module configuration and legacy callbacks.
3. **Playable lamp retrofit.** Separate task. Validate the lamp API, fit an adapter, and verify power, wire control, detachment, and persistence. The next PC window can combine the shared-tile wire check, mixed-byte display regression, and lamp check after that prototype is ready.

## Chunk 2 — runtime and durable installation

Native byte sources publish through the basic sender. The pressure plate supplies 0 when empty and its configured byte when occupied, with a default of 1. The debug source supplies its configured byte. An unloaded source or nil reading marks the signal unavailable. The network owns the live packet and schedules delivery when its contents or availability change.

A modular receiver definition specifies `receiverModule` and `bindFixture(object, context, config)`. The binding returns an adapter. The runtime creates a receiver for one loaded attachment and releases it when the fixture or cable goes away. The numeric display uses the built-in Byte Readout and calls its existing display and clear helpers. Existing definitions using `receive` and optional `onUnavailable` keep that callback path.

A fixture with an explicit installation stores `state.module = { id = "ZedComm.ByteReadoutReceiver", config = { ... } }` in its device record. The fixture receives a copy of the configuration. The existing pickup path carries the record back into the selected inventory item and leaves the wire in the world. An old display with no module record uses the built-in module from its definition. An incompatible explicit module is reported and retained with its wiring. It receives no updates until the installation is corrected. Current input, requested state, and adapter instances are transient and rebuild after reload.

All 342 offline Lua 5.1 checks passed with `next = nil`, including 13 added checks for binding, durable state, reload, pickup, incompatible installations and legacy fallback. The installed PZ Lua wrappers ran with simulated world and inventory objects. Live PZ verification remains part of the next smoke session.

## ADR-309 Phase A - packet transport

The simulation carries one current packet per source through the existing network and dispatch pass. The network copies packets on publication and read, and compares their contents when deciding whether to schedule delivery. Source packets are live state. Saves store device configuration and wiring, and the runtime samples the source again on load.

Phase A routed the built-in sources through basic packets. The transport also accepts a typed advanced weight packet. The basic receiver boundary supplies its byte or sender-provided fallback to the existing fixture logic. An absent or invalid fallback gives the attachment no live input. A fallback of 0 is a valid reading.

Phase A verified the packet transport offline.

## ADR-309 Phase B - weight plate sender selection

The weight plate declares a weight reading and samples its full estimated load once. Basic Sender publishes the same scaled byte as before. Advanced Sender publishes the typed weight in kg and the equivalent byte fallback. For 1,150 kg, the advanced packet contains `value = { kind = "weight", amount = 1150, unit = "kg" }` and `basicValue = 115`.

On the plate, use **ZedComm → Plate → Weight plate sender** to select **Basic Sender** or **Advanced Sender**. The menu shows the current selection. Advanced is stored as `state.senderModule = { id = "ZedComm.AdvancedSender" }`. Selecting Basic clears the override. The module choice follows the plate through pickup and reload. An unsupported saved sender is retained and produces no signal until corrected.

**Inspect circuit** shows the source packet type, advanced load and units, fallback, and the display reading. A change from 1,150 to 1,151 kg updates the advanced payload and the inspector while the basic display stays at 115.

Phase B passed 576 offline Lua checks, including the real debug menu callbacks, selection persistence, and source loss and recovery. The fresh-save Build 42 test is Phase C.

## Future data signals

The current maintained byte is the starting point for a **Basic Sender** module. The endpoint signal contract uses logical packets tagged `signal.basic` or `signal.advanced`. The wire carries either packet through the same topology. The sender chooses what to publish independently of receivers. Each packet represents one game update, with serialization, bit timing, and frame internals kept implicit.

- A **Basic Sender** publishes `signal.basic` with a byte from 0 to 255. It can publish a byte supplied by the endpoint or apply the endpoint's documented byte conversion to a richer reading.
- An **Advanced Sender** publishes `signal.advanced` with a typed reading or structured payload. It can include an optional `basicValue` byte when the sender has a meaningful conversion. The sender computes that byte without negotiating with receivers.
- A **basic receiver** forwards the byte in a basic packet or the sender-supplied `basicValue` in an advanced packet. If the advanced packet has no valid fallback, the attachment sees no live signal. A fallback of 0 is valid.
- A future **advanced receiver** forwards the advanced payload or passes the raw basic byte to its attached endpoint. A basic byte carries no measurement type or unit. The endpoint applies its own device behavior to the input it receives.

### Weight plate example

The plate samples the same estimated load with either module. With a Basic Sender, it reports the existing rounded and capped byte, one step per 10 kg. With an Advanced Sender, it reports the full estimated load and its unit and can include that same scaled byte as `basicValue`. For a 1,150 kg estimate, a basic display receives **115** from either sender when the fallback is present. An advanced display receives the typed **1,150 kg** reading from the advanced packet. If it receives a basic packet with **255**, it gets the raw byte **255**.

### Electrical skill and crafting progression

Craft compatible devices with a basic module by default using modest Electrical skill and common parts. A more involved recipe can fit an advanced sender or receiver at craft time using higher Electrical skill and more materials. Players can also install a separately crafted advanced module into a compatible device as an upgrade and use the existing wire run. Exact skill levels, ingredients, and recipe availability are open balance choices.

Multi-byte data has period precedents. The 1981 Internet Protocol specification describes datagrams with data payloads, and early twisted-pair Ethernet offers a period reference for the technology. [RFC 791](https://www.rfc-editor.org/rfc/rfc791.html) · [IEEE 802.3i-1990](https://standards.ieee.org/ieee/802.3i/1068/)

## Planned stateful modules and signal probing

Latch holds its output after Set goes away and clears it on Reset. Counter holds its count until reset. Preserve both states across save and reload. An in-flight Pulse expires on reload. A one-shot circuit can use Latch to block repeat activation until reset, with Pulse providing a brief output.

The first Signal Probe is a read-only context action with no carried item required. It shows the run name, signal value and connected devices. For a later release, consider requiring a small carried Probe to see the run name and connected devices in the inspection view.
