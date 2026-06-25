# Research journal: CLOS fabric and broken-link failover

**dlftk pin:** v0.1.0 · **Claims:** `OneLayerClos.lean`, `BrokenLink.lean`

## Question

On a one-layer CLOS with parallel planes, can traffic failover to surviving
planes after a link/plane failure? When does residual state on the dead plane
cause deadlock?

## Hypothesis

1. Healthy cross traffic on `CreditConservative` CLOS is deadlock-free at small
   buffer sizes.
2. After plane failure, new traffic on surviving planes can proceed **if**
   routing avoids the dead plane and no packets remain in dead-plane buffers.
3. Residual egress or VOQ occupancy on the dead plane creates permanent deadlock
   under the operational `hasWork` predicate.

## Model

- `DLFTK.Switch.CreditConservative` — VOQ holds upstream credit until egress
- `DLFTK.Switch.Topology.OneLayerClos` — P planes, full host↔plane mesh

Packet path: host egress (plane p) → switch p VOQ → host ingress (plane p).

Fault model: `linkUp` mask per `(host, plane)`. Broken link disables
host→plane transmit and switch→host delivery. `hostDeliver` still works for
packets already in host ingress (local consume + downstream credit return).

Base params: 2 hosts, 2 planes, 1 lane, all capacities = 1.

## Part 1 — Cross traffic (`OneLayerClos.lean`)

### Workload

H0→H1 and H1→H0 cross traffic on plane 0 (`crossTrafficSys`).

### Results

| design | reachable states | saturated | result |
|--------|------------------|-----------|--------|
| tight (voqCap=1) | 80 | yes | deadlock-free |
| relaxed (voqCap=2) | 304 | yes | deadlock-free |

### Rejected / failed attempts

- **Expected tight cross traffic to deadlock** — false. Under
  `CreditConservative` credits, both flows can complete; no witness found across
  parameter grid (voq/ingress/egress caps 1–2, 1–2 planes).

- **Full environment inject** (all host×plane×dest×lane combinations) — explored
  for deadlock; 1053–5733 states depending on caps, all deadlock-free at
  cap=1–2. State space too large for some configs; cross-traffic-only env used
  for the main claims.

- **`CreditSplit` switch model** — not yet studied in this thread. May behave
  differently; deferred to a separate study.

## Part 2 — Broken plane 0 (`BrokenLink.lean`)

Plane 0 fully broken (`withBrokenPlane`). Plane 1 healthy.

### Scenario A: Failover

New cross traffic on plane 1 only (`crossTrafficOnPlaneSys 1`).

- 80 reachable states, saturated, **deadlock-free**.

### Scenario B: Stuck egress

Init: H0 has one packet queued for dead plane 0 egress.

- **Deadlocks.** `hostTransmit` disabled on broken link; packet never leaves;
  `hasWork` permanently true.

Witness: `{ hosts[0].egress[0] = [{dest:=1, lane:=0}], ... }`.

### Scenario C: Stuck VOQ

Init: plane 0 switch holds H0→H1 packet in VOQ (upstream credit consumed).

- **Deadlocks.** `switchTransmit` to H1 disabled (broken plane→host link); VOQ
  never drains; upstream credit not returned.

### Scenario D: Drain then failover

Init: H1 has ingress packet from plane 0 (credit-consistent: downstream credit
already consumed on switch). Workload: cross traffic on plane 1.

- 160 reachable states, saturated, **deadlock-free**.
- H1 `hostDeliver` drains dead-plane ingress despite broken link; then plane 1
  carries new traffic.

### Rejected / failed attempts

- **Ingress init without consuming switch downstream credit** — `hostDeliver`
  blocked (downCredit already at cap). Fixed `withHostIngress` to decrement
  switch downstream credit, modeling a completed switch→host transfer.

- **Misconfigured routing after fault** — if hosts keep injecting to dead plane,
  `hostInject` is blocked when `linkUp` is false; no new stuck packets from env,
  but pre-fault egress/VOQ state still deadlocks (scenarios B/C).

- **Partial link failure** (single host-plane pair) — not yet formalized;
  `withBrokenLink` helper exists, no dedicated claims yet.

## Parameter search log

Grid searched (cross traffic env): nHost∈{2,3}, nPlane∈{1,2},
voqCap/ingressCap/egressCap∈{1,2}. All saturated configs: **no deadlock**.
Relaxed VOQ only enlarges reachable set.

## Takeaways

1. Remaining planes are sufficient for new traffic after failover.
2. Dead-plane **residual buffers** (egress or VOQ) are the failure mode — not
   lack of alternate routing capacity.
3. In-flight packets at host ingress can drain locally; in-flight at switch VOQ
   on a dead plane cannot without flush/drop policy.

## Open follow-ups

- Explicit **flush/drop** recovery transitions on plane failure
- Partial link failure scenarios (`withBrokenLink`)
- `CreditSplit` vs `CreditConservative` under same CLOS topology
- Combine CLOS topology with UB store req/resp endpoints
