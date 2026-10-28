---
project: zedcomm
created_date: "Saturday, October 24th 2026, 10:47:50 pm"
last_update: "Saturday, October 24th 2026, 10:47:50 pm"
adr-status: accepted
adr_domain: Architecture
adr_number: 303
aliases: []
authors:
  - ChatGPT
deciders:
  - Darth-Ginger
decision_topic: "Deliver Unacknowledged State with Endpoint Failure Policies"
decision_date: 2026-10-24
fileClass: adr
related-adr: []
related-cards:
tags:
  - zedcomm
  - architecture
---

# ADR-303: Deliver Unacknowledged State with Endpoint Failure Policies

## Context

A sensor should publish without tracking whether a receiver exists. The display must distinguish valid zero from a broken connection and recover predictably after reconnection. Real-world simple binary wires do not inherently expose connection health; this is an intentional simulation abstraction.

Source: Design discussion. Darth-Ginger approved this record with the abstract OFF default and overridable endpoint-definition clarification. Implementation and validation have not yet occurred.

## Decision

Publish the sender's maintained byte without acknowledgements, delivery confirmation or receiver-specific sessions. Preserve connectivity separately from the byte: valid zero is not disconnected. The native MVP display defaults OFF when disconnected and automatically adopts the source's current value when continuity returns, without requiring a new toggle or sender awareness. Endpoints own their response to valid input and unavailable input. In future work, the default/fallback state will be part of the endpoint definition: the abstract endpoint defaults to OFF, and specific endpoint definitions must be able to override that default easily. The native MVP display uses the inherited OFF default. Future endpoint protocols may implement stateful behavior. UDP-like is an analogy for unacknowledged delivery only, not selection of UDP packets. OFF is the MVP failure default, not a universal safety claim. Do not require heartbeats, framing or repeated transmissions to maintain the current level.

## Consequences

### Positive

- Keeps sender behavior independent of receivers.
- Supports automatic recovery and clear diagnostics.
- Allows later endpoint-specific latching, alarms or session behavior without changing the default.

### Negative

- No end-to-end delivery guarantee or acknowledgement is provided.
- Explicit connectivity knowledge is more abstract than an unsupervised electrical switch.
- Fail-off can be inappropriate for other devices; those devices must define their own policy.

## Related

- Design and MVP
- Decision index

```dataview
TABLE file.folder AS "Folder", adr-status AS "Status", adr_domain AS "Domain", decision_topic AS "Topic", last_update AS "Updated"
FROM ""
WHERE contains(this.related-adr, file.link)
```
