---
adr-status: accepted
authors:
  - ChatGPT
deciders:
  - Darth-Ginger
decision_date: 2026-10-24
---

# ADR-303: Deliver Unacknowledged State with Endpoint Failure Policies

## Context

A sensor should publish without tracking whether a receiver exists. The display must distinguish valid zero from a broken connection and recover predictably after reconnection. Real-world simple binary wires do not inherently expose connection health; this is an intentional simulation abstraction.

The maintained level, OFF default and recovery behavior are implemented. Offline coverage includes unloading and reloading the source.

## Decision

Publish the sender's maintained byte without acknowledgements, delivery confirmation or receiver-specific sessions. Preserve connectivity separately from the byte: valid zero is not disconnected. The native MVP display defaults OFF when disconnected and automatically adopts the source's current value when continuity returns, without requiring a new toggle or sender awareness. Endpoints own their response to valid input and unavailable input. In future work, the default/fallback state will be part of the endpoint definition: the abstract endpoint defaults to OFF, and specific endpoint definitions must be able to override that default easily. The native MVP display uses the inherited OFF default. Future endpoint protocols may implement stateful behavior. UDP-like is an analogy for unacknowledged delivery only, not selection of UDP packets. OFF is the MVP failure default, not a universal safety claim. Do not require heartbeats, framing or repeated transmissions to maintain the current level.

### Unloaded source and receiver fallback

If a source tile or definition is unavailable, the circuit keeps its saved topology but has no live source byte. An attached receiver gets unavailable input, represented by nil. The default receiver delivery passes nil to its normal handler for the OFF state. A definition can supply an optional `onUnavailable(object, context)` callback to override that case. Valid zero still goes through `receive`. An unattached receiver does not receive network updates. When the source is loaded again, the simulation samples it before delivery and reconciles the receiver even if the byte matches the last saved reading.

## Consequences

### Positive

- Keeps sender behavior independent of receivers.
- Supports automatic recovery and clear diagnostics.
- Allows later endpoint-specific latching, alarms or session behavior without changing the default.

### Negative

- No end-to-end delivery guarantee or acknowledgement is provided.
- Explicit connectivity knowledge is more abstract than an unsupervised electrical switch.
- Fail-off can be inappropriate for other devices; those devices must define their own policy.
