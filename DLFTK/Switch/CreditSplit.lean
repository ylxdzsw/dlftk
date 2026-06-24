/-
# DLFTK.Switch.CreditSplit

More faithful switched-credit model.

The upstream credit-accounted resource is an input receive buffer. A packet is
routed into a VOQ as a separate progress step. Upstream credit returns when that
input buffer slot is freed, not when the packet leaves the whole switch.

The output side still uses link-local downstream credits.
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.Switch.Types

namespace DLFTK.Switch.CreditSplit

open DLFTK.Switch

structure Params where
  nIn : Nat
  nOut : Nat
  nLane : Nat
  /-- Upstream-facing ingress receive capacity per `(input, lane)`. -/
  ingressCap : Nat
  /-- VOQ capacity per `(input, output, lane)`. -/
  voqCap : Nat
  /-- Downstream receive-buffer credits per `(output, lane)`. -/
  downCap : Nat
deriving DecidableEq, Repr, BEq, Hashable

structure St where
  ingress : List RoutedPkt := []
  voq : List RoutedPkt := []
  upCredit : List Nat := []
  downCredit : List Nat := []
deriving DecidableEq, Repr, BEq, Hashable

def upIdx (P : Params) (input : InPort) (lane : Lane) : Nat := idx2 P.nLane input lane
def downIdx (P : Params) (out : OutPort) (lane : Lane) : Nat := idx2 P.nLane out lane

namespace Step

variable (P : Params)

/-- Environment arrival consumes only the upstream-facing ingress resource. -/
def inject (input : InPort) (out : OutPort) (lane : Lane) (s : St) : List St :=
  let ui := upIdx P input lane
  if natAt s.upCredit ui > 0 && countByInputLane input lane s.ingress < P.ingressCap then
    let p : RoutedPkt := { input := input, out := out, lane := lane }
    [{ s with ingress := s.ingress ++ [p], upCredit := decNat s.upCredit ui }]
  else []

/-- Move from ingress to the selected VOQ and return upstream credit. -/
def routeToVOQ (input : InPort) (lane : Lane) (s : St) : List St :=
  match headByInputLane input lane s.ingress with
  | none => []
  | some (pkt, rest) =>
      if countVOQ pkt.input pkt.out pkt.lane s.voq < P.voqCap then
        let ui := upIdx P input lane
        [{ s with
          ingress := rest,
          voq := s.voq ++ [pkt],
          upCredit := incNat s.upCredit ui }]
      else []

/-- Send one VOQ head downstream, consuming only downstream link credit. -/
def transmit (input : InPort) (out : OutPort) (lane : Lane) (s : St) : List St :=
  let di := downIdx P out lane
  match headVOQ input out lane s.voq with
  | none => []
  | some (_, rest) =>
      if natAt s.downCredit di > 0 then
        [{ s with voq := rest, downCredit := decNat s.downCredit di }]
      else []

def downstreamCreditReturn (out : OutPort) (lane : Lane) (s : St) : List St :=
  let di := downIdx P out lane
  if natAt s.downCredit di < P.downCap then
    [{ s with downCredit := incNat s.downCredit di }]
  else []

def progress (s : St) : List St :=
  let inputs := List.range P.nIn
  let outputs := List.range P.nOut
  let lanes := List.range P.nLane
  let route := inputs.flatMap (fun i => lanes.flatMap (fun l => routeToVOQ P i l s))
  let send := inputs.flatMap (fun i =>
    outputs.flatMap (fun o =>
      lanes.flatMap (fun l => transmit P i o l s)))
  route ++ send

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
  { upCredit := initNat2 P.nIn P.nLane P.ingressCap,
    downCredit := initNat2 P.nOut P.nLane P.downCap }

def system (P : Params) : DLFTK.System St where
  init := [initSt P]
  progress := Step.progress P
  env := Step.env P

def hasWork (s : St) : Bool := hasRoutedWork s.ingress || hasRoutedWork s.voq

end DLFTK.Switch.CreditSplit
