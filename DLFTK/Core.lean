/-
# DLFTK.Core — Generic transition-system core for deadlock study

A protocol model is a *labeled transition system* (LTS) whose steps are split
into two kinds:

* **progress** steps  — the system doing useful work on its own
  (link transfer, request processing, response consumption, retransmit, ...).
* **environment** steps — the outside world offering load
  (injecting new requests). These are *not* progress.

Deadlock is then defined operationally:

> a reachable state that still has outstanding work,
> but from which **no progress step** is possible.

This file is protocol-agnostic. Concrete protocols (UB, Falcon, ...) instantiate
`System` and reuse the search/analysis machinery here.
-/
import Std.Data.HashSet

namespace DLFTK

/-- A finite-branching transition system over a state type `σ`.

We keep everything **executable** (`successors` returns a `List`) so that for
small, finite instances we can search the reachable set and decide deadlock
questions by computation (`decide`/`native_decide`) instead of by hand. -/
structure System (σ : Type) where
  /-- Initial states. -/
  init : List σ
  /-- Progress successors: useful work the system can do from `s`. -/
  progress : σ → List σ
  /-- Environment successors: load offered from outside (e.g. injection). -/
  env : σ → List σ

namespace System

variable {σ : Type}

/-- All successors (progress + environment). -/
def step (M : System σ) (s : σ) : List σ :=
  M.progress s ++ M.env s

/-- A state can make progress iff it has at least one progress successor. -/
def canProgress (M : System σ) (s : σ) : Prop :=
  M.progress s ≠ []

instance (M : System σ) (s : σ) : Decidable (M.canProgress s) := by
  unfold canProgress; infer_instance

/-! ## Reachability via BFS over a `HashSet`

We compute the reachable set with a worklist BFS, using a `Std.HashSet` for
O(1) membership. A `fuel` parameter bounds the number of iterations so the
function is total; for finite-state models a large-enough fuel **saturates**
(the worklist empties) and the result is the *exact* reachable set. -/

variable [BEq σ] [Hashable σ]

/-- BFS from `M.init`. Returns `(states, saturated)` where `saturated = true`
means the worklist emptied within `fuel` steps, so `states` is the complete
reachable set (not a fuel-truncated under-approximation). -/
def explore (M : System σ) (fuel : Nat) : Array σ × Bool :=
  let rec go (fuel : Nat) (seen : Std.HashSet σ) (acc : Array σ)
      (work : List σ) : Array σ × Bool :=
    match fuel, work with
    | _,      []          => (acc, true)          -- worklist empty ⇒ saturated
    | 0,      _ :: _       => (acc, false)         -- ran out of fuel ⇒ partial
    | fuel'+1, s :: rest   =>
        let succ := M.step s
        let (seen, acc, work) := succ.foldl
          (fun (st : Std.HashSet σ × Array σ × List σ) t =>
            let (seen, acc, work) := st
            if seen.contains t then (seen, acc, work)
            else (seen.insert t, acc.push t, t :: work))
          (seen, acc, rest)
        go fuel' seen acc work
  let init := M.init.eraseDups
  let seen0 := init.foldl (fun (h : Std.HashSet σ) s => h.insert s) ∅
  go fuel seen0 init.toArray init

/-- Reachable states (as a `List`). The companion `reachableSaturated` says
whether this is the complete set. -/
def reachable (M : System σ) (fuel : Nat) : List σ :=
  (M.explore fuel).1.toList

/-- `true` iff the BFS worklist emptied within `fuel` — i.e. `reachable fuel`
is the *exact* reachable set. -/
def reachableSaturated (M : System σ) (fuel : Nat) : Bool :=
  (M.explore fuel).2

end System
end DLFTK
