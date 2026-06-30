/-
# DLFTK.Layer.L2.Link — Credit-based reliable link hop

Models one endpoint of an L2 link segment:

* per-dimension ingress / egress queues and credits,
* bounded send window + replay buffer,
* side-band ACK (`linkAck`),
* **drop** (env) and **retransmit** (progress) on replayed blocks.

ACK/credit-return remain side-band (non-blocking), matching current UB/Falcon
assumptions. In-band control is a future overlay on the same `Block` type.
-/
import DLFTK.Layer.L2.Types
import DLFTK.Switch.Types

namespace DLFTK.Layer.L2

open DLFTK.Layer
open DLFTK.Switch

structure LinkSide (α : Type) where
  ingress : List (Block α) := []
  egress  : List (Block α) := []
  /-- Free buffer slots believed available at the peer ingress, per dimension. -/
  credit  : List Nat := []
  /-- Sent-but-unACKed blocks (replay / retry buffer). -/
  replay  : List (Block α) := []
deriving DecidableEq, Repr, BEq, Hashable

def initCredit (P : LinkParams) : List Nat :=
  List.replicate P.nDim P.cap

def creditAt (xs : List Nat) (d : Dim) : Nat := (xs[d]?).getD 0

def setCredit (xs : List Nat) (d : Dim) (n : Nat) : List Nat :=
  let xs := xs ++ List.replicate (d + 1 - xs.length) 0
  xs.set d n

namespace LinkStep

variable {α : Type} [DecidableEq α] [BEq α]
variable (P : LinkParams)

/-- Move dimension-`d` egress head to peer ingress. Consumes credit and records replay. -/
def transmit (d : Dim) (self peer : LinkSide α) : List (LinkSide α × LinkSide α) :=
  match dimHead d self.egress with
  | none => []
  | some (blk, rest) =>
    if creditAt self.credit d > 0 && self.replay.length < P.window
        && dimLen d peer.ingress < P.cap then
      let self' := { self with
        egress := rest,
        credit := setCredit self.credit d (creditAt self.credit d - 1),
        replay := self.replay ++ [blk] }
      let peer' := { peer with ingress := peer.ingress ++ [blk] }
      [(self', peer')]
    else []

/-- Peer freed an ingress slot on dimension `d`; return one credit. -/
def returnCredit (d : Dim) (peer : LinkSide α) : LinkSide α :=
  { peer with credit := setCredit peer.credit d (creditAt peer.credit d + 1) }

/-- Oldest in-flight block is ACKed; frees a send-window slot. -/
def linkAck (self : LinkSide α) : List (LinkSide α) :=
  match self.replay with
  | [] => []
  | _ :: rest => [{ self with replay := rest }]

/-- Retransmit the oldest replayed block (requires credit + peer ingress room). -/
def retransmit (d : Dim) (self peer : LinkSide α) : List (LinkSide α × LinkSide α) :=
  match self.replay with
  | [] => []
  | blk :: _ =>
    if blk.dim == d && creditAt self.credit d > 0 && dimLen d peer.ingress < P.cap then
      let self' := { self with
        credit := setCredit self.credit d (creditAt self.credit d - 1) }
      let peer' := { peer with ingress := peer.ingress ++ [blk] }
      [(self', peer')]
    else []

/-- Environment: drop the oldest in-flight block (L2 loss). Does not free credits;
the peer may still hold the original copy until consumed. -/
def dropInflight (self : LinkSide α) : List (LinkSide α) :=
  match self.replay with
  | [] => []
  | _ :: rest => [{ self with replay := rest }]

end LinkStep

end DLFTK.Layer.L2
