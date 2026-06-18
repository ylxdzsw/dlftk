/-
# DLFTK.UB.Scenario.TwoHostStore — the first case study

Two hosts on a direct UB link, both streaming non-posted **store** requests at
each other. We compare two designs:

* **shared**   — requests and responses share one VL (`VLMap.shared`).
* **separate** — requests on VL 0, responses on VL 1 (`VLMap.separate`).

The hypothesis under study:

> With a shared VL the system can reach a **message-dependent deadlock**;
> with separate VLs (dedicated flow-control buffer + queue per class) it is
> **deadlock-free**.

We discharge both claims **by computation** over the bounded reachable set:

* `shared_has_deadlock`   : the shared design reaches a deadlock state.
* `separate_deadlock_free`: the separate design has no deadlock state,
                            and the search has **saturated** (so this is the
                            true reachable set, not an artifact of low fuel).

Run `#eval` lines to inspect; the `example`s are machine-checked by `decide`.
-/
import DLFTK.UB.Transitions
import DLFTK.Analysis

namespace DLFTK.UB.Scenario

open DLFTK DLFTK.UB

/-- Shared-VL design: 1 lane, capacity 1, window 2. -/
def sharedP : Params := { nVL := 1, cap := 1, window := 2, vlmap := VLMap.shared }

/-- Separate-VL design: 2 lanes, capacity 1, window 2. -/
def separateP : Params := { nVL := 2, cap := 1, window := 2, vlmap := VLMap.separate }

def sharedSys   : System St := system sharedP
def separateSys : System St := system separateP

/-- Search depth (BFS state-pops). Small caps ⇒ finite reachable set; this is
set comfortably above saturation for both designs. -/
def fuel : Nat := 100000

/-! ## Diagnostics (evaluate these to look inside) -/

-- How many states each design explores:
#eval sharedSys.reachableCount fuel
#eval separateSys.reachableCount fuel

-- Has the search saturated (true reachable set reached)?
#eval sharedSys.reachableSaturated fuel
#eval separateSys.reachableSaturated fuel

-- The deadlock witness for the shared design (Some state), and `none` for separate:
#eval sharedSys.findDeadlock hasWork fuel
#eval separateSys.findDeadlock hasWork fuel

/-! ## Machine-checked claims -/

/-- **Shared VL reaches a deadlock.** -/
example : (sharedSys.findDeadlock hasWork fuel).isSome = true := by native_decide

/-- **Separate VL is deadlock-free** over the (saturated) reachable set. -/
example : separateSys.deadlockFree hasWork fuel = true := by native_decide

/-- The separate-design search has actually saturated, so the freedom result is
about the *true* reachable set, not an artifact of insufficient fuel. -/
example : separateSys.reachableSaturated fuel = true := by native_decide

/-- The shared-design search has also saturated: its deadlock is real, not an
artifact, and freedom genuinely fails on the complete reachable set. -/
example : sharedSys.reachableSaturated fuel = true := by native_decide

end DLFTK.UB.Scenario
