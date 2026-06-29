/-
# DLFTK.Falcon.Model — Two-peer Falcon connection with resource pools

We model **one bidirectional Falcon connection** between peers `A` and `B`, with
the deadlock-relevant transaction-layer structure from Falcon §8.2–8.4 (OCP v1.1)
and §4.5 / Fig. 6 (SIGCOMM).

## Spec correspondence (what we model)

| Mechanism | OCP / paper | Model |
|-----------|-------------|-------|
| CR Rule #1: independent Tx vs Rx allocation | §8.2.1.2 rule 1 | `txUlpReq`/`txUlpData` vs `rxUlpReq`/`rxNetReq` pools |
| CR Rule #2: independent initiator vs target pkts | §8.2.1.2 rule 2, §8.3 | `reqLane` vs `dataLane`; separate PDL windows |
| Proactive pull Rx at ULP inject | §8.2.2 Row B Col2; paper §4.5 | `inject` `.pull` → `txUlpReq` + `rxUlpReq` |
| Proactive push completion Rx at inject | §8.2.2 Row A | `inject` `.push` → `txUlpReq` + `rxUlpReq` |
| Pull data uses pre-allocated initiator Rx | §8.4.3.2 | `rxUlpReq` held from inject through `complete` |
| Target net Rx on receive | §8.5.3.1 | `allocNetReq` at `transmitReq` on peer |
| Target ULP data Tx on pull response | §8.2.2 Row C Col3 | `allocUlpData` at `targetPull` |
| UR Rule: ordered HoL at target | §8.2.1.1 | `isHol` on `netReq` / `pushWait` |
| UR Rule: push ACK blocked on HoL txn | §8.2.1.1 | `deliverPush` + `ordered` + `netReq` |
| Separate req/data PSN spaces | §A.1 (paper) | `reqWindow` / `dataWindow`; `ackReq` / `ackData` |
| PullReqAckd / early request ACK | §8.4.3.1 | `ackReq` after `targetPull` |

## Intentional abstractions / not modeled

* Four physical pools (Tx/Rx packet + buffer) collapsed to **packet slots**
  per region; byte-granular buffer credits (`ceiling(L/N)`) omitted.
* PDL congestion control (`ncwnd`/`fcwnd`), RNR/CIE/Resync, green/red HoL zones
  (§8.2.4), Xon/Xoff backpressure, multi-connection scheduling.
* Target ULP ack before pull data (`PullReqUlpAckd`); target always ready.
* ACKs modeled as side-band `ackReq`/`ackData` steps (like UB `linkAck`).

## Key modeling assumptions (documented on purpose)

* Buffer pools are counted in **packet slots** (not bytes); one slot per
  transaction phase, matching the per-packet credit counters in §8.2.3.
* PDL reliability is abstracted as finite **in-flight windows** with an `ack`
  progress step (like UB `linkAck`), on a non-blocking side-band path.
* RSN is a small `Nat` assigned at inject time; ordering is enforced by HoL
  rules and completion queues, not by an unbounded sequence space.
* Target push delivery (ULP ack before PDL ack) is a single `deliverPush`
  progress step — the dependency that creates UR-rule ordering exposure.
-/
import DLFTK.Falcon.Types
import DLFTK.Core
import DLFTK.Analysis

namespace DLFTK.Falcon

structure Params where
  /-- Per-region capacity when `design = crCompliant`. -/
  poolCap : Nat
  /-- Capacity of the ULP Req Rx region (proactive pull-response / push-completion slots). -/
  rxUlpReqCap : Nat
  /-- Shared-pool capacity for `sharedTxRx`. -/
  sharedCap : Nat
  /-- Request PDL window (pull requests). -/
  reqWindow : Nat
  /-- Data PDL window (push data + pull data). -/
  dataWindow : Nat
  /-- Max outstanding ULP transactions per peer. -/
  txnWindow : Nat
  /-- Ordered connection: target HoL + completion ordering. -/
  ordered : Bool
  /-- Resource / scheduler / window carving policy. -/
  design : ResourceDesign

/-- Per-region pool occupancy (CR-compliant carving). -/
structure DedicatedPools where
  txUlpReq  : Nat := 0
  txUlpData : Nat := 0
  rxUlpReq  : Nat := 0
  rxNetReq  : Nat := 0
deriving DecidableEq, Repr, BEq, Hashable

structure Side where
  /-- Next RSN to assign. -/
  nextRsn : Nat := 0
  /-- ULP transactions accepted but not yet scheduled. -/
  pending : List Txn := []
  /-- Initiator scheduler lane (`pullReq` + `pushData`). -/
  reqLane : List WirePkt := []
  /-- Target scheduler lane (`pullData`). -/
  dataLane : List WirePkt := []
  /-- Unified scheduler when `sharedScheduler`. -/
  unifiedLane : List WirePkt := []
  /-- Request-window in-flight. -/
  reqFlight : List WirePkt := []
  /-- Data-window in-flight. -/
  dataFlight : List WirePkt := []
  /-- Unified in-flight when `sharedReqData`. -/
  unifiedFlight : List WirePkt := []
  /-- Network requests waiting target processing. -/
  netReq : List WirePkt := []
  /-- Push data admitted at target, awaiting ULP delivery before ACK. -/
  pushWait : List WirePkt := []
  /-- Completions waiting in-order delivery to initiator ULP. -/
  completions : List WirePkt := []
  /-- Pull data delivered from network, not yet copied to completions (OOO). -/
  inFlightPullData : List WirePkt := []
  /-- Base RSN for ordered completion delivery. -/
  brsn : Nat := 0
  /-- Dedicated pool occupancy. -/
  pools : DedicatedPools := {}
  /-- Shared Tx/Rx occupancy when `sharedTxRx`. -/
  sharedPool : Nat := 0
deriving DecidableEq, Repr, BEq, Hashable

structure St where
  a : Side := {}
  b : Side := {}
deriving DecidableEq, Repr, BEq, Hashable

def St.side (s : St) : Peer → Side
  | .A => s.a
  | .B => s.b

def St.setSide (s : St) : Peer → Side → St
  | .A, sd => { s with a := sd }
  | .B, sd => { s with b := sd }

/-- Total outstanding transaction slots on a side. -/
def Side.outstanding (sd : Side) : Nat :=
  sd.pending.length + sd.reqLane.length + sd.dataLane.length + sd.unifiedLane.length
    + sd.reqFlight.length + sd.dataFlight.length + sd.unifiedFlight.length
    + sd.netReq.length + sd.pushWait.length + sd.completions.length
    + sd.inFlightPullData.length

def canInject (P : Params) (sd : Side) : Bool :=
  sd.outstanding < P.txnWindow

end DLFTK.Falcon
