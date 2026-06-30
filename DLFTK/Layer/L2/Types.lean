/-
# DLFTK.Layer.L2.Types — Link-layer data blocks

An **L2 block** is the unit of transmission on one hop. Payload is opaque at
this layer; L4 protocols tag blocks with their own fields (`Protocol.UB.Pkt`,
Falcon `WirePkt`, …).

Reliability (window, replay, ACK, drop, retransmit) operates on L2 blocks.
-/
import DLFTK.Layer.Dim
import DLFTK.Switch.Types

namespace DLFTK.Layer.L2

open DLFTK.Layer
open DLFTK.Switch

/-- A data block on the wire / in a link buffer, tagged with its L2 dimension. -/
structure Block (α : Type) where
  dim : Dim
  payload : α
deriving DecidableEq, Repr, BEq, Hashable

/-- Per-dimension link parameters shared by UB, Ethernet hop models, etc. -/
structure LinkParams where
  nDim : Nat
  /-- Ingress / egress capacity per dimension (slots). -/
  cap : Nat
  /-- Max in-flight unACKed blocks per endpoint. -/
  window : Nat
deriving DecidableEq, Repr, BEq, Hashable

/-- FIFO head on dimension `d` in a block queue. -/
def dimHead (d : Dim) (q : List (Block α)) : Option (Block α × List (Block α)) :=
  removeFirst (fun b => b.dim == d) q

/-- Count blocks on dimension `d`. -/
def dimLen (d : Dim) (q : List (Block α)) : Nat :=
  (q.filter (fun b => b.dim == d)).length

/-- Blocks on dimension `d` in FIFO order. -/
def dimOf (d : Dim) (q : List (Block α)) : List (Block α) :=
  q.filter (fun b => b.dim == d)

end DLFTK.Layer.L2
