/-
# DLFTK.Switch.Scenario.BrokenLink — link-fault study on one-layer CLOS

Two hosts, two planes. **Plane 0 fails** (all host↔plane-0 links break). We ask
whether the cluster can keep working on the **remaining plane** (plane 1).

| scenario                         | workload / residual state        | result            |
|----------------------------------|----------------------------------|-------------------|
| **failover**                     | new cross traffic on plane 1     | **deadlock-free** |
| **stuck egress**                 | pkt queued on dead plane 0       | **deadlocks**     |
| **stuck VOQ**                    | pkt trapped in dead plane switch | **deadlocks**     |
| **drain then failover**          | pkt in host ingress on dead plane| **deadlock-free** |

The takeaway: failover to remaining planes works **only if** routing and
buffer state do not retain work on the failed plane. Residual packets in dead-
plane egress or switch VOQs create a **permanent livelock/deadlock** under the
operational `hasWork` predicate.
-/
import DLFTK.Switch.Topology.OneLayerClos
import DLFTK.Analysis

namespace DLFTK.Switch.Scenario.BrokenLink

open DLFTK DLFTK.Switch.Topology.OneLayerClos

def baseP : Params :=
  { nHost := 2, nPlane := 2, nLane := 1,
    voqCap := 1, hostIngressCap := 1, hostEgressCap := 1 }

/-- Plane 0 is entirely broken; plane 1 remains. -/
def plane0BrokenP : Params := withBrokenPlane baseP 0

def fuel : Nat := 100000

/-! ## 1. Failover: route new traffic on the surviving plane -/

def failoverSys : System St := crossTrafficOnPlaneSys 1 plane0BrokenP

#eval failoverSys.reachableCount fuel
#eval failoverSys.reachableSaturated fuel
#eval failoverSys.findDeadlock hasWork fuel

example : failoverSys.deadlockFree hasWork fuel = true := by native_decide
example : failoverSys.reachableSaturated fuel = true := by native_decide

/-! ## 2. Stuck egress: packet still queued for the dead plane -/

def stuckEgressInit : St :=
  withHostEgress plane0BrokenP (initClosSt plane0BrokenP) 0 0 1 0

def stuckEgressSys : System St :=
  { init := [stuckEgressInit],
    progress := Step.progress plane0BrokenP,
    env := Step.env plane0BrokenP }

#eval stuckEgressSys.reachableCount fuel
#eval stuckEgressSys.reachableSaturated fuel
#eval stuckEgressSys.findDeadlock hasWork fuel

example : (stuckEgressSys.findDeadlock hasWork fuel).isSome = true := by native_decide
example : stuckEgressSys.reachableSaturated fuel = true := by native_decide

/-! ## 3. Stuck VOQ: packet inside the dead plane's switch -/

def stuckVOQInit : St :=
  withSwitchVOQ plane0BrokenP (initClosSt plane0BrokenP) 0 0 1 0

def stuckVOQSys : System St :=
  { init := [stuckVOQInit],
    progress := Step.progress plane0BrokenP,
    env := Step.env plane0BrokenP }

#eval stuckVOQSys.reachableCount fuel
#eval stuckVOQSys.reachableSaturated fuel
#eval stuckVOQSys.findDeadlock hasWork fuel

example : (stuckVOQSys.findDeadlock hasWork fuel).isSome = true := by native_decide
example : stuckVOQSys.reachableSaturated fuel = true := by native_decide

/-! ## 4. Drain residual ingress on dead plane, then use plane 1 -/

def drainInit : St :=
  withHostIngress plane0BrokenP (initClosSt plane0BrokenP) 1 0 0 0

def drainThenFailoverSys : System St :=
  { init := [drainInit],
    progress := Step.progress plane0BrokenP,
    env := crossTrafficOnPlaneEnv 1 plane0BrokenP }

#eval drainThenFailoverSys.reachableCount fuel
#eval drainThenFailoverSys.reachableSaturated fuel
#eval drainThenFailoverSys.findDeadlock hasWork fuel

example : drainThenFailoverSys.deadlockFree hasWork fuel = true := by native_decide
example : drainThenFailoverSys.reachableSaturated fuel = true := by native_decide

end DLFTK.Switch.Scenario.BrokenLink
