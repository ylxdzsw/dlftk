# dlftk

Research framework for **deadlock in scale-up interconnects** (Huawei UB,
Google Falcon, CXL). Classic routing-cycle theory (Dally/Duato) misses the
failure mode that dominates simple scale-up topologies: **resource,
flow-control, and message-dependent deadlock**.

## Approach

Each fabric design is an **executable transition system**: states, progress steps
(fabric doing work), and environment steps (offered load, faults). Deadlock is
defined operationally:

> a **reachable** state with outstanding **work**, but **no progress step** is
> possible.

For small, finite parameterizations we explore the reachable set by BFS and
check whether the search **saturated** (worklist emptied — the exact reachable
set, not a fuel-truncated slice). Safety claims are then discharged by
computation (`native_decide`) over that set — no hand proof for the
model-checking layer.

Studies compose reusable **models** (UB link, switch backpressure, CLOS
topology, …) and discharge concrete claims about a specific design choice or
failure scenario. Full research notes — failed attempts, rejected ideas,
parameter searches — live in each study's `report.md`.

For developing the library or starting a new study, see [AGENTS.md](AGENTS.md).

## Research

### [UB virtual-lane separation](studies/ub-vl-separation/)

Do store requests and responses deadlock when they share one virtual lane on a
two-node UB link? **Shared VL deadlocks** (1639 states); **separate VL
(req→0, resp→1) is deadlock-free** (18976 states). Establishes the
message-dependent req→resp cycle as the core UB failure mode.

### [CLOS fabric and broken-link failover](studies/clos-fabric/)

One-layer CLOS with parallel planes under conservative credit flow control.
Cross traffic is deadlock-free; after a plane fails, **failover to surviving
planes works** unless packets remain stuck in dead-plane egress or switch VOQs.
