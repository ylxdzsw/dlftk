/-
# Study: UB virtual-lane separation on CLOS fabric

Same hypothesis as `TwoHostStore.lean`, but hosts are on a one-layer CLOS
(plane 0) instead of a direct two-node link.
-/
import DLFTK.Compose.UbOnClos
import DLFTK.Analysis

namespace StudyUbVlSeparation.UbOnClos

open DLFTK.Compose.UbOnClos
open DLFTK.Protocol.UB

def sharedP : Params :=
  { nHost := 2, nPlane := 1, nDim := 1, cap := 1, window := 2,
    vlmap := VLMap.shared,
    voqCap := 1, hostIngressCap := 1, hostEgressCap := 1 }

def separateP : Params :=
  { sharedP with nDim := 2, vlmap := VLMap.separate }

def sharedSys : DLFTK.System St := crossTrafficSys sharedP
def separateSys : DLFTK.System St := crossTrafficSys separateP

def fuel : Nat := 10000

/-! ## Diagnostics -/

#eval sharedSys.reachableCount fuel
#eval separateSys.reachableCount fuel

#eval sharedSys.reachableSaturated fuel
#eval separateSys.reachableSaturated fuel

#eval sharedSys.findDeadlock hasWork fuel
#eval separateSys.findDeadlock hasWork fuel

/-! ## Machine-checked claims -/

example : separateSys.deadlockFree hasWork fuel = true := by native_decide

end StudyUbVlSeparation.UbOnClos
