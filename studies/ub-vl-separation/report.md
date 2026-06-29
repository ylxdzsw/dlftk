# Research journal: UB virtual-lane separation

**dlftk pin:** v0.1.0 · **Claims:** `TwoHostStore.lean`, `WFGAnalysis.lean`

## Question

Does sharing a virtual lane between store requests and responses create
message-dependent deadlock on a two-node UB link?

## Hypothesis

> Shared VL → message-dependent deadlock possible.
> Separate VL (req and resp on independent lanes) → deadlock-free.

This is the classic scale-up fabric failure mode: not routing cycles (Dally/Duato)
but **resource / flow-control / message-dependent** deadlock.

## Model

`DLFTK.UB.Transitions` — two hosts, one link, four mechanisms:

1. Credit-based flow control + egress queue
2. Virtual lanes (independent buffer/credit pools per lane)
3. Source-ordering (send window + replay buffer)
4. Link-level retry

**Documented assumption:** ACK/credit-return on a non-blocking side-band
(consume step returns credit directly). Under this assumption, the only deadlock
path is the req→resp message dependency — which is exactly what we test.

Parameters: `cap = 1`, `window = 2`.

## Workload

Both hosts inject store requests at each other (environment step). Progress:
transmit, process (req→resp), consume (resp sinks), linkAck.

## Results

| design | reachable states | saturated | result |
|--------|------------------|-----------|--------|
| shared (`nVL=1`, `VLMap.shared`) | 1639 | yes | **deadlock** |
| separate (`nVL=2`, `VLMap.separate`) | 18976 | yes | **deadlock-free** |

### Deadlock witness (shared VL)

Both nodes hold a request at ingress head, each needing to process → emit a
response. Each response needs a free egress slot on the **shared** lane, but
that lane is occupied by a request that cannot transmit (peer ingress full,
credit = 0). Classic message-dependent cycle.

### Why separate VL works

Response lane is never blocked by the request lane. Responses drain, credits
return, requests eventually complete. Search finds no deadlock state in the full
reachable set.

## Failed / rejected attempts

- **Unbounded sequence numbers** — rejected at model design time. Ordering is
  captured by send window + FIFO replay buffer; unbounded `seq` would inflate
  state space without adding ordering power (`DLFTK/UB/Types.lean`).

- **Hand-written proofs** — rejected for this layer. Finite instance + BFS +
  `native_decide` is the intended workflow for the model-checking tier.

- **In-band ACK path** — deferred. Side-band ACKs isolate message-dependent
  deadlock; in-band ACKs would expose pure credit-return deadlock (roadmap item).

## Parameter notes

`cap = 1`, `window = 2` chosen for small finite state space while still
exhibiting the shared-VL deadlock. Saturation at `fuel = 100000` confirms
results are over the exact reachable set, not fuel-truncated.

Separate-VL design explores more states (18976 vs 1639) because independent
lanes multiply reachable buffer/credit configurations — still saturates within
fuel budget.

## Open follow-ups

- Same hypothesis on longer dependency chains (posted writes, multi-hop)
- In-band ACK model to separate credit-only deadlock from message-dependent
- Mathlib-backed WFG theory (generalise beyond 2-node peer graphs)
- Analytic deadlock-freedom proof for separate VL (replace enumeration)

## Mathematical layer (`WFGAnalysis.lean`)

Alongside full BFS enumeration in `TwoHostStore.lean`, we extract **peer
wait-for graphs** from operational states (`DLFTK.UB.Dependency`):

| predicate | shared VL | separate VL |
|-----------|-----------|-------------|
| `reachableDeadlockMutualWait` | **true** (some deadlock has A⇄B wait) | n/a |
| `reachableDeadlockWFG` | **true** (deadlock + WFG cycle) | **false** |
| `reachablePartitionInv` | n/a | **true** (process blocked ↔ resp egress full) |

The shared-VL stall is the classic symmetric pattern: each node holds a request
at ingress, cannot produce a response because the shared egress lane is occupied
by a request stuck on zero credit / full peer ingress — mutual waiting in the
WFG. Separate VL breaks the cycle because response production depends only on
the response lane (`lanesPartitioned`).
