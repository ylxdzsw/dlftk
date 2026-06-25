/-
# Study: one-layer CLOS cross traffic

Two hosts on a **2-plane** one-layer CLOS with cross traffic on plane 0.
Compares tight vs relaxed VOQ sizing under `CreditConservative` flow control.
-/
import DLFTK.Switch.Topology.OneLayerClos
import DLFTK.Analysis

namespace StudyClosFabric.OneLayerClos

open DLFTK DLFTK.Switch.Topology.OneLayerClos

def tightP : Params :=
  { nHost := 2, nPlane := 2, nLane := 1,
    voqCap := 1, hostIngressCap := 1, hostEgressCap := 1 }

def relaxedP : Params :=
  { nHost := 2, nPlane := 2, nLane := 1,
    voqCap := 2, hostIngressCap := 1, hostEgressCap := 1 }

def tightSys   : System St := crossTrafficSys tightP
def relaxedSys : System St := crossTrafficSys relaxedP

def fuel : Nat := 100000

#eval tightSys.reachableCount fuel
#eval relaxedSys.reachableCount fuel

#eval tightSys.reachableSaturated fuel
#eval relaxedSys.reachableSaturated fuel

#eval tightSys.findDeadlock hasWork fuel
#eval relaxedSys.findDeadlock hasWork fuel

example : tightSys.deadlockFree hasWork fuel = true := by native_decide
example : tightSys.reachableSaturated fuel = true := by native_decide
example : relaxedSys.deadlockFree hasWork fuel = true := by native_decide
example : relaxedSys.reachableSaturated fuel = true := by native_decide

end StudyClosFabric.OneLayerClos
