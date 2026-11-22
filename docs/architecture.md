# ZedComm Architecture Reference

ZedComm targets Project Zomboid Build 42 singleplayer. Server Lua owns world records and the simulation. Client Lua handles placement, context menus, board editing and visuals. Shared Lua holds the network and circuit rules.

## Topology and signals

- A run is an explicit chain with one source. A jack can remain wired when its source is unavailable. Valid zero, unavailable input and physical detach have distinct meanings.
- The network carries the latest packet. Basic uses an integer from 0 to 255. Advanced uses a typed reading and may supply a byte fallback. A Basic receiver with no usable fallback sees no signal. An Advanced receiver gets a Basic byte unchanged.
- Advanced `fluidVolume` packets carry a finite nonnegative amount in liters (`L`). They have no Basic fallback. An Advanced Display shows the numeric face and reports exact liters through Read full signal. Cache forwards volume through an Advanced output. Full Reading weight arithmetic requires weight operands.
- An adapter connects a fixture. A board module processes packets or adds a connection. Logic produces byte decisions, Cache preserves the incoming packet, and supported Full Reading arithmetic can produce typed weight. A cabinet output's mode controls what leaves its jack. Splitter branches are separate runs.
- Read [ADR-306](adr/ADR-306-cable-runs-as-chains__zedcomm.md), [ADR-309](adr/ADR-309-maintained-signal-packets__zedcomm.md) and [ADR-310](adr/ADR-310-board-signal-boundaries__zedcomm.md) for the design decisions.

## Device definitions

Register descriptors through **ZedComm/DeviceDefinitions**. Use a unique namespaced ID, the source or receiver role, a dense list of unique port names, and a pure boolean **match(object, context)**. The registry maps a receiver to a network sink. Native definitions load through **NativeDevices**.

- A source supplies **sample(object, context)**. It returns a byte or the declared raw reading type. The sender encodes it.
- A receiver names its receiver module and implements **bindFixture**. A single-port binding exposes **apply(request)**, optionally **isAvailable** and **release**. Apply returns **applied**, **unavailable**, or **unsupported**, with an optional reason. A board that drives multiple local actions binds one controller with an adapter per action.
- Registration validates and copies the descriptor and ports. Matching returns a copy for one match, no result for no match, and an error for ambiguous matches or an invalid predicate. Treat a matching error separately from an ordinary miss.
- World object tags identify the fixture by stable ID and definition ID. Use the shared tag reader in DeviceDefinitions. The registry restores lamp installation tags from native moveable data when needed.

## Persistence and runtime

The registry writes one global-object record per square and stores its pieces by ID. Save durable configuration and links in that record. Keep callbacks, sampled values, pending requests and active timers in runtime state. Validate plain, acyclic save state before replacement; the record accepts nested tables up to 32 levels. Missing definitions preserve saved topology and state until the definition is available again.

**SimulationRunner** runs the server update. **DeviceRuntime** samples loaded sources, refreshes bindings when needed, and builds delivery routes when topology changes. **Simulation** drains dirty networks. Receivers reconcile when their fixture is available again. Board timers and power changes can also trigger evaluation. The lamp follows native power and uses fail-off while attached. Door Lock and Open use the distinct policies in [ADR-311](adr/ADR-311-networked-door-control__zedcomm.md).

## Placement and Build 42 verification

The native Moveables bridge integrates supported items and pickup targets. The server placement command handlers validate reach, the selected item, and the target before applying a change. Fixture identity and durable state move with picked-up equipment; wires stay in the world. See [ADR-304](adr/ADR-304-retain-equipment-leave-cables__zedcomm.md).

Run **tests/run.sh** with Lua 5.1. Set **PZ_LUA** to the installed game's **media/lua** directory to include the native cursor suites. Offline harnesses do not prove Java-side behavior or sprite occlusion in a running save.

