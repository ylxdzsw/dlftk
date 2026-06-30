/-
# Study: RoCE PFC pause ring deadlock witness

Fabric-side pause ring with **completion drain disabled** (`hostIngressCap := 0`):
switch buffers cannot hand off to hosts, so inter-switch packets accumulate and
PFC pause cannot clear. Documents the cyclic buffer dependency in isolation from
host CQ drain (full RDMA completion is a separate progress path).
-/
import DLFTK.RoCE.Topology.TwoSwitchLine
import DLFTK.Analysis

namespace StudyRoCEPfcDeadlock.PauseRing

open DLFTK DLFTK.RoCE.Topology.TwoSwitchLine
open Port

def P : Params :=
  { nPrio := 1, queueCap := 1, pauseThreshold := 1, resumeThreshold := 0,
    hostEgressCap := 2, hostIngressCap := 0 }

/-- Each switch input lane is full with pause asserted; hosts still hold egress. -/
def pauseRingInit : St :=
  { h0 := { egress := [[{ dest := 1, prio := 0 }]], ingress := [[]] },
    h1 := { egress := [[{ dest := 0, prio := 0 }]], ingress := [[]] },
    sw0 := { q := [{ input := sw0H0, out := sw0ToSw1, lane := 0 },
                  { input := sw0FromSw1, out := sw0ToH0, lane := 0 }],
             upstreamPaused := [true, true], downstreamPaused := [false, false] },
    sw1 := { q := [{ input := sw1H1, out := sw1ToSw0, lane := 0 },
                  { input := sw1FromSw0, out := sw1ToH1, lane := 0 }],
             upstreamPaused := [true, true], downstreamPaused := [false, false] } }

def pauseRingSys : System St :=
  { init := [pauseRingInit],
    progress := Step.progress P,
    env := fun _ => [] }

def fuel : Nat := 10_000

#eval pauseRingSys.reachableCount fuel
#eval pauseRingSys.reachableSaturated fuel
#eval pauseRingSys.findDeadlock hasWork fuel
#eval hasWork pauseRingInit
#eval (Step.progress P pauseRingInit).isEmpty

example : hasWork pauseRingInit = true := by native_decide
example : (Step.progress P pauseRingInit).isEmpty = true := by native_decide
example : (pauseRingSys.findDeadlock hasWork fuel).isSome = true := by native_decide
example : pauseRingSys.reachableSaturated fuel = true := by native_decide

end StudyRoCEPfcDeadlock.PauseRing
