# CLOS fabric and broken-link failover

**dlftk pin:** v0.1.0

## Motivation

Scale-up clusters use parallel fabric planes (one-layer CLOS). When a
host↔plane link fails, can traffic continue on surviving planes?

## Approach

Compose `CreditConservative` switches into a full host–plane mesh. Model
bidirectional link faults via `linkUp` in `Params`. Four broken-plane scenarios
with BFS + `native_decide`.

## Key results

**Cross traffic (healthy fabric):** tight and relaxed VOQ sizing both
deadlock-free (80 / 304 states).

**Plane 0 failed:**

| scenario | result |
|----------|--------|
| failover to plane 1 | deadlock-free |
| packet stuck in dead-plane egress | **deadlocks** |
| packet stuck in dead-plane VOQ | **deadlocks** |
| drain host ingress, then failover | deadlock-free |

Failover works only if no residual work remains on the failed plane.

**Code:** `OneLayerClos.lean`, `BrokenLink.lean` · **Journal:** [report.md](report.md)

```bash
lake build StudyClosFabric
```
