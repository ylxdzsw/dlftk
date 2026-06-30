/-
# Study: RoCE PFC pause wait-for graph analysis

Extracts pause-ring structure from deadlock states via `DLFTK.RoCE.Dependency`.
-/
import DLFTK.RoCE.Dependency
import DLFTK.RoCE.Topology.TwoSwitchLine
import PauseRing
import TwoSwitchLine

namespace StudyRoCEPfcDeadlock

open DLFTK DLFTK.RoCE
open TwoSwitchLineDep

/-! ## Pause-ring init exhibits a four-node WFG cycle -/

#eval linePauseCycle PauseRing.P PauseRing.pauseRingInit 0
#eval (lineWfg PauseRing.P PauseRing.pauseRingInit 0).hasCycle

example : linePauseCycle PauseRing.P PauseRing.pauseRingInit 0 = true := by native_decide

/-! ## Cross traffic: pause cycles may appear transiently but no deadlock carries one -/

def reachableDeadlockPauseCycle (sys : System Topology.TwoSwitchLine.St) (P : Params) (fuel : Nat) : Bool :=
  (sys.reachable fuel).any (fun s =>
    Topology.TwoSwitchLine.hasWork s
      && sys.progress s == []
      && linePauseCycle P s 0)

#eval reachableDeadlockPauseCycle TwoSwitchLine.crossSys TwoSwitchLine.P TwoSwitchLine.fuel
#eval reachableDeadlockPauseCycle PauseRing.pauseRingSys PauseRing.P PauseRing.fuel

example : reachableDeadlockPauseCycle TwoSwitchLine.crossSys TwoSwitchLine.P TwoSwitchLine.fuel = false :=
  by native_decide

example : reachableDeadlockPauseCycle PauseRing.pauseRingSys PauseRing.P PauseRing.fuel = true :=
  by native_decide

end StudyRoCEPfcDeadlock
