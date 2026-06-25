/-
# Study: UB virtual-lane separation (shared vs separate VL)

Two hosts on a direct UB link, both streaming non-posted **store** requests at
each other. We compare two designs:

* **shared**   — requests and responses share one VL (`VLMap.shared`).
* **separate** — requests on VL 0, responses on VL 1 (`VLMap.separate`).

The hypothesis under study:

> With a shared VL the system can reach a **message-dependent deadlock**;
> with separate VLs (dedicated flow-control buffer + queue per class) it is
> **deadlock-free**.

We discharge both claims **by computation** over the bounded reachable set.

Run `#eval` lines to inspect; the `example`s are machine-checked by `decide`.
-/
import DLFTK.UB.Transitions
import DLFTK.Analysis

namespace StudyUbVlSeparation

open DLFTK DLFTK.UB

/-- Shared-VL design: 1 lane, capacity 1, window 2. -/
def sharedP : Params := { nVL := 1, cap := 1, window := 2, vlmap := VLMap.shared }

/-- Separate-VL design: 2 lanes, capacity 1, window 2. -/
def separateP : Params := { nVL := 2, cap := 1, window := 2, vlmap := VLMap.separate }

def sharedSys   : System St := system sharedP
def separateSys : System St := system separateP

def fuel : Nat := 100000

/-! ## Diagnostics -/

#eval sharedSys.reachableCount fuel
#eval separateSys.reachableCount fuel

#eval sharedSys.reachableSaturated fuel
#eval separateSys.reachableSaturated fuel

#eval sharedSys.findDeadlock hasWork fuel
#eval separateSys.findDeadlock hasWork fuel

/-! ## Machine-checked claims -/

example : (sharedSys.findDeadlock hasWork fuel).isSome = true := by native_decide
example : separateSys.deadlockFree hasWork fuel = true := by native_decide
example : separateSys.reachableSaturated fuel = true := by native_decide
example : sharedSys.reachableSaturated fuel = true := by native_decide

end StudyUbVlSeparation
