# Falcon deadlock avoidance

Does Falcon's constrained-resource (CR) carving — dedicated pools, separate
request/data PDL windows, and separate initiator/target scheduler lanes — avoid
protocol deadlock under mixed load/store traffic?

## Approach

`DLFTK.Falcon.Transitions` models a two-peer connection with push (store) and
pull (load) transactions, RSN ordering, and four resource designs:

| design | Falcon rule |
|--------|-------------|
| `crCompliant` | CR Rules #1–#2 + UR ordering |
| `sharedTxRx` | violates CR #1 (shared Tx/Rx pool) |
| `sharedReqData` | violates CR #2 (merged request/data PDL window) |
| `sharedScheduler` | violates CR #2 (merged scheduler lanes) |

## Key results

| design | workload | result |
|--------|----------|--------|
| `crCompliant` | cross push/pull | **deadlock-free** |
| `sharedTxRx` | cross push/pull | **deadlock** |
| `sharedReqData` | pull-only | **deadlock** |

See `PullAckStudy.lean` for ACK ablation on pull-only traffic (early request
ACK, data ACK, and no-ACK variants).

**Code:** `TwoPeerLoadStore.lean` · **Journal:** [report.md](report.md)
