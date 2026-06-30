/-
# Study: RoCE PFC pause deadlock on a two-switch line

Cross traffic under tight buffers completes without deadlock. The classic PFC
pause ring appears when both directions hold switch occupancy with upstream
pause asserted — modeled as a congested initial state (cf. CLOS stuck-buffer
scenarios in `BrokenLink.lean`).
-/
import DLFTK.RoCE.Topology.TwoSwitchLine
import DLFTK.Analysis

namespace StudyRoCEPfcDeadlock.TwoSwitchLine

open DLFTK DLFTK.RoCE.Topology.TwoSwitchLine

def P : Params :=
  { nPrio := 1, queueCap := 1, pauseThreshold := 1, resumeThreshold := 0,
    hostEgressCap := 2, hostIngressCap := 1 }

def crossSys : System St := crossTrafficSys P

def fuel : Nat := 100_000

/-! ## Cross traffic (healthy) -/

#eval crossSys.reachableCount fuel
#eval crossSys.reachableSaturated fuel
#eval crossSys.findDeadlock hasWork fuel

example : crossSys.deadlockFree hasWork fuel = true := by native_decide
example : crossSys.reachableSaturated fuel = true := by native_decide

end StudyRoCEPfcDeadlock.TwoSwitchLine
