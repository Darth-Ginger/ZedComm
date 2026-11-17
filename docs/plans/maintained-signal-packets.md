# Maintained Signal Packets Implementation Plan

**Goal** Prove ADR-309 with a weight plate, one existing wire run, the current numeric display, and a circuit inspector that shows the full payload.

**Architecture** A fixture samples the world. Its sender publishes a packet. The network holds and delivers the packet through the existing dirty-network pass. A basic receiver forwards the byte or the sender's fallback to its existing fixture adapter.

**Spec** [ADR-309: Use Maintained Signal Packets](../adr/ADR-309-maintained-signal-packets__zedcomm.md)

**Target** Project Zomboid Build 42 singleplayer, Lua 5.1 and the existing Workshop build.

## Proposed architecture

```text
Weight plate  ->  Sender module  ->  Wire run  ->  Basic receiver  ->  Numeric display
 raw load         latest packet                    byte or nil
                       |
                       +-> Inspect circuit shows packet and delivered byte
```

```lua
{ type = "signal.basic", value = 115 }

{
    type = "signal.advanced",
    value = { kind = "weight", amount = 1150, unit = "kg" },
    basicValue = 115,
}
```

The basic packet accepts integer values from 0 through 255. The first advanced payload is a finite, nonnegative weight estimate. The weight sender uses the existing rounding, minimum positive byte of 1 and cap of 255 to compute the fallback. Future payload kinds can define their own schema and optional byte projection. The current byte display and on/off receiver consume the byte or fallback through their existing behavior. A future advanced receiver can forward a basic byte with its format intact or hand its fixture the typed payload.

The network compares packet contents, holds one current packet per source and delivers it to the existing receivers. Keep the one-source rule, topology, and availability behavior. A missing or invalid fallback produces no live input for a basic receiver. Zero is a valid byte and a valid fallback. An attached display with no live input shows dashes. A detached display is blank.

Persist device identity, wiring, and configuration in the new build. Store an explicit sender selection in endpoint state as `senderModule = { id = "ZedComm.AdvancedSender" }`. Basic Sender is the default. Both packet types live in runtime state and rebuild from current samples after reload. An explicit incompatible module reports unavailable while preserving the record and wiring. Start live verification in a fresh disposable save.

## Phase A - Packet transport

**Files** `shared/ZedComm/SignalModules.lua`, `shared/ZedComm/Network.lua`, `shared/ZedComm/Simulation.lua`, `shared/ZedComm/Dispatch.lua`, `server/ZedComm/Registry.lua`, `server/ZedComm/DeviceRuntime.lua`, and the existing signal-module, network, simulation and registry tests. Lua paths are relative to the Build 42 mod's `media/lua` directory.

- [x] Add packet constructors, validation, value equality, and basic projection in `SignalModules.lua`. The network can use the packet helpers for validation and equality. Basic projection belongs at the receiver boundary. An invalid optional fallback is unavailable to a basic receiver while a valid advanced payload remains usable.
- [x] Replace numeric network publication and recompute with a single packet path. Update the registry, simulation and their callers together. Remove the live numeric source value from saved records and persist device configuration through the existing state path. Make the network own a snapshot of each accepted packet so mutating a caller's table cannot change the held value without a new publication.
- [x] Wrap the outputs of current sources as basic packets. Project incoming packets to a byte or nil at the existing receiver boundary, including byte callbacks. Keep attach, detach and fixture reconciliation working through the existing runtime.
- [x] Verify the current byte circuits and lamp behavior. Cover bytes 0 and 255, rejection of malformed basic packets, missing and invalid fallbacks, fallback 0, full payload change while its fallback stays the same, equal payload in a fresh table, table mutation after publication, and the existing one-source conflict rule. Save and reload a circuit built on this version. Verify links and configuration restore and the next sample supplies the current reading.

**Review checkpoint** Existing byte circuits use the packet transport with the same visible behavior.

Phase A passed 539 offline Lua 5.1 checks and the Windows Workshop build. The registry tests exercise same-build reload with saved configuration and wiring, followed by a fresh source sample. The in-game fresh-save pass remains Phase C.

The independent review found a dispatch ownership follow-up. Subscribers receive a shared packet snapshot. The current runtime subscriber treats it as read-only. Revisit subscriber isolation when adding a subscriber that needs to change a packet.

## Phase B - Selectable weight plate sender

**Goal** A weight plate can switch between a basic byte and an advanced weight packet. Inspect Circuit shows the selected packet and the existing display's byte reading.

**Scope** Build 42 singleplayer debug controls, sender selection on the weight plate, and offline verification. Phase C owns the in-game pass. The existing wire, packet delivery, and byte receiver from Phase A are reused.

### B1. Sample the load and encode it

**Files** `shared/ZedComm/DeviceDefinitions.lua`, `shared/ZedComm/Devices/WeightPlate.lua`, `shared/ZedComm/SignalModules.lua`. Tests in `tests/device_definitions_test.lua`, `tests/native_devices_test.lua`, and `tests/signal_modules_test.lua`.

- [x] Add definition tests for `readingKind = "weight"` on a source, rejected values on a receiver, and unchanged registration of byte-only sources.
- [x] Allow and copy the optional source field `readingKind`. The supported value in this slice is `"weight"`. A source without it still samples a byte. Update the weight plate to return the raw estimate from `context.getWeightPlateLoad(object)`.
- [x] Add `ZedComm.BasicSender` and `ZedComm.AdvancedSender` identifiers. Extend `Sender.encode(reading, readingKind, moduleId)` to default to Basic Sender. Basic Sender accepts a byte-only reading or a weight reading. Advanced Sender accepts a weight reading in this slice. Both weight modes use one conversion. Round to the nearest 10 kg, with a minimum of 1 for positive loads and a cap of 255. Basic publishes that byte. Advanced publishes the full weight in kg and includes the same byte as `basicValue`.
- [x] Verify the encoder with 0 kg, 2 kg, 75 kg, 1,150 kg, and 3,000 kg. Expected basic bytes and advanced fallbacks are 0, 1, 8, 115, and 255. Verify that an advanced reading of 1,150.25 kg retains the fractional amount, a byte-only source still carries its exact byte, and invalid weights or incompatible sender choices report an error.

### B2. Save and select the sender

**Files** `server/ZedComm/DeviceRuntime.lua`, `client/ZedComm/DebugCircuits.lua`, and `tests/registry_test.lua`. The current `Registry:setDeviceState` and placement record paths provide persistence.

- [x] Add runtime tests for a default weight plate, explicit advanced selection, switching back to basic, an invalid selection, and an unsupported saved module. Use the existing linked weight plate and display fixture.
- [x] Resolve the sender from `piece.state.senderModule.id` when present and pass it with `definition.readingKind` into the encoder. Add `Runtime.setWeightPlateSender(registry, id, moduleId)` returning success or a reason. Validate the target and module before saving, preserve unrelated state, and use `{ id = "ZedComm.AdvancedSender" }` for an advanced installation. Selecting Basic Sender restores the default by clearing the installation field. The next sample publishes the new format.
- [x] Treat an unsupported saved sender as unavailable. Preserve its saved module and wiring so the debug selector can repair it. Confirm the display stays attached and shows dashes until a supported sender publishes.
- [x] Add **ZedComm → Plate → Weight plate sender** with **Basic Sender** and **Advanced Sender** choices. Show the current choice, or unavailable for an unsupported saved module. Build the option for the targeted weight plate only. Resolve the selected object again when a menu action fires and route the change through the runtime setter. Exercise both choices through the real menu callbacks in the existing test harness.
- [x] Save and reload with Advanced Sender installed. Change the simulated load from 1,150 to 1,200 kg before the first new sample. Verify that the mode and links persist and the first packet carries 1,200 kg with fallback 120. Pick up and replace the plate and check that its module choice follows the item. Reconnect the existing wire to verify delivery resumes.

### B3. Inspect the packet and review the build

**Files** `server/ZedComm/DeviceRuntime.lua`, `client/ZedComm/DebugCircuits.lua`, `tests/registry_test.lua`, and the signal module and weight plate guides.

- [x] Return a `sourcePacket` snapshot from `Runtime.inspect(id, port)`. Derive the effective byte from that same snapshot. Format the existing **Inspect circuit** action to show `signal.basic` and the byte, or `signal.advanced`, the weight with units, and its fallback. Keep the receiver reading and the unavailable state visible. Show a fallback of 0 as 0.
- [x] Drive the same loaded plate in both modes. Verify the inspector changes from basic byte 115 to advanced 1,150 kg with fallback 115 while the display stays at 115. Change the load to 1,151 kg and verify the inspector updates the full payload while the display still reads 115. Verify source loss and reconnection through the existing runtime.
- [x] Run the full Lua 5.1 suite and Windows Workshop build. Record the debug controls, payload example, and offline results in the guides. Update the Phase B checkpoint and prepare the linked dev build for the fresh-save live test in Phase C.

**Review checkpoint** One wired weight plate can change sender modes through the debug menu. The inspector shows the full advanced payload and the existing display uses the sender's fallback. Same-build offline reload and pickup tests preserve the selected module and rebuild the current reading.

Phase B passed 576 offline Lua 5.1 checks and the Windows Workshop build. The live Build 42 smoke test is Phase C.

## Phase C - Singleplayer proof

- [x] Run the existing Lua 5.1 suite with `ZEDCOMM_REQUIRE_LUA=1 bash tests/run.sh` where a Lua interpreter is installed, or the verified Windows Lua 5.1 runner using the installed PZ Lua wrappers. Run `tools/build.ps1` for the Windows Workshop build and publish the verified linked dev build for the live test.
- [x] In a fresh disposable save, build a basic circuit. Verify the wire links, configured plate output and display response. Select the advanced sender on the weight plate and compare the full estimate and fallback in the inspector with the display. Clear the load and verify 0. Cut and reconnect the source and verify dashes then the current byte. Reload with the advanced sender selected and confirm the selection and wiring persist.
- [x] Capture the console and record the result. Use the direct-wire proof as the starting point for a separate repeater and splitter design. Crafting recipes, an advanced display, and cabinet UI are later slices.

**Live results, Build 42, 2026-11-16.** All steps passed in the Chunk 2 save. The basic sender gave `signal.basic 8 | receiver 8` for the player. With Advanced Sender selected, the readings were 80 kg with fallback 8, 155 kg with fallback 16 with a dragged zombie, and 0 kg with fallback 0 when clear, while the display read the fallback each time. Picking up the source wire gave no signal, and reconnecting restored the current reading. After a reload, 9 pieces loaded in 2 networks with Advanced Sender still selected, and the first sample read 80 kg with fallback 8. The capture shows no ZedComm errors: `the shared test-log folderchunk2-phase-c-20261116-console.txt`. The offline suite passed in CI (run 43879333090) and in a Lua 5.1 container.

**Review checkpoint** The direct-wire slice has live evidence for basic output, the advanced payload and fallback, signal loss, and reload within the new build.
