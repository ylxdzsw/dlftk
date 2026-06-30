/-
# DLFTK.Topology.TwoNode — Degenerate two-endpoint fabric

A **topology** is only wiring: two nodes with one logical L2 hop between them.
Protocol semantics (UB L4, Falcon L4, …) attach at each endpoint separately.

The legacy `DLFTK.UB` study uses this topology with UB message + L2 link steps.
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.Layer.L2.Link
import DLFTK.Layer.L2.Types
import DLFTK.Protocol.UB.Message

namespace DLFTK.Topology.TwoNode

open DLFTK.Layer
open DLFTK.Layer.L2
open DLFTK.Protocol.UB

inductive Node | A | B
deriving DecidableEq, Repr, BEq, Hashable

def Node.peer : Node → Node
  | .A => .B
  | .B => .A

/-- Topology + L2 parameters for a single bidirectional hop. -/
structure Params where
  nDim : Nat
  cap : Nat
  window : Nat
  vlmap : VLMap

def linkParams (P : Params) : LinkParams :=
  { nDim := P.nDim, cap := P.cap, window := P.window }

def msgParams (P : Params) : MsgParams :=
  { vlmap := P.vlmap }

abbrev Endpoint := LinkSide Msg

structure St where
  a : Endpoint := {}
  b : Endpoint := {}
deriving DecidableEq, Repr, BEq, Hashable

def St.side (s : St) : Node → Endpoint
  | .A => s.a
  | .B => s.b

def St.setSide (s : St) : Node → Endpoint → St
  | .A, sd => { s with a := sd }
  | .B, sd => { s with b := sd }

namespace Step

variable (P : Params)

def inject (n : Node) (s : St) : List St :=
  let self := s.side n
  let m := msgParams P
  (MsgStep.inject m self.egress P.cap).map fun egress' =>
    s.setSide n { self with egress := egress' }

def transmitDim (n : Node) (d : Dim) (s : St) : List St :=
  let self := s.side n
  let peer := s.side n.peer
  let lp := linkParams P
  (LinkStep.transmit lp d self peer).map fun (self', peer') =>
    (s.setSide n self').setSide n.peer peer'

def processDim (n : Node) (d : Dim) (s : St) : List St :=
  let self := s.side n
  let peer := s.side n.peer
  let m := msgParams P
  match MsgStep.process m d self.ingress self.egress P.cap with
  | none => []
  | some (ingress', egress') =>
    let self' := { self with ingress := ingress', egress := egress' }
    let peer' := LinkStep.returnCredit d peer
    [(s.setSide n self').setSide n.peer peer']

def consumeDim (n : Node) (d : Dim) (s : St) : List St :=
  let self := s.side n
  let peer := s.side n.peer
  match MsgStep.consume d self.ingress with
  | none => []
  | some ingress' =>
    let self' := { self with ingress := ingress' }
    let peer' := LinkStep.returnCredit d peer
    [(s.setSide n self').setSide n.peer peer']

def linkAck (n : Node) (s : St) : List St :=
  (LinkStep.linkAck (s.side n)).map fun self' => s.setSide n self'

def retransmitDim (n : Node) (d : Dim) (s : St) : List St :=
  let self := s.side n
  let peer := s.side n.peer
  let lp := linkParams P
  (LinkStep.retransmit lp d self peer).map fun (self', peer') =>
    (s.setSide n self').setSide n.peer peer'

def dropInflight (n : Node) (s : St) : List St :=
  (LinkStep.dropInflight (s.side n)).map fun self' => s.setSide n self'

def progress (s : St) : List St :=
  let nodes := [Node.A, Node.B]
  let dims := List.range P.nDim
  nodes.flatMap fun n =>
    dims.flatMap (fun d => transmitDim P n d s)
    ++ dims.flatMap (fun d => processDim P n d s)
    ++ dims.flatMap (fun d => consumeDim n d s)
    ++ dims.flatMap (fun d => retransmitDim P n d s)
    ++ linkAck n s

def env (s : St) : List St :=
  [Node.A, Node.B].flatMap (fun n => inject P n s)
    ++ [Node.A, Node.B].flatMap (fun n => dropInflight n s)

end Step

def initSt (P : Params) : St :=
  let sd : Endpoint := { credit := initCredit (linkParams P) }
  { a := sd, b := sd }

def system (P : Params) : DLFTK.System St where
  init := [initSt P]
  progress := Step.progress P
  env := Step.env P

def hasWork (s : St) : Bool :=
  ¬ (s.a.ingress.isEmpty ∧ s.a.egress.isEmpty ∧ s.a.replay.isEmpty
     ∧ s.b.ingress.isEmpty ∧ s.b.egress.isEmpty ∧ s.b.replay.isEmpty)

end DLFTK.Topology.TwoNode
