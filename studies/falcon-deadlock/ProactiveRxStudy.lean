/-
# Study: proactive pull-response Rx allocation (OCP §8.2.2 Row B)

The OCP spec and SIGCOMM paper require the initiator to reserve Rx resources
for the incoming `pullData` **when the ULP offers the pull** — before sending
the `pullReq`. The `noProactivePullRx` design defers `rxUlpReq` until
`pullData` arrives, violating §8.2.2 Row B Col2.

Workload: peer `A` offers two pulls; `rxUlpReqCap = 1` but `poolCap = 2`
allows two outstanding **Tx** slots.

* `crCompliant` — second ULP pull is **rejected** at inject (cannot reserve a
  second Rx slot); only one transaction runs → deadlock-free.
* `noProactivePullRx` — both pulls are accepted (Tx only); out-of-order
  `pullData` can occupy the sole Rx landing slot and block the HoL response.
-/
import DLFTK.Falcon.Transitions
import DLFTK.Analysis

namespace StudyFalconDeadlock.ProactiveRx

open DLFTK DLFTK.Falcon

def mkParams (design : ResourceDesign) : Params := {
  poolCap := 2,
  rxUlpReqCap := 1,
  sharedCap := 2,
  reqWindow := 2,
  dataWindow := 2,
  txnWindow := 2,
  ordered := true,
  design := design
}

/-- Inject `n` sequential pulls from peer A (stops early if admission fails). -/
def initPulls (P : Params) (n : Nat) : List St :=
  let rec go (k : Nat) (s : St) : St :=
    match k with
    | 0 => s
    | k'+1 =>
      match Step.inject P Peer.A .pull s with
      | [s'] => go k' s'
      | _ => s
  termination_by k
  [go n initSt]

def mkSys (P : Params) : System St where
  init := initPulls P 2
  progress := Step.progress P
  env := fun _ => []

def crP : Params := mkParams .crCompliant
def noProactiveP : Params := mkParams .noProactivePullRx

def crTwoPullSys : System St := mkSys crP
def noProactiveTwoPullSys : System St := mkSys noProactiveP

def fuel : Nat := 200_000

/-! ## Diagnostics -/

#eval crTwoPullSys.reachableCount fuel
#eval noProactiveTwoPullSys.reachableCount fuel

#eval crTwoPullSys.findDeadlock hasWork fuel
#eval noProactiveTwoPullSys.findDeadlock hasWork fuel

/-! ## Machine-checked claims -/

/-- Proactive Rx admission: only one pull accepted when `rxUlpReqCap = 1`. -/
example : crTwoPullSys.deadlockFree hasWork fuel = true := by native_decide

/-- Without proactive Rx: both pulls accepted; OOO response blocks HoL → deadlock. -/
example : (noProactiveTwoPullSys.findDeadlock hasWork fuel).isSome = true := by native_decide
example : noProactiveTwoPullSys.reachableSaturated fuel = true := by native_decide

end StudyFalconDeadlock.ProactiveRx
