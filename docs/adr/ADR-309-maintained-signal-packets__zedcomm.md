---
project: zedcomm
created_date: "Thursday, November 12th 2026, 2:18:49 pm"
last_update: "Thursday, November 12th 2026, 2:34:35 pm"
adr-status: accepted
adr_domain: Architecture
adr_number: 309
aliases: []
authors:
  - Codex
  - Darth-Ginger
deciders:
  - Darth-Ginger
decision_topic: "Use Maintained Signal Packets"
decision_date: 2026-11-12
fileClass: adr
related-adr:
related-cards:
tags:
  - zedcomm
  - architecture
  - signals
---

# ADR-309: Use Maintained Signal Packets

## Context

ADR-301 defines a straight-through byte circuit in terms of eight logical lanes. The implementation already passes the byte as a number, and the live sensor, numeric display, and lamp tests exercised its value, availability, and recovery. The weight plate can now measure a load that an advanced endpoint could use at greater precision than the scaled byte. That creates a need for richer signals over existing wire runs while preserving the behavior of basic devices.

## Decision

Supersede ADR-301. A connected wire run carries the source's latest logical packet unchanged. The network models maintained values and availability. Serialization, lane representation, bit timing, and per-wire propagation time stay implicit. Each segment keeps one source under the existing topology rules.

- The Basic Sender publishes a `signal.basic` packet with an integer `value` from 0 to 255.
- The Advanced Sender publishes a `signal.advanced` packet with a typed `value`. That value can represent a larger number, text, or structured data. The sender can also supply an optional `basicValue` byte when it has a meaningful conversion.
- A basic receiver forwards the byte from a basic packet or the valid sender-supplied fallback from an advanced packet. A missing or invalid fallback yields no live signal for that receiver. A byte of 0 is valid.
- An advanced receiver forwards the typed advanced payload or the raw basic byte to its endpoint. The raw byte carries its transmitted precision and has no inferred units or measurement type. The fixture applies its own behavior to the representation it receives.

The sender publishes independently of receivers. Format selection and fallback use require no acknowledgement, negotiation, or receiver-specific sender state. Signal fidelity is determined for each sender and receiver pair. Different receivers can use different representations of the same published packet when topology supports fan-out.

A weight plate samples one estimated load. For a 1,150 kg estimate, a Basic Sender publishes 115. An Advanced Sender can publish the typed load of 1,150 kg with `basicValue = 115`. The existing byte display can consume the fallback, and an advanced display can consume the full estimate.

Recompute and deliver changed maintained values through the existing simulation pass. Compare packet content to determine whether the value changed. Preserve the distinct states of valid zero, unavailable signal, and physical detach. Persist device identity, wiring, configuration, and module selection. Basic Sender is the default. Both packet types rebuild from current source samples after reload. The first implementation slice uses a fresh test save to verify a direct weight plate to byte display circuit, the full packet in the inspector, fallback and signal loss, and reload on the same build.

## Consequences

### Positive

- Existing byte circuits and their fixture behavior carry forward.
- Sender and receiver module upgrades can expose richer signals on the same wire.
- Receiver compatibility stays local to each attachment. The sender supplies any fallback once, and the network can forward the packet as a whole.

### Negative

- Runtime validation, change detection, and diagnostics need to handle both packet formats through a single packet path.
- Advanced payloads need a defined type and shape. A basic receiver has no live reading when the sender omits a fallback.
- The maintained packet represents the latest state. Addressing, event delivery, and forwarding between separate segments require their own design decisions.

## Related

```dataview
TABLE
    file.folder AS "Folder",
    adr-status AS "Status",
    adr_domain AS "Domain",
    decision_topic AS "Topic",
    last_update AS "Updated"
FROM ""
WHERE contains(this.related-adr, file.link)
```
