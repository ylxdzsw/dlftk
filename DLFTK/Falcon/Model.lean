/-
# DLFTK.Falcon.Model — Two-peer Falcon connection with resource pools

We model **one bidirectional Falcon connection** between peers `A` and `B`, with
the deadlock-relevant transaction-layer structure from Falcon §8.2–8.4:

1. **Push and pull transactions** with RSN assignment and (optional) ordered
   delivery at the target and ordered completions at the initiator.
2. **Resource pools** carved into ULP-request, ULP-data, and network-request
   regions — or collapsed to a single shared pool (`sharedTxRx`).
3. **Separate request vs data PDL windows** — or merged (`sharedReqData`).
4. **Separate initiator vs target scheduler queues** — or merged
   (`sharedScheduler`).

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

def canInject (P : Params) (sd : Side) : Bool :=
  sd.outstanding < P.txnWindow

end DLFTK.Falcon
