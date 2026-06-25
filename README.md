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
  Switch/
    Types.lean              -- shared port/lane/VOQ helpers
    CreditConservative.lean -- routed ingress VOQ holds upstream credit
    CreditSplit.lean        -- ingress credit is freed on route-to-VOQ
    PFC.lean                -- threshold pause/resume per priority
    Topology/
      OneLayerClos.lean     -- one-layer CLOS: full host–plane mesh
    Scenario/
      OneLayerClos.lean     -- cross-traffic case study on 2 planes
      BrokenLink.lean       -- link-fault / failover vs stuck-traffic study
```

## Switch flow-control libraries

`DLFTK.Switch` provides selectable switch abstractions for future studies:

- `CreditConservative`: packet arrival immediately chooses an output and enters
  a VOQ; the VOQ is the upstream credit-accounted resource, so credit returns
  only when the packet transmits out of the switch. This simplifies dependency
  analysis and is conservative.
- `CreditSplit`: models common credit fabrics more directly: packet arrival
  consumes an upstream-facing ingress buffer, route-to-VOQ frees that ingress
  buffer and returns upstream credit, and downstream transmission consumes a
  separate next-hop credit.
- `PFC`: models Ethernet Priority Flow Control as threshold pause/resume state
  per input/priority, with downstream pause state controlled by the environment.

Each library exports its own `Params`, `St`, `system`, and `hasWork`, so a study
can choose the model by importing the corresponding module.

## One-layer CLOS topology (`DLFTK.Switch.Topology.OneLayerClos`)

Models a single switching stage with **P parallel planes** (switches). Every
host connects to every plane; plane `p` is a `CreditConservative` switch with
`nIn = nOut = nHost`. Packets traverse host egress → plane VOQ → host ingress.

The first scenario (`DLFTK/Switch/Scenario/OneLayerClos.lean`) places two hosts
on a 2-plane CLOS with cross traffic on plane 0 and machine-checks
deadlock-freedom under tight and relaxed VOQ sizing.

Link faults are modeled via a per `(host, plane)` `linkUp` mask. The broken-link
study (`DLFTK/Switch/Scenario/BrokenLink.lean`) shows that failover to
remaining planes works when routing avoids the failed plane, but **deadlocks** if
packets remain in dead-plane egress queues or switch VOQs.

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
