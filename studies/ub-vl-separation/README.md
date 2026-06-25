# UB virtual-lane separation

**dlftk pin:** v0.1.0

## Motivation

Scale-up fabrics (UB, etc.) multiplex requests and responses on shared buffer
pools. A natural design puts both on one virtual lane; a common mitigation
dedicates lanes per message class.

## Approach

Two-node UB link, both hosts streaming non-posted stores. Compare `VLMap.shared`
vs `VLMap.separate`. Bounded BFS over the reachable set; claims via
`native_decide` with saturation witnesses.

## Key results

| design | states | result |
|--------|--------|--------|
| shared VL (req+resp on lane 0) | 1639 | **deadlocks** |
| separate VL (req→0, resp→1) | 18976 | **deadlock-free** |

Separating lanes breaks the req→resp dependency cycle.

**Code:** `TwoHostStore.lean` · **Journal:** [report.md](report.md)

```bash
lake build StudyUbVlSeparation
```
