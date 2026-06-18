/-
# DLFTK.UB.Model — A two-node UB link with the deadlock-relevant mechanisms

We model **one link between two nodes `A` and `B`**, carrying non-posted store
traffic, with the four mechanisms requested:

1. **Credit-based flow control + egress queue.**
   To send a packet on VL `v`, a node must hold a *credit* for `v`
   (credit = a free buffer slot at the peer's ingress for that VL). Packets wait
   in a per-node **egress** queue until they have both a credit and (see §3) a
   send window slot. Receiving consumes ingress buffers and *returns* credit.

2. **Virtual lanes (VL).**
   Ingress/egress are partitioned per VL: a packet on VL `v` is only ever
   blocked by other packets on VL `v` (per-lane FIFO), never by another lane.
   The `VLMap` policy decides which class uses which lane — this is the single
   knob separating the *shared* design from the *separate* design.

3. **Source-ordering + send window.**
   A source assigns increasing sequence numbers and keeps unacknowledged packets
   in a **replay** buffer. It may have at most `window` packets in flight; it
   must wait for ACKs of earlier packets before sending more. (`window = 1` is
   stop-and-wait.)

4. **Link-level retry.**
   The replay buffer holds sent-but-unACKed packets so they can be
   **retransmitted**. ACKs remove packets from the replay buffer.

## Key modeling assumption (documented on purpose)

Credit-return and ACKs travel on a **non-blocking link-layer path** (a dedicated
side-band, as in real fabrics), so they are modeled as direct, always-enabled
effects of the consume step rather than as in-band packets competing for VLs.
Consequence: under this assumption the *only* way to deadlock is the
**message-dependent req→resp cycle**, which is exactly the hypothesis under
study. Making ACKs in-band (to expose ack/credit-return deadlock) is a planned
extension and is isolated to the consume step.
-/
import DLFTK.UB.Types
import DLFTK.Core
import DLFTK.Analysis

namespace DLFTK.UB

/-- Static parameters of a model instance. -/
structure Params where
  /-- Number of virtual lanes. -/
  nVL : Nat
  /-- Ingress buffer capacity, per VL (slots). -/
  cap : Nat
  /-- Send window: max in-flight (unACKed) packets per node. -/
  window : Nat
  /-- Class→VL assignment policy. -/
  vlmap : VLMap

/-- Per-node state. Per-VL structures are stored as flat `List`s; the VL lives
inside each `Pkt`, and per-lane views are recovered by filtering on `vl`. This
keeps the whole state in plain `List`/`Nat` fields so `BEq`/`DecidableEq`/
`Hashable` derive automatically, which is what powers the reachability search. -/
structure Side where
  /-- Received packets awaiting local consumption/processing (per-VL FIFO). -/
  ingress : List Pkt := []
  /-- Locally produced packets awaiting transmission (per-VL FIFO). -/
  egress  : List Pkt := []
  /-- `credit[v]` = free buffer slots believed available at peer ingress on VL `v`. -/
  credit  : List Nat := []
  /-- Sent-but-unACKed packets (retry/replay buffer). Its length is the in-flight count. -/
  replay  : List Pkt := []
deriving DecidableEq, Repr, BEq, Hashable

/-- Full system state: both sides. -/
structure St where
  a : Side := {}
  b : Side := {}
deriving DecidableEq, Repr, BEq, Hashable

/-! ## Small list helpers (per-VL views and indexed credit) -/

/-- Packets of a given VL, in FIFO order. -/
def laneOf (vl : VL) (q : List Pkt) : List Pkt := q.filter (fun p => p.vl == vl)

/-- Number of packets of VL `vl` currently in `q`. -/
def laneLen (vl : VL) (q : List Pkt) : Nat := (laneOf vl q).length

/-- Read `credit[vl]`, defaulting to `0` past the end. -/
def creditAt (cs : List Nat) (vl : VL) : Nat := (cs[vl]?).getD 0

/-- Write `credit[vl] := n`, padding with zeros if needed. -/
def setCredit (cs : List Nat) (vl : VL) (n : Nat) : List Nat :=
  let cs := cs ++ List.replicate (vl + 1 - cs.length) 0
  cs.set vl n

/-- Initial credits: every lane starts with `cap` free slots at the peer. -/
def initCredit (P : Params) : List Nat := List.replicate P.nVL P.cap

end DLFTK.UB
