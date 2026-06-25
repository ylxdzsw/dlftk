/-
# DLFTK.Switch.Scenario.OneLayerClos — first CLOS fabric case study

Two hosts on a **2-plane** one-layer CLOS, both offering cross traffic on
**plane 0** (lane 0). Each host queues a packet toward the peer; delivery
requires the full host → plane → host path with conservative credits.

We compare two buffer budgets:

* **tight**   — VOQ, host ingress, and host egress all capacity 1.
* **relaxed** — VOQ capacity 2 (more switch buffering headroom).

Under `CreditConservative` flow control, both designs are **deadlock-free** for
this cross-traffic workload; relaxing the VOQ only enlarges the reachable set.

Run the `#eval` lines to inspect reachability; the `example`s are checked by
`native_decide` together with saturation witnesses.
-/
import DLFTK.Switch.Topology.OneLayerClos
import DLFTK.Analysis

namespace DLFTK.Switch.Scenario.OneLayerClos

open DLFTK DLFTK.Switch.Topology.OneLayerClos

/-- 2 hosts, 2 parallel planes, 1 lane, tight buffers. -/
def tightP : Params :=
  { nHost := 2, nPlane := 2, nLane := 1,
    voqCap := 1, hostIngressCap := 1, hostEgressCap := 1 }

/-- Relaxed switch VOQ: extra headroom at the plane. -/
def relaxedP : Params :=
  { nHost := 2, nPlane := 2, nLane := 1,
    voqCap := 2, hostIngressCap := 1, hostEgressCap := 1 }

def tightSys   : System St := crossTrafficSys tightP
def relaxedSys : System St := crossTrafficSys relaxedP

def fuel : Nat := 100000

/-! ## Diagnostics -/

-- Reachable state counts (80 tight, 304 relaxed):
#eval tightSys.reachableCount fuel
#eval relaxedSys.reachableCount fuel

#eval tightSys.reachableSaturated fuel
#eval relaxedSys.reachableSaturated fuel

#eval tightSys.findDeadlock hasWork fuel
#eval relaxedSys.findDeadlock hasWork fuel

/-! ## Machine-checked claims -/

/-- **Tight buffers: deadlock-free** over the saturated reachable set. -/
example : tightSys.deadlockFree hasWork fuel = true := by native_decide

example : tightSys.reachableSaturated fuel = true := by native_decide

/-- **Relaxed VOQ: also deadlock-free**, with a larger reachable set. -/
example : relaxedSys.deadlockFree hasWork fuel = true := by native_decide

example : relaxedSys.reachableSaturated fuel = true := by native_decide

end DLFTK.Switch.Scenario.OneLayerClos
