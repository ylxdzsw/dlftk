/-
# DLFTK.Switch.CreditConservative

Conservative switched-credit model.

The packet chooses its output at arrival and is placed directly in an ingress
VOQ. That VOQ is also the upstream credit-accounted resource, so upstream credit
is returned only when the packet leaves the switch on its output link.

This model is deliberately stronger than common hardware: it collapses ingress
buffering, VOQ occupancy, and upstream credit into one resource. That simplifies
dependency/proof structure and is useful as a conservative deadlock study.
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.Switch.Types

namespace DLFTK.Switch.CreditConservative

open DLFTK.Switch

structure Params where
  nIn : Nat
  nOut : Nat
  nLane : Nat
  /-- Capacity of the upstream-credit-accounted VOQ pool per `(input, lane)`. -/
  voqCap : Nat
  /-- Downstream receive-buffer credits per `(output, lane)`. -/
  downCap : Nat
deriving DecidableEq, Repr, BEq, Hashable

structure St where
  voq : List RoutedPkt := []
  /-- Free upstream credits, indexed by `(input, lane)`. -/
  upCredit : List Nat := []
  /-- Free downstream credits, indexed by `(output, lane)`. -/
  downCredit : List Nat := []
deriving DecidableEq, Repr, BEq, Hashable

def upIdx (P : Params) (input : InPort) (lane : Lane) : Nat := idx2 P.nLane input lane
def downIdx (P : Params) (out : OutPort) (lane : Lane) : Nat := idx2 P.nLane out lane

namespace Step

variable (P : Params)

/-- Environment arrival from an upstream link. Routing happens immediately. -/
def inject (input : InPort) (out : OutPort) (lane : Lane) (s : St) : List St :=
  let ui := upIdx P input lane
  if natAt s.upCredit ui > 0 && countByInputLane input lane s.voq < P.voqCap then
    let p : RoutedPkt := { input := input, out := out, lane := lane }
    [{ s with voq := s.voq ++ [p], upCredit := decNat s.upCredit ui }]
  else []

/-- Send one VOQ head downstream. This is also when upstream credit returns. -/
def transmit (input : InPort) (out : OutPort) (lane : Lane) (s : St) : List St :=
  let di := downIdx P out lane
  match headVOQ input out lane s.voq with
  | none => []
  | some (_, rest) =>
      if natAt s.downCredit di > 0 then
        let ui := upIdx P input lane
        [{ s with
          voq := rest,
          upCredit := incNat s.upCredit ui,
          downCredit := decNat s.downCredit di }]
      else []

/-- External next-hop drain returning a downstream credit to this switch. -/
def downstreamCreditReturn (out : OutPort) (lane : Lane) (s : St) : List St :=
  let di := downIdx P out lane
  if natAt s.downCredit di < P.downCap then
    [{ s with downCredit := incNat s.downCredit di }]
  else []

def progress (s : St) : List St :=
  let inputs := List.range P.nIn
  let outputs := List.range P.nOut
  let lanes := List.range P.nLane
  inputs.flatMap (fun i =>
    outputs.flatMap (fun o =>
      lanes.flatMap (fun l => transmit P i o l s)))

def env (s : St) : List St :=
  let inputs := List.range P.nIn
  let outputs := List.range P.nOut
  let lanes := List.range P.nLane
  let arrivals := inputs.flatMap (fun i =>
    outputs.flatMap (fun o =>
      lanes.flatMap (fun l => inject P i o l s)))
  let returns := outputs.flatMap (fun o =>
    lanes.flatMap (fun l => downstreamCreditReturn P o l s))
  arrivals ++ returns

end Step

def initSt (P : Params) : St :=
  { upCredit := initNat2 P.nIn P.nLane P.voqCap,
    downCredit := initNat2 P.nOut P.nLane P.downCap }

def system (P : Params) : DLFTK.System St where
  init := [initSt P]
  progress := Step.progress P
  env := Step.env P

def hasWork (s : St) : Bool := hasRoutedWork s.voq

end DLFTK.Switch.CreditConservative
