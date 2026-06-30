# Research journal: RoCE PFC pause deadlock

**dlftk pin:** v0.4.2 · **Claims:** `TwoSwitchLine.lean`, `PauseRing.lean`, `PauseWFG.lean`

## Question

Does bidirectional cross traffic on a two-switch RoCE line deadlock under PFC
pause propagation? When does the classic pause ring appear?

## Hypothesis

1. Tight PFC thresholds + small buffers on a line topology can create a
   **pause cycle** (H0→SW0→SW1→H1 and reverse).
2. With host completion drain enabled, cross traffic may still complete if
   packets can exit the fabric to host ingress.
3. Fabric-side cyclic dependency is exposed when switch→host delivery is
   blocked (buffers cannot drain).

## Model

- `DLFTK.RoCE.Topology.TwoSwitchLine` — H0–SW0–SW1–H1 line
- `DLFTK.Switch.PFC` — threshold pause/resume per `(input, priority)`
- `DLFTK.RoCE.Dependency` — four-node line WFG (H0, SW0, SW1, H1)

**Documented assumptions:** one packet per RDMA operation; no go-back-N or
ECN/CNP; PFC pause is per-priority head-of-line blocking within the lossless
class.

Base params: `nPrio = 1`, `queueCap = 1`, `pauseThreshold = 1`,
`resumeThreshold = 0`, `hostEgressCap = 2`.

## Part 1 — Cross traffic (`TwoSwitchLine.lean`)

Workload: H0→H1 and H1→H0 inject on priority 0 (`crossTrafficSys`).

| config | reachable | saturated | deadlock |
|--------|-----------|-----------|----------|
| tight (`hostIngressCap = 1`) | 6336 | yes | **none** |

Pause cycles appear transiently in the reachable set, but every such state still
admits a progress step — cross traffic drains to completion.

### Library fix during this study

`TwoSwitchLine` forwarding and delivery used wrong VOQ input ports (host traffic
was queued on `sw0H0` but `forwardSw0ToSw1` read `sw0FromSw1`). Fixed:

- `forwardSw0ToSw1` / `forwardSw1ToSw0` — host input ports
- `deliverSw0ToH0` / `deliverSw1ToH1` — inter-switch input ports

Without this fix, host packets never left the ingress switch and the model
reported spurious deadlocks.

## Part 2 — Pause ring witness (`PauseRing.lean`)

With `hostIngressCap := 0` (completion drain disabled), a congested initial
state places one packet on every switch input lane with all PFC pauses asserted.
No progress step is possible; `hasWork` remains true.

| check | result |
|-------|--------|
| `progress` empty at init | **true** |
| `findDeadlock` | witness = init |
| `linePauseCycle` | **true** (H0⇄SW0⇄SW1⇄H1 ring) |

This isolates the **fabric-side** pause ring from host CQ drain. Enabling
`hostIngressCap ≥ 1` lets `deliverSw0ToH0` / `deliverSw1ToH1` drain inter-switch
packets and break the ring (or PFC resume on empty lanes unblocks forwarding).

## WFG layer (`PauseWFG.lean`)

| predicate | cross traffic | pause ring |
|-----------|---------------|------------|
| `reachableDeadlockPauseCycle` | **false** | **true** |
| `linePauseCycle` at deadlock | n/a | **true** |

## Takeaways

1. Tight PFC on a two-switch line does **not** deadlock under cross traffic
   when host completion drain is enabled.
2. The pause ring is real: full input-lane occupancy + asserted pause in all
   directions creates a WFG cycle with no fabric progress.
3. Host CQ drain (or PFC resume on idle lanes) is what breaks the ring in
   practice — an explicit recovery policy question for studies.

## Open follow-ups

- Reachable pause-ring deadlock under sustained cross traffic (without disabling
  host ingress)
- `RoCE.Topology.OneLayerClos` PFC study (multi-plane)
- Couple with Falcon or UB endpoints on PFC fabric
- Downstream pause wiring between peer switches (currently via upstream pause on
  peer only)
