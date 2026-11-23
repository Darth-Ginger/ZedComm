---
adr-status: accepted
authors:
  - Claude
  - Darth-Ginger
deciders:
  - Darth-Ginger
decision_date: 2026-11-06
---

# ADR-306: Cable Runs Are Explicit Chains With One Source

## Context

Open decision 6 in the Design and MVP note left cable route ordering undecided. ADR-304 already requires cable ends to connect explicitly to equipment ports, so adjacency alone never terminates an endpoint. That left the question of how cable pieces connect to each other: by sitting on neighbouring squares, or by explicit links laid with the run.

Adjacency between cable pieces would make two parallel runs on neighbouring squares merge without anyone choosing it, and would let a single piece touch up to four others, which turns every run into a possible branch. The offline network model written on 2026-11-06 (`shared/ZedComm/Network.lua`) uses explicit connections.

A second question came with it: what a network does when more than one source drives it. Choosing a winner, merging values or routing between them all need rules the MVP does not need.

## Decision

A cable run is an explicit chain, like a linked list. Each cable piece has a start and an end and links to at most two neighbours: another cable piece on an orthogonally adjacent square on the same level, or a free endpoint port on its own or an adjacent square. Every connection is a link record made deliberately; being next to something never connects it.

Cables do not branch. Splitting a signal, joining paths or taking a second route is the job of an infrastructure device such as a hub or switch (ADR-307), not of the cable.

For the MVP a network carries exactly one source. A link that would put a second source on a network is refused, and a network found with more than one source (for example from a damaged save) is treated as disconnected. Multiple sources and routing between them are later scope.

## Consequences

### Positive

- Parallel runs stay separate no matter how closely they are laid.
- A run's shape is unambiguous, so the network is cheap to derive and to explain to the player.
- The one-source rule keeps the byte on a network well defined (ADR-301, ADR-303) with no arbitration.
- Branching has one clear future home, infrastructure devices, instead of special cases in the cable.

### Negative

- Laying a run needs a link step per piece, so the placement action must link each new piece to the previous one, and the UI must show free ends.
- Players cannot build a T or a fan-out from cable alone until infrastructure devices exist.
- Any later multi-source design has to revisit the refusal at link time.

## Related

- [ADR-302](ADR-302-separate-framework-endpoint-behavior__zedcomm.md)
- [ADR-304](ADR-304-retain-equipment-leave-cables__zedcomm.md)
- [ADR-307](ADR-307-four-network-object-roles__zedcomm.md)
