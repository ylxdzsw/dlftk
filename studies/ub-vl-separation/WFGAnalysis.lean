/-
# Study: UB virtual-lane separation — wait-for graph analysis

Complements `TwoHostStore.lean` (full state enumeration) with a **mathematical**
layer:

1. **Lane partition** — separate VL decouples req/resp buffer pools.
2. **WFG extraction** — shared-VL deadlock states exhibit mutual peer waiting
   and a WFG cycle.
3. **Structured invariants** — scan the reachable set for dependency patterns
   rather than only the top-level `deadlockFree` bit.

Enumeration in `TwoHostStore.lean` remains the ground truth over the exact
reachable set. This module reads off the *dependency structure* behind the
results.
-/
import DLFTK.UB.Dependency
import TwoHostStore

namespace StudyUbVlSeparation

open DLFTK DLFTK.UB

/-! ## Lane partition -/

example : lanesPartitioned sharedP = false := by native_decide
example : lanesPartitioned separateP = true := by native_decide

/-! ## Shared-VL deadlock: mutual wait + WFG cycle -/

/-- Canonical symmetric req-req stall (matches the `findDeadlock` witness shape). -/
def stallPkt : Pkt := { cls := Cls.req, vl := 0 }
def stallSide : Side := { ingress := [stallPkt], egress := [stallPkt], credit := [0], replay := [] }
def stallState : St := { a := stallSide, b := stallSide }

#eval waitsForPeer sharedP stallState .A
#eval waitsForPeer sharedP stallState .B
#eval mutualPeerWait sharedP stallState
#eval (wfg sharedP stallState).hasCycle

example : mutualPeerWait sharedP stallState = true := by native_decide
example : (wfg sharedP stallState).hasCycle = true := by native_decide
example : (twoNodeWfg true true).hasCycle = true := by native_decide

/-- Some reachable shared-VL deadlock exhibits mutual peer waiting. -/
def reachableDeadlockMutualWait (sys : System St) (P : Params) (fuel : Nat) : Bool :=
  (sys.reachable fuel).any (fun s =>
    hasWork s && sys.progress s == [] && mutualPeerWait P s)

#eval reachableDeadlockMutualWait sharedSys sharedP fuel

example : reachableDeadlockMutualWait sharedSys sharedP fuel = true := by native_decide

/-! ## Separate VL: no deadlock state carries a WFG cycle -/

/-- `true` when some reachable state is deadlocked *and* its WFG has a cycle. -/
def reachableDeadlockWFG (sys : System St) (P : Params) (fuel : Nat) : Bool :=
  (sys.reachable fuel).any (fun s =>
    hasWork s
      && sys.progress s == []
      && (wfg P s).hasCycle)

#eval reachableDeadlockWFG separateSys separateP fuel
#eval reachableDeadlockWFG sharedSys sharedP fuel

example : reachableDeadlockWFG separateSys separateP fuel = false := by native_decide
example : reachableDeadlockWFG sharedSys sharedP fuel = true := by native_decide

/-! ## Lane-partition invariant on the reachable set -/

/-- All reachable separate-VL states satisfy: process blocked on req ↔ resp egress full. -/
def reachablePartitionInv (sys : System St) (P : Params) (fuel : Nat) : Bool :=
  (sys.reachable fuel).all (fun s =>
    [Node.A, Node.B].all (fun n => processBlocked_iff_respFull P n s))

#eval reachablePartitionInv separateSys separateP fuel

example : reachablePartitionInv separateSys separateP fuel = true := by native_decide

end StudyUbVlSeparation
