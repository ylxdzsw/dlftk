/-
# DLFTK.Falcon.Types — Falcon transaction and packet vocabulary

We model the **transaction sublayer** mechanisms from the OCP Falcon Transport
Protocol that matter for protocol deadlock:

* **Push** (store / write) and **Pull** (load / read) transactions.
* **Request Sequence Numbers (RSN)** — transaction ordering on ordered connections.
* **Packet classes** — pull request, push data, and pull data (the packet-delivery
  sublayer uses separate request vs data sliding windows / PSN spaces; we name the
  packet kinds after their roles).
* **Resource carving** — dedicated pools vs shared pools that violate Falcon CR rules.

Nodes are `A` / `B` on a single bidirectional connection (each end is simultaneously
initiator and target, as in the spec).
-/

namespace DLFTK.Falcon

/-- Connection endpoint. -/
inductive Peer | A | B
deriving DecidableEq, Repr, BEq, Hashable

def Peer.peer : Peer → Peer
  | .A => .B
  | .B => .A

/-- ULP transaction kind: push (store/write) or pull (load/read). -/
inductive TxnKind | push | pull
deriving DecidableEq, Repr, BEq, Hashable

/-- On-wire packet kind at the transaction / PDL boundary. -/
inductive PktKind
  | pullReq
  | pushData
  | pullData
deriving DecidableEq, Repr, BEq, Hashable

/-- A ULP transaction waiting to start on the initiator. -/
structure Txn where
  kind : TxnKind
  rsn  : Nat
deriving DecidableEq, Repr, BEq, Hashable

/-- A schedulable or in-flight packet. RSN ties packets to their transaction. -/
structure WirePkt where
  kind : PktKind
  rsn  : Nat
deriving DecidableEq, Repr, BEq, Hashable

/-- Falcon constrained-resource carving policy.

`crCompliant` follows CR Rules #1–#2 (OCP §8.2.1.2) and proactive ULP resource
assignment (§8.2.2 table Row B): separate Tx/Rx-style pools, separate request
vs data PDL windows, separate initiator (`pullReq`/`pushData`) vs target
(`pullData`) scheduler lanes, and **pull inject allocates ULP Req Tx + ULP Req
Rx** so the initiator can land the incoming `pullData` before transmitting the
`pullReq` (SIGCOMM §4.5 resource lifecycle).

The `shared*` variants each remove one independence axis to expose the
corresponding deadlock class.

`noProactivePullRx` violates §8.2.2 Row B Col2: pull inject allocates only
`txUlpReq`; `rxUlpReq` is deferred until `pullData` arrives at the initiator. -/
inductive ResourceDesign
  | crCompliant
  | sharedTxRx
  | sharedReqData
  | sharedScheduler
  | noProactivePullRx
deriving DecidableEq, Repr, BEq, Hashable

/-- Initiator scheduler lane: pull requests and push data (spec §8.3). -/
def initiatorPkt? (k : PktKind) : Bool :=
  k == .pullReq || k == .pushData

/-- Target scheduler lane: pull data responses. -/
def targetPkt? (k : PktKind) : Bool :=
  k == .pullData

end DLFTK.Falcon
