/-
# DLFTK.Analysis — Deadlock predicates and computable search

Operational definitions on top of `DLFTK.System`:

* `HasWork`   — the state is not fully idle (there is something left to do).
* `Deadlock`  — reachable, has work, but cannot make progress.

For finite instances `findDeadlock` searches the bounded reachable set and
returns a concrete witness state if one exists, so we can both **find** bugs
and (when the search saturates) **certify** their absence by `decide`.
-/
import DLFTK.Core

namespace DLFTK
namespace System

variable {σ : Type} [BEq σ] [Hashable σ]

/-- A *work* predicate marks states that are not legitimately idle.
`Deadlock` only fires on states that still have outstanding work. -/
def HasWorkP := σ → Bool

/-- A reachable state with work but no progress step is deadlocked.
Returns the first such witness in the reachable set, if any. -/
def findDeadlock (M : System σ) (work : σ → Bool) (fuel : Nat) : Option σ :=
  (M.reachable fuel).find? (fun s => work s && M.progress s == [])

/-- `true` when the reachable set contains no deadlock state.

⚠ Only meaningful together with `reachableSaturated fuel = true`: otherwise the
search may simply not have reached a deadlock yet. The scenario theorems pair
these two facts. -/
def deadlockFree (M : System σ) (work : σ → Bool) (fuel : Nat) : Bool :=
  (M.findDeadlock work fuel).isNone

/-- Number of reachable states explored (diagnostic). -/
def reachableCount (M : System σ) (fuel : Nat) : Nat :=
  (M.reachable fuel).length

end System
end DLFTK
