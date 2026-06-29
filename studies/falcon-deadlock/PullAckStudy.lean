/-
# Study: Pull transaction ACK ablation

Is the pull request's **early ACK** (`ackReq`) necessary? What if pull were
simply one request and one response with no ACK-for-request and no
ACK-for-response?

We ablate `ackReq` / `ackData` on top of the existing Falcon step relation.
`sharedReqData` already models merged request/data windows with **late** release
(no early request ACK). This module adds explicit no-ACK variants on
`crCompliant` (separate windows) and pull-only traffic.
-/
import DLFTK.Falcon.Transitions
import DLFTK.Analysis

namespace StudyFalconDeadlock.PullAck

open DLFTK DLFTK.Falcon

def mkParams (design : ResourceDesign) (txnWindow : Nat := 1) : Params := {
  poolCap := 1,
  rxUlpReqCap := 1,
  sharedCap := 2,
  reqWindow := 1,
  dataWindow := 1,
  txnWindow := txnWindow,
  ordered := true,
  design := design
}

def pullOnlyEnv (P : Params) (s : St) : List St :=
  Step.inject P Peer.A .pull s ++ Step.inject P Peer.B .pull s

/-- Rebuild per-peer progress omitting selected ACK steps. -/
def perPeerNoAckReq (P : Params) (n : Peer) (s : St) : List St :=
  Step.scheduleTxn P n s
  ++ Step.transmitReq P n s
  ++ Step.transmitPush P n s
  ++ Step.targetPull P n s
  ++ Step.deliverPush P n s
  ++ Step.transmitData P n s
  ++ Step.landPullData P n s
  ++ Step.complete P n s
  ++ Step.ackData P n s

def perPeerNoAckData (P : Params) (n : Peer) (s : St) : List St :=
  Step.scheduleTxn P n s
  ++ Step.transmitReq P n s
  ++ Step.transmitPush P n s
  ++ Step.targetPull P n s
  ++ Step.deliverPush P n s
  ++ Step.transmitData P n s
  ++ Step.landPullData P n s
  ++ Step.complete P n s
  ++ Step.ackReq P n s

def perPeerNoAck (P : Params) (n : Peer) (s : St) : List St :=
  Step.scheduleTxn P n s
  ++ Step.transmitReq P n s
  ++ Step.transmitPush P n s
  ++ Step.targetPull P n s
  ++ Step.deliverPush P n s
  ++ Step.transmitData P n s
  ++ Step.landPullData P n s
  ++ Step.complete P n s

def progressNoAckReq (P : Params) (s : St) : List St :=
  perPeerNoAckReq P Peer.A s ++ perPeerNoAckReq P Peer.B s

def progressNoAckData (P : Params) (s : St) : List St :=
  perPeerNoAckData P Peer.A s ++ perPeerNoAckData P Peer.B s

def progressNoAck (P : Params) (s : St) : List St :=
  perPeerNoAck P Peer.A s ++ perPeerNoAck P Peer.B s

def mkSys (P : Params) (progress : Params → St → List St) : System St where
  init := [initSt]
  progress := progress P
  env := pullOnlyEnv P

def crP : Params := mkParams .crCompliant
def sharedReqDataP : Params := mkParams .sharedReqData

def crPullSys : System St := mkSys crP Step.progress
def crNoAckReqSys : System St := mkSys crP progressNoAckReq
def crNoAckDataSys : System St := mkSys crP progressNoAckData
def crNoAckSys : System St := mkSys crP progressNoAck
def sharedReqDataNoAckSys : System St := mkSys sharedReqDataP progressNoAck

def pullFuel : Nat := 10_000
/-- Partial BFS budget for CR pull-only (reachable set is >1M states). -/
def crPullFuel : Nat := 2_000_000

/-! ## Diagnostics -/

#eval crPullSys.reachableCount crPullFuel
#eval crNoAckReqSys.reachableCount pullFuel
#eval crNoAckDataSys.reachableCount pullFuel
#eval crNoAckSys.reachableCount pullFuel
#eval sharedReqDataNoAckSys.reachableCount pullFuel

#eval crPullSys.findDeadlock hasWork crPullFuel
#eval crNoAckReqSys.findDeadlock hasWork pullFuel
#eval crNoAckDataSys.findDeadlock hasWork pullFuel
#eval crNoAckSys.findDeadlock hasWork pullFuel
#eval sharedReqDataNoAckSys.findDeadlock hasWork pullFuel

/-! ## Machine-checked claims -/

/-- Separate windows + both ACKs: no deadlock in ≥1.3M reachable pull-only states.
`TwoPeerLoadStore` already certifies `crCompliant` on cross push/pull traffic. -/
example : crPullSys.deadlockFree hasWork crPullFuel = true := by native_decide

/-- Without request ACK (no early ACK), reqFlight never drains → deadlock. -/
example : (crNoAckReqSys.findDeadlock hasWork pullFuel).isSome = true := by native_decide
example : crNoAckReqSys.reachableSaturated pullFuel = true := by native_decide

/-- Without data ACK, dataFlight / target ULP-data pools never drain → deadlock. -/
example : (crNoAckDataSys.findDeadlock hasWork pullFuel).isSome = true := by native_decide
example : crNoAckDataSys.reachableSaturated pullFuel = true := by native_decide

/-- One request + one response with no ACK steps at all → deadlock. -/
example : (crNoAckSys.findDeadlock hasWork pullFuel).isSome = true := by native_decide
example : crNoAckSys.reachableSaturated pullFuel = true := by native_decide

/-- Merged window + no ACK at all: same pull-only deadlock class as `sharedReqData`. -/
example : (sharedReqDataNoAckSys.findDeadlock hasWork pullFuel).isSome = true := by native_decide
example : sharedReqDataNoAckSys.reachableSaturated pullFuel = true := by native_decide

end StudyFalconDeadlock.PullAck
