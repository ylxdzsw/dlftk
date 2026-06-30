# RoCE PFC pause deadlock

**dlftk pin:** v0.4.2

## Motivation

RoCE relies on **PFC (Priority Flow Control)** for lossless Ethernet. When switch
buffers fill, pause frames propagate across hops. A classic datacenter failure
mode is a **cyclic buffer dependency**: each hop waits on the next, and no
queue can drain.

## Approach

Two-host, two-switch line topology (`DLFTK.RoCE.Topology.TwoSwitchLine`) with
cross traffic on PFC priority 0. Claims use bounded BFS plus wait-for-graph
extraction (`DLFTK.RoCE.Dependency`).

## Key results

| scenario | states | result |
|----------|--------|--------|
| cross traffic (tight buffers) | 6336 | **deadlock-free** |
| pause ring (congested init, no host CQ drain) | 1 | **deadlocks** with WFG cycle |

Cross traffic completes under tight PFC thresholds. The pause ring witness
models fabric-side cyclic dependency with `hostIngressCap := 0` (completion
drain disabled) so switch buffers cannot hand off to hosts.

**Code:** `TwoSwitchLine.lean`, `PauseRing.lean`, `PauseWFG.lean` · **Journal:** [report.md](report.md)

```bash
lake build StudyRoCEPfcDeadlock
```
