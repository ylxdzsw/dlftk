/-
# Study: broken-link failover on one-layer CLOS

Plane 0 fails; plane 1 survives. Compares healthy failover vs stuck residual
buffers on the dead plane.
-/
import DLFTK.Switch.Topology.OneLayerClos
import DLFTK.Analysis

namespace StudyClosFabric.BrokenLink

open DLFTK DLFTK.Switch.Topology.OneLayerClos

def baseP : Params :=
  { nHost := 2, nPlane := 2, nLane := 1,
    voqCap := 1, hostIngressCap := 1, hostEgressCap := 1 }

def plane0BrokenP : Params := withBrokenPlane baseP 0

def fuel : Nat := 100000

/-! ## 1. Failover -/

def failoverSys : System St := crossTrafficOnPlaneSys 1 plane0BrokenP

#eval failoverSys.reachableCount fuel
#eval failoverSys.reachableSaturated fuel
#eval failoverSys.findDeadlock hasWork fuel

example : failoverSys.deadlockFree hasWork fuel = true := by native_decide
example : failoverSys.reachableSaturated fuel = true := by native_decide

/-! ## 2. Stuck egress -/

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

/-! ## 3. Stuck VOQ -/

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

/-! ## 4. Drain then failover -/

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

end StudyClosFabric.BrokenLink
