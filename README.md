# dlftk — a Lean library for studying deadlock in scale-up fabrics

`dlftk` is a research framework for formalizing and studying **deadlock** in
scale-up interconnects (e.g. Huawei UB, Google Falcon, CXL). Rather than the
classic *routing* deadlock theory (Dally/Duato — channel dependency graphs), it
targets the deadlock class that actually dominates simple-topology scale-up
fabrics: **resource / flow-control / message-dependent deadlock**.

## What it models

The first protocol model (`DLFTK.UB`) is a **two-node, single-link UB segment**
carrying non-posted store traffic, with the four deadlock-relevant mechanisms:

1. **Credit-based flow control + egress buffer queue** — a sender needs a credit
   (a free peer ingress slot) per VL before transmitting; packets wait in a
   bounded egress queue.
2. **Virtual lanes (VL)** — independent buffer/credit pools; per-lane FIFO so a
   packet is only ever blocked by others on its own lane.
3. **Source-ordering** — bounded send window + FIFO replay buffer ("wait for
   earlier packets' ACKs before sending the rest").
4. **Link-level retry** — the replay buffer holds sent-but-unACKed packets for
   retransmission.

## Approach

Everything is an **executable transition system** (`DLFTK.System`). Deadlock is
defined *operationally*:

> a **reachable** state that still has outstanding **work** but from which
> **no progress step** (transmit / process / consume / ack) is possible.

For finite instances the reachable set is computed by a `HashSet`-based BFS
(`DLFTK.System.explore`) that reports whether it **saturated** (explored the
*exact* reachable set). Claims are then discharged by `native_decide` — no hand
proofs needed for the model-checking layer.

## First result (`DLFTK/UB/Scenario/TwoHostStore.lean`)

Two hosts streaming stores at each other:

| design                          | reachable states | result            |
|---------------------------------|-------------------|-------------------|
| **shared VL** (req+resp on VL 0) | 1639 (saturated)  | **deadlocks**     |
| **separate VL** (req→0, resp→1)  | 18976 (saturated) | **deadlock-free** |

The shared-VL deadlock witness is the textbook message-dependent cycle: both
nodes hold a request at the ingress head needing to *process* (→ emit a
response), but the egress lane that response must enter is full of a request
that cannot *transmit* because the peer's ingress is full (credit = 0).
Separating the classes onto independent VLs makes the class-dependency order
`resp ≺ req` acyclic, and the search proves no deadlock state is reachable.

## Layout

```
DLFTK/
  Core.lean        -- generic transition system + BFS reachability (HashSet)
  Analysis.lean    -- operational deadlock predicates + search
  UB/
    Types.lean       -- Node, Cls, VL, Pkt, VLMap policies
    Model.lean       -- Params, Side, St; credit/lane helpers
    Transitions.lean -- inject / transmit / process / consume / ack / retransmit
    Scenario/
      TwoHostStore.lean  -- the shared-vs-separate case study (native_decide)
```

## Build

```
lake build
```

Requires the Lean toolchain pinned in `lean-toolchain` (no Mathlib dependency
yet — the abstract wait-for-graph theory layer will add it later).

## Roadmap

- Abstract **wait-for-graph** master theorem (acyclic reachable WFG ⇒ deadlock
  free), parametric over protocol — the reusable theory layer (will use Mathlib).
- In-band ACK/credit-return path to expose pure flow-control (credit) deadlock.
- Posted writes (credit-only, no response) and longer message-dependency chains.
- Liveness / fairness (every store eventually completes) on top of safety.
- Additional fabrics: Falcon, CXL.mem.
