# ZedComm Terminology and Player Workflows

## Terminology

| Term | Definition | Example |
| --- | --- | --- |
| **Endpoint** | A world device that senses, acts, or does both. An installed adapter provides its network interface. | Pressure plate, lamp, numeric display |
| **Source endpoint** | A send-only device. Its adapter publishes the device's reading or state. | Button, player-operated switch, pressure plate, tripwire |
| **Receiver endpoint** | A receive-only device. Its adapter supplies a value or request the device can use. Actuators take ON/OFF requests. Readouts take values. | A lamp switches on, or a display shows a byte |
| **Dual-role endpoint** | A device that can both send and receive. Its fixture defines the directions and actions it supports. | A future door reports its open state and accepts a lock request |
| **Adapter** | The installed hardware interface between an endpoint and the wire. The fixture determines what the adapter can read or control. | A vanilla lamp gets an adapter so it can be wired |
| **Basic Adapter** | Connects an endpoint directly to the wire through a port appropriate to its role. | A pressure plate publishes a byte, or a lamp follows an on/off signal |
| **Advanced Adapter** | Connects an endpoint to the wire and hosts a small internal circuit. Target capacity is one or two modules, with the exact limit open. | A weight plate uses an internal threshold module before publishing to the wire |
| **Fixture binding** | Device-specific code that samples the world object or applies a request. This is the code behind the installed adapter. | Measures load on a plate or switches a powered lamp |
| **Module** | A component installed inside an Advanced Adapter or network cabinet. It adds a connection or processes an input. | Input extension, AND, threshold, adder |
| **Extension module** | Adds an external jack and an internal terminal. Its 2×1 footprint rotates in 90° steps and mounts with the jack against a host edge, facing out. | A second input feeds an AND module from the bottom edge |
| **Logic module** | Evaluates one or more inputs and produces ON/OFF. | AND, OR, XOR, or a threshold |
| **Arithmetic module** | Combines numeric signals and produces a numeric result. | Adder or subtracter |
| **Port** | An external jack where the player connects a wire. A port is free while it has no cable attached. | The output jack on a pressure plate's adapter |
| **Internal node** | A connection point in the host's circuit editor. A node represents a host input or output or a module terminal. | A threshold module's numeric input |
| **Module slot** | A place in the host layout where a module is installed. Its connections use the module's terminals. | A cabinet position occupied by an AND module |
| **Wired** | A port has a cable attached. Signal availability depends on the circuit. | A display stays wired after the source is disconnected |
| **Wire segment / wire run** | A segment is one placed piece. A run is a chain of explicitly joined segments. | The cable laid from a plate to a lamp |
| **Signal packet** | The latest value the network carries. A basic packet carries a 0–255 byte. A typed packet can carry a richer reading and a sender-supplied byte fallback. | Valid byte 0, or an estimated 1,150 kg with fallback 115 |
| **Infrastructure** | Equipment that processes or distributes signals within the network. | A splitter forwards one input to separate output runs |
| **Network cabinet** | A larger standalone host for internal circuits and modules. It exposes inputs and outputs to the external network. | A cabinet connects two incoming runs through an AND module to an outgoing run |

**Basic and Advanced are adapter hardware tiers.** The difference is capacity for local circuitry. Signal format is a separate choice. The Phase B prototype's Basic Sender and Advanced Sender labels refer to packet formats in that test. ADR-309 still describes the maintained packet transport. A gameplay rule for where typed payloads are useful remains open.

## Draft player workflows

| Workflow | What the player does | What they get |
| --- | --- | --- |
| **1. Craft an adapter** | Craft a Basic or Advanced Adapter directly from raw parts. Start with electronic scrap and wire for Basic, and more resources for Advanced. | An adapter ready to use in crafting, conversion, or an upgrade. Material counts, Electrical requirements, and a possible battery ingredient are balance decisions. |
| **2. Craft a native ZedComm endpoint** | Combine the device's body components with a compatible adapter. For example, craft a Basic Adapter and use it in the pressure plate recipe. | A finished endpoint with its adapter already fitted and ready to wire. |
| **3. Convert a compatible vanilla device** | Fit an adapter directly to a supported fixture such as a lamp. Use Basic for ordinary control, or Advanced to put a small circuit on the device. | The existing fixture gains a ZedComm interface. Its fixture binding defines supported sensing and actions. |
| **4. Upgrade an endpoint** | Replace its Basic Adapter with a separately crafted Advanced Adapter. Open the adapter to install and connect modules. | The same endpoint can run local logic. Recovery of the old adapter and whether the player reconnects the external cable remain open. |
| **5. Build an internal circuit** | Open an Advanced Adapter or cabinet. Place modules in its layout and connect their terminals to host inputs and outputs. Add input or output extensions where needed. | A circuit that can process signals along a complete input-to-output path. |

## Internal circuit editor

Use an inventory-style grid to arrange modules and explicit connections between terminals to define the circuit. Both host types start with **one built-in input and one built-in output**. Each occupies two grid cells, using the same footprint as an extension. Built-in parts are fixed in place and orientation. The player wires to their internal terminals. Removable modules use the remaining cells. Advanced Adapters fit one or two modules as a design target. Cabinets provide room for larger circuits. All removable modules rotate in 90° steps. The footprint, sprite, and terminals rotate together, and the terminals keep their identities and input or output roles. A 1×2 module becomes 2×1 after a quarter turn. Input and output extensions have an additional placement rule. Their jack must sit flush with an enclosure edge and face out. That allows extensions on the top, bottom, left, or right edge wherever the rotated footprint fits.

Draw modules as compact, top-down 1990s electronics sprites, with visible circuit boards, chips, sockets, and wire leads. Show the same part in the carried-modules pane and on the board, with terminals readable at grid scale. An input extension has an outward-facing network jack and an inward contact. An output extension has an inward contact and an outward-facing jack with a short outgoing lead as a visual cue. An AND module has two input contacts and one output lead. A drawn lead identifies the output; an actual link is made explicitly. Internal connections use wiring supplied by the host. External runs use the normal wire placement workflow.

A circuit is functional when there is a complete path from a host input to a host output and every module on that path has its required inputs connected. The editor should identify a missing input or output path. An incomplete path produces no live signal at its output. A valid zero is a live signal.

**Proposed endpoint port mapping.** The base input and output describe the internal circuit. On a source endpoint, the fixture supplies the internal input and the output reaches the external wire. On a receiver endpoint, the external wire supplies the input and the output goes to the fixture. A standalone cabinet exposes both base connections as external ports. Which extension nodes become external jacks on an endpoint, and whether those extensions count toward the adapter's one-or-two-module capacity, are decisions for the next design pass.

## Scope and first proof

The direct Basic circuit stays simple. Craft a plate with a Basic Adapter, fit a Basic Adapter to a lamp, then wire the two together. The lamp takes an ON/OFF request. A numeric display can still read the actual byte.

The first local-logic proof uses a Basic Adapter on the weight plate and an Advanced Adapter on the lamp. Install one Threshold module in the lamp adapter. The wire carries the plate's load byte. Set it to output **255** at **50 or above** and **0** below 50. The tested 80 kg player produced **8** and the sheriff car produced **115**, so that threshold separates those two loads. An occupancy plate could use the same module with a threshold of **3** counted actors.

Prove the host-to-module connections, valid zero, and behavior after cutting or removing a connection with one threshold module. Use that circuit to settle the editor behavior before expanding to multiple modules, cabinets, and arithmetic.

### Cabinet example - combined load

Connect adjacent weight plates to the cabinet's fixed input and an input extension. An Adder combines the two byte readings. A Threshold module compares the total with the configured trip point. An optional AND module combines the threshold's ON/OFF result with an arm switch on another input extension. The AND output goes to the cabinet's fixed output.

For example, two plate readings of 60 and 55 give a total of 115. At a threshold of 100, either plate alone leaves the output OFF. Together, they turn it ON while the arm switch is active. This adds the reported readings. A single vehicle overlapping both plates can contribute its full reported weight to both, so this example represents combined sensor output. A readout that needs a full weight or a unit can use typed data when scoped.
