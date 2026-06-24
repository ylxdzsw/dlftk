/-
# DLFTK.Switch.Types — Common switch-model vocabulary

These definitions are intentionally small and protocol-neutral. The concrete
models in this directory instantiate the same high-level switch pipeline with
different backpressure mechanisms:

* conservative credit: the ingress VOQ is the credited resource until egress
* split credit: upstream ingress credit is freed when the packet leaves ingress
* PFC: threshold pause/resume instead of exact credits
-/

namespace DLFTK.Switch

abbrev InPort := Nat
abbrev OutPort := Nat
abbrev Lane := Nat
abbrev Priority := Nat

/-- A packet after routing has chosen an output and flow-control class. -/
structure Pkt where
  out : OutPort
  lane : Lane
deriving DecidableEq, Repr, BEq, Hashable

/-- A packet stored inside the switch, retaining its input port for VOQ accounting. -/
structure RoutedPkt where
  input : InPort
  out : OutPort
  lane : Lane
deriving DecidableEq, Repr, BEq, Hashable

/-- Flatten a two-dimensional `(major, minor)` index into a list position. -/
def idx2 (nMinor major minor : Nat) : Nat := major * nMinor + minor

/-- Flatten a three-dimensional `(a, b, c)` index into a list position. -/
def idx3 (nB nC a b c : Nat) : Nat := (a * nB + b) * nC + c

def natAt (xs : List Nat) (i : Nat) : Nat := (xs[i]?).getD 0

def setNat (xs : List Nat) (i n : Nat) : List Nat :=
  let xs := xs ++ List.replicate (i + 1 - xs.length) 0
  xs.set i n

def incNat (xs : List Nat) (i : Nat) : List Nat := setNat xs i (natAt xs i + 1)

def decNat (xs : List Nat) (i : Nat) : List Nat := setNat xs i (natAt xs i - 1)

def boolAt (xs : List Bool) (i : Nat) : Bool := (xs[i]?).getD false

def setBool (xs : List Bool) (i : Nat) (b : Bool) : List Bool :=
  let xs := xs ++ List.replicate (i + 1 - xs.length) false
  xs.set i b

def initNat2 (nMajor nMinor value : Nat) : List Nat :=
  List.replicate (nMajor * nMinor) value

def initBool2 (nMajor nMinor : Nat) : List Bool :=
  List.replicate (nMajor * nMinor) false

/-- Remove the first element satisfying `p`, preserving the order of the rest. -/
def removeFirst (p : α → Bool) : List α → Option (α × List α)
  | [] => none
  | x :: xs =>
      if p x then some (x, xs)
      else (removeFirst p xs).map (fun (y, rest) => (y, x :: rest))

def countRouted (p : RoutedPkt → Bool) (q : List RoutedPkt) : Nat :=
  (q.filter p).length

def countByInputLane (input : InPort) (lane : Lane) (q : List RoutedPkt) : Nat :=
  countRouted (fun p => p.input == input && p.lane == lane) q

def countVOQ (input : InPort) (out : OutPort) (lane : Lane) (q : List RoutedPkt) : Nat :=
  countRouted (fun p => p.input == input && p.out == out && p.lane == lane) q

def countOutLane (out : OutPort) (lane : Lane) (q : List RoutedPkt) : Nat :=
  countRouted (fun p => p.out == out && p.lane == lane) q

def headByInputLane (input : InPort) (lane : Lane) (q : List RoutedPkt) : Option (RoutedPkt × List RoutedPkt) :=
  removeFirst (fun p => p.input == input && p.lane == lane) q

def headVOQ (input : InPort) (out : OutPort) (lane : Lane) (q : List RoutedPkt) : Option (RoutedPkt × List RoutedPkt) :=
  removeFirst (fun p => p.input == input && p.out == out && p.lane == lane) q

def hasRoutedWork (q : List RoutedPkt) : Bool := ¬ q.isEmpty

end DLFTK.Switch
