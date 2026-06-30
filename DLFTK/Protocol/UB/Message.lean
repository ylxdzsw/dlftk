/-
# DLFTK.Protocol.UB.Message — UB transaction layer (L4)

Non-posted store semantics on top of L2 blocks:

* `req` injected by the environment,
* `process` turns a received `req` into a `resp`,
* `consume` sinks a received `resp`.

`VLMap` is an L4 policy knob: which L2 dimension each class uses. Virtual
lanes themselves are L2 resources (see `Layer.L2`).
-/
import DLFTK.Layer.Dim
import DLFTK.Layer.L2.Types
import DLFTK.Switch.Types

namespace DLFTK.Protocol.UB

open DLFTK.Layer
open DLFTK.Layer.L2
open DLFTK.Switch

inductive Cls | req | resp
deriving DecidableEq, Repr, BEq, Hashable

/-- UB message carried inside an L2 block. -/
structure Msg where
  cls : Cls
deriving DecidableEq, Repr, BEq, Hashable

abbrev Pkt := Block Msg

abbrev VLMap := Cls → Dim

def VLMap.shared : VLMap := fun _ => 0

def VLMap.separate : VLMap
  | .req => 0
  | .resp => 1

structure MsgParams where
  vlmap : VLMap

namespace MsgStep

variable (M : MsgParams)

/-- Offer a new store request on the request dimension. -/
def inject (egress : List Pkt) (cap : Nat) : List (List Pkt) :=
  let d := M.vlmap .req
  if dimLen d egress < cap then
    let pkt : Pkt := { dim := d, payload := { cls := .req } }
    [egress ++ [pkt]]
  else []

/-- Process a `req` at dimension `d` ingress head; produce `resp` on its dimension. -/
def process (d : Dim) (ingress egress : List Pkt) (cap : Nat)
    : Option (List Pkt × List Pkt) :=
  match dimHead d ingress with
  | none => none
  | some (blk, rest) =>
    if blk.payload.cls == .req then
      let rd := M.vlmap .resp
      if dimLen rd egress < cap then
        let resp : Pkt := { dim := rd, payload := { cls := .resp } }
        some (rest, egress ++ [resp])
      else none
    else none

/-- Consume a `resp` at dimension `d` ingress head. -/
def consume (d : Dim) (ingress : List Pkt) : Option (List Pkt) :=
  match dimHead d ingress with
  | none => none
  | some (blk, rest) =>
    if blk.payload.cls == .resp then some rest else none

end MsgStep

end DLFTK.Protocol.UB
