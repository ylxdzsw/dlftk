/-
# Study: Falcon deadlock avoidance (CR rules vs shared resources)

Two peers on one bidirectional Falcon connection. We compare Falcon's
constrained-resource (CR) design against violations of its deadlock rules.

Run `#eval` lines to inspect; the `example`s are machine-checked by `decide`.
-/
import DLFTK.Falcon.Transitions
import DLFTK.Analysis

namespace StudyFalconDeadlock

open DLFTK DLFTK.Falcon

def mkParams (design : ResourceDesign) (txnWindow : Nat := 2) : Params := {
  poolCap := 1,
  rxUlpReqCap := 1,
  sharedCap := 2,
  reqWindow := 1,
  dataWindow := 1,
  txnWindow := txnWindow,
  ordered := true,
  design := design
}

def crP : Params := mkParams .crCompliant
def sharedTxRxP : Params := mkParams .sharedTxRx
def sharedReqDataP : Params := mkParams .sharedReqData 1

/-- Cross load/store: A stores to B while B loads from A (symmetric). -/
def crossEnv (P : Params) (s : St) : List St :=
  Step.inject P Peer.A .push s ++ Step.inject P Peer.B .pull s
  ++ Step.inject P Peer.A .pull s ++ Step.inject P Peer.B .push s

/-- Pull-only workload: both peers issue loads (pull transactions). -/
def pullOnlyEnv (P : Params) (s : St) : List St :=
  Step.inject P Peer.A .pull s ++ Step.inject P Peer.B .pull s

def mkSys (P : Params) (env : Params → St → List St) : System St where
  init := [initSt]
  progress := Step.progress P
  env := env P

def crSys : System St := mkSys crP crossEnv
def sharedTxRxSys : System St := mkSys sharedTxRxP crossEnv
def sharedReqDataSys : System St := mkSys sharedReqDataP pullOnlyEnv

/-- BFS iteration budget for cross-traffic workloads (large reachable sets). -/
def crossFuel : Nat := 2_000_000
def pullFuel : Nat := 10_000

/-! ## Diagnostics -/

#eval crSys.reachableCount crossFuel
#eval sharedTxRxSys.reachableCount crossFuel
#eval sharedReqDataSys.reachableCount pullFuel

#eval crSys.findDeadlock hasWork crossFuel
#eval sharedTxRxSys.findDeadlock hasWork crossFuel
#eval sharedReqDataSys.findDeadlock hasWork pullFuel

/-! ## Machine-checked claims -/

example : crSys.deadlockFree hasWork crossFuel = true := by native_decide

example : (sharedTxRxSys.findDeadlock hasWork crossFuel).isSome = true := by native_decide

example : (sharedReqDataSys.findDeadlock hasWork pullFuel).isSome = true := by native_decide
example : sharedReqDataSys.reachableSaturated pullFuel = true := by native_decide

end StudyFalconDeadlock
