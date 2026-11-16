# Device definition registry - implementation proposal

Prepared 2026-11-09 after the verified cable/lamp spike (fix 7c8e5b5). Approved by Darth-Ginger with a check-in after each phase. Phases A through D are implemented and verified offline. The combined singleplayer smoke test is next. See the [contract, results and smoke steps](../device-definitions.md).

## Scope and contract

Implement criterion mn9d91a under Implement Endpoints And Cables. ADR-302 and ADR-308 require native and extension devices to register through the same seam. Definitions contain a stable ID, match predicate, source/receiver role, named ports and behaviour callbacks. Keep definition functions in code; save only identity and serializable device state. Map public receiver to the network model's existing sink role at the integration boundary.

Matching identifies eligible objects; it must never automatically modify or connect them. Untagged vanilla lamps remain untouched. Infrastructure forwarding, real placement/pickup timed actions, crafting, art, lamp-control policy and device naming are later work. A modified but unattached object keeps ordinary behaviour; an attached port without a source receives the OFF state.

The lamp pickup spike remains the persistence proof. Track the playable relay retrofit separately after the sensor-to-display MVP. It covers module installation, the shared lamp adapter, guarded switch control and the visible relay. See [relay retrofit architecture](../device-definitions.md#relay-retrofit-architecture) for the responsibilities and open decisions.

## Work packages and ownership


A. Definition contract (first): new shared/ZedComm/DeviceDefinitions.lua and tests/device_definitions_test.lua. Define register/get/match operations, validate IDs/roles/ports/callbacks, reject duplicates and ambiguous matches explicitly. Acceptance: deterministic lookup; malformed definitions rejected; native and third-party definitions use identical registration.

B. Native definitions (depends on A): new shared/ZedComm/Devices/PressureSensor.lua, Devices/NumericDisplay.lua and a native-definition bootstrap, with tests/native_devices_test.lua. Pressure returns 255 for player/zombie occupancy and 0 otherwise; display consumes the byte. Use a narrow context adapter so pure callback tests need no Java objects. Acceptance: player/zombie versus empty/non-actor occupancy tested; zero/nonzero and mixed-byte display values tested. Real item/sprite binding remains with placement work.

C. Persistence integration (depends on A): server/ZedComm/Registry.lua, narrowly scoped shared/ZedComm/Network.lua changes only where definition identity/state must round-trip, tests/registry_test.lua and tests/network_test.lua. Preserve existing cable saves and multiple pieces per square. Unknown definition IDs must be reported and preserved for recovery, not silently deleted. Acceptance: identity/state round-trip, duplicate reload registration avoided, missing-definition recovery, cable compatibility, functions never serialized.

D. Runtime integration and review (depends on B+C): new server/ZedComm/DeviceRuntime.lua plus SimulationRunner.lua and Dispatch.lua only where required. Sample loaded source objects before the existing dirty-network drain and deliver to attached receiver ports via definition callbacks. Explicitly distinguish no cable from attached/no-source; account for detach/topology changes so stale network IDs cannot leave a receiver stuck ON. Acceptance: sensor -> explicit cable -> display end-to-end test, no-source OFF, unattached object untouched, unload/reload without duplicate subscriptions. Document the extension contract in README/docs.


## Verification and release boundary

Run all existing 105 checks and new contract/native/runtime tests with next unavailable, using the installed game's global-object wrapper Lua for registry tests. Verify old cable save compatibility and missing definitions without data loss. Check diff and review callback isolation, load order and dirty-network ordering. Then conduct a short PZ smoke test with Darth-Ginger: clean startup, retained cable/lamp, and definition registration. Full physical sensor/display gameplay waits for real placement and assets. Hosted multiplayer remains unverified and outside this slice.

Phase B uses the stable IDs ZedComm.PressureSensor and ZedComm.NumericDisplay, each with a signal port. Phase A documents duplicate and ambiguous registration diagnostics in the contract. Do not add lamp switch-control policy or rename objects without a separate decision.
