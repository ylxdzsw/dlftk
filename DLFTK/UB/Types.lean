/-
# DLFTK.UB.Types — Basic types for the UB protocol model

UB is an **L4 message protocol** (req/resp store semantics) over **L2 virtual
lanes**. The legacy two-host study uses topology `Topology.TwoNode`; see
`Compose.UbOnClos` for CLOS fabric wiring.

The vocabulary is chosen to expose the mechanisms that matter for deadlock:

* **Virtual lanes (VL)** — independent buffer/credit pools multiplexed on one link.
* **Message class** — `req` (store request) vs `resp` (completion/response).
  A non-posted store request, once *processed*, emits a response.
* **Sequence numbers** — for source-ordering and link-level retry.

Nodes are named `A` / `B`. A *packet* travels on a VL, carries a class and a
sequence number.
-/

namespace DLFTK.UB

/-- The two endpoints of the link. -/
inductive Node | A | B
deriving DecidableEq, Repr, BEq, Hashable

/-- `Node.peer` — the other endpoint. -/
def Node.peer : Node → Node
  | .A => .B
  | .B => .A

/-- Message class. A UB store is *non-posted*: `req` ⇒ (after processing) `resp`. -/
inductive Cls | req | resp
deriving DecidableEq, Repr, BEq, Hashable

/-- Virtual-lane identifier. Kept as a `Nat` so a model can use as many as it
needs; scenarios fix a concrete small count. -/
abbrev VL := Nat

/-- A packet on the wire / in a buffer.

Note on **source-ordering**: we deliberately do *not* carry an unbounded source
sequence integer. Ordering ("a source waits for earlier packets' ACKs before
sending the rest") is captured faithfully and *finitely* by two things in the
model: the bounded **send window** and the **FIFO order of the replay buffer**.
An ever-growing `seq` field would only make the state space infinite without
adding any ordering power the replay FIFO doesn't already give. -/
structure Pkt where
  cls : Cls
  vl  : VL
deriving DecidableEq, Repr, BEq, Hashable

/-- Which VL a class is mapped to, under a given *VL assignment policy*.
This is the knob that distinguishes the **shared** design (both classes → VL 0)
from the **separate** design (`req`→0, `resp`→1). -/
abbrev VLMap := Cls → VL

/-- Shared design: everything on VL 0. -/
def VLMap.shared : VLMap := fun _ => 0

/-- Separate design: requests on VL 0, responses on VL 1. -/
def VLMap.separate : VLMap
  | .req => 0
  | .resp => 1

end DLFTK.UB
