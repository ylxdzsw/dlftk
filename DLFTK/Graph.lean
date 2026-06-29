/-
# DLFTK.Graph — Finite directed graphs for dependency analysis

Lightweight graph utilities used by the wait-for-graph (WFG) layer. We keep
everything executable so cycle checks discharge by `native_decide` on small
instances, without pulling in Mathlib.
-/
namespace DLFTK

/-- A finite directed graph over vertex labels `α`. -/
structure Digraph (α : Type) [BEq α] where
  vertices : List α
  /-- Directed wait edges `x → y` (“`x` waits for `y`”). -/
  edges : List (α × α)
deriving Repr

namespace Digraph

variable {α : Type} [BEq α]

/-- Out-neighbours of `v` in `g`. -/
def succs (g : Digraph α) (v : α) : List α :=
  g.edges.filterMap (fun (x, y) => if x == v then some y else none)

/-- `src` can reach `dst` in at most `fuel` hops. -/
def reaches (g : Digraph α) (src dst : α) : Nat → Bool
  | 0 => src == dst
  | fuel + 1 =>
    src == dst || (g.succs src).any (g.reaches · dst fuel)

/-- `true` when `g` has any directed cycle. A cycle exists iff some vertex can
reach one of its successors back again (including self-loops). -/
def hasCycle (g : Digraph α) : Bool :=
  let fuel := g.vertices.length
  g.vertices.any (fun v => (g.succs v).any (g.reaches · v fuel))

/-- A 2-vertex wait cycle: mutual waiting `a ⇄ b`. -/
def mutualWait (waitsAB waitsBA : Bool) : Bool :=
  waitsAB && waitsBA

end Digraph
end DLFTK
