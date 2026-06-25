# Study: UB virtual-lane separation

**dlftk pin:** `v0.1.0` (see `study.toml`)

## Question

Does sharing a virtual lane between store requests and responses create
message-dependent deadlock on a two-node UB link?

## Models

- `DLFTK.UB.Transitions` — two-node UB with credit, VL, source-ordering, retry

## Results

| design | reachable states | result |
|--------|------------------|--------|
| **shared VL** (req+resp on VL 0) | 1639 (saturated) | **deadlocks** |
| **separate VL** (req→0, resp→1) | 18976 (saturated) | **deadlock-free** |

## Build

From repo root:

```
lake build StudyUbVlSeparation
```

Standalone (pinned path dep during dev):

```
cd studies/ub-vl-separation && lake build
```
