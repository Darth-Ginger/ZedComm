# Door smoke results

Build/commit: ______  PZ version: ______  Save: ______  Tester/date: ______

Use [the full setup, grants and procedure](networked-door-smoke-test.md). Restart PZ first. Enter Pass, Fail or Skip in each result cell and describe deviations. Offline tests are not gameplay evidence.

## Checkpoint 1 - independent controls and mounting

Live observation on `4dd32ec`: a barricade prevented the door from opening under network control. Door class and behavior after clearance were unrecorded. The board reported state from behind a north-facing door, where the leaf obscured the housing. Both-side interaction and the updated indicators remain open for retest.

| Check | Expected | Map door | Built door | Observation |
| --- | --- | --- | --- | --- |
| Fitting and interruption | Interrupted fitting keeps materials. Successful Basic fitting consumes two adapters, retains screwdriver. | | | |
| Open control | Positive opens once, zero closes. Held input does not chatter. | | | |
| Lock control | Closed door locks. Already-open door stays pending until closed. | | | |
| Both controls ON | Applied lock prevents new opening. | | | |
| Native manual interaction | Held network lock blocks both sides. Record whether this policy is accepted. | | | |
| Source unavailable | Attached Lock unlocks; attached Open closes. | | | |
| Physically unwired | Corresponding native function resumes. Original lock flags restored on detach. | | | |
| Obstructed or barricaded | Movement waits and applies the latest request after clearance. | | | |
| Four faces and two hinges | Housing stays on frame. Wires follow hinge jamb and remain visible over flooring. | | | |

Both-side policy accepted: ______
Console capture before reload: ______

## Checkpoint 2 - Advanced board

| Check | Expected | Result | Observation |
| --- | --- | --- | --- |
| Board geometry | 6x3, four fixed two-cell parts. Invalid drops preserve items. | | |
| Delayed close | Wait(1s) -> NOT -> AND closes an already-open door then applies pending lock. Countdown pauses with game. | | |
| Labels and direction | Names preserve identity, contacts and connections. Outputs are local actions. | | |
| Full inventory | Removal refuses without partial returns or lost wiring. | | |
| Successful removal | Two adapters and every installed module recovered. | | |

Measured Wait duration in unpaused real seconds: ______
Console capture before reload: ______

## Checkpoint 3 - native lifecycle and secret door

| Check | Expected | Map door | Built door | Observation |
| --- | --- | --- | --- | --- |
| Reload | Tier, board, labels and wires survive. Current inputs sampled. Pending timer restarts. | | | |
| Destruction | Both fixtures disappear. Wires remain with free ends. Replacement door starts unmodified. | | | |
| Secret-door conditions | Two qualifying loads plus removed crate open the door. Missing condition closes it. | | | |
| Secret-door reload | Saved circuit works after reload. | | | |
| Helper lifecycle | No duplicate, orphaned or lingering floor leads after reload/removal. | | | |

Console capture: ______

## Checkpoint 4 - independent Contact

| Check | Expected | Map door | Built door | Observation |
| --- | --- | --- | --- | --- |
| Contact only | Crafted contact fits without actuator pair or board. Native door stays manual. | | | |
| Closed | 255 on its direct output. Sensor and magnet sit together. | | | |
| Open | Valid 0 on its direct output. Contact visual shows separation. | | | |
| Locked but closed | 255. Position reporting does not claim lock status. | | | |
| Unavailable host | No signal, distinct from valid 0. | | | |
| Inputs and Contact | Each reads/acts on its own wire. An obstructed opener reports actual position. | | | |
| Independent removal | Removing either fixture preserves the other, its names and its wires. | | | |
| Combined fitting | Consumes matched pair plus crafted contact; interruption consumes nothing. | | | |
| Contact visual | Four faces and both hinges, jamb riser, floor lead, no overlap with actuator housing. | | | |
| Reload and cleanup | Name, wire and source survive reload. No duplicate lead/housing. Removal clears only Contact. | | | |

Console capture: ______

## Closeout

Failures and reproduction steps: ______
Skipped checks and reason: ______
Remaining policy decisions: ______
