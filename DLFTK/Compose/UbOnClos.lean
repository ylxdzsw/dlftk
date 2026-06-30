/-
# DLFTK.Compose.UbOnClos — UB protocol on a one-layer CLOS fabric

**Topology** (CLOS mesh) is separate from **protocol** (UB L4 + L2 blocks):

* hosts inject / process / consume UB messages,
* each plane runs credit-based switching with `lane = VL`,
* per-host replay / ACK / drop / retransmit on fabric transfers.

This generalizes the two-node UB study: the same `VLMap` knob applies, but
packets traverse switch VOQs instead of a single direct link.
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.Layer.L2.Types
import DLFTK.Protocol.UB.Message
import DLFTK.Switch.Types

namespace DLFTK.Compose.UbOnClos

open DLFTK.Layer
open DLFTK.Layer.L2
open DLFTK.Protocol.UB
open DLFTK.Switch hiding Pkt

abbrev HostId := Nat
abbrev PlaneId := Nat

structure Params where
  nHost : Nat
  nPlane : Nat
  nDim : Nat
  cap : Nat
  window : Nat
  vlmap : VLMap
  voqCap : Nat
  hostIngressCap : Nat
  hostEgressCap : Nat
  linkUp : List Bool := []

def linkIdx (P : Params) (h p : Nat) : Nat := h * P.nPlane + p

def linkUpAt (P : Params) (h p : Nat) : Bool :=
  (P.linkUp[linkIdx P h p]?).getD true

def msgParams (P : Params) : MsgParams :=
  { vlmap := P.vlmap }

/-- A UB message routed across the fabric. -/
structure FabricPkt where
  src : HostId
  dest : HostId
  pkt : Pkt
deriving DecidableEq, Repr, BEq, Hashable

/-- Switch-internal packet retaining UB class through the VOQ. -/
structure UbRoutedPkt where
  input : InPort
  out : OutPort
  lane : Lane
  cls : Cls
deriving DecidableEq, Repr, BEq, Hashable

structure SwitchSt where
  voq : List UbRoutedPkt := []
  upCredit : List Nat := []
  downCredit : List Nat := []
deriving DecidableEq, Repr, BEq, Hashable

def upIdx (P : Params) (input : InPort) (lane : Lane) : Nat := idx2 P.nDim input lane
def downIdx (P : Params) (out : OutPort) (lane : Lane) : Nat := idx2 P.nDim out lane

def initSwitch (P : Params) : SwitchSt :=
  { upCredit := initNat2 P.nHost P.nDim P.voqCap,
    downCredit := initNat2 P.nHost P.nDim P.hostIngressCap }

def headVOQ (input : InPort) (out : OutPort) (lane : Lane) (q : List UbRoutedPkt) :
    Option (UbRoutedPkt × List UbRoutedPkt) :=
  removeFirst (fun p => p.input == input && p.out == out && p.lane == lane) q

def countByInputLane (input : InPort) (lane : Lane) (q : List UbRoutedPkt) : Nat :=
  (q.filter (fun p => p.input == input && p.lane == lane)).length

/-- Per-host UB endpoint state. -/
structure HostUb where
  ubIngress : List Pkt := []
  ubEgress : List FabricPkt := []
  replay : List FabricPkt := []
  planeEgress : List (List FabricPkt) := []
  planeIngress : List (List FabricPkt) := []
deriving DecidableEq, Repr, BEq, Hashable

structure St where
  hosts : List HostUb := []
  planes : List SwitchSt := []
deriving DecidableEq, Repr, BEq, Hashable

def initHost (P : Params) : HostUb :=
  { planeEgress := List.replicate P.nPlane [],
    planeIngress := List.replicate P.nPlane [],
    ubIngress := [], ubEgress := [], replay := [] }

def initClosSt (P : Params) : St :=
  { hosts := List.replicate P.nHost (initHost P),
    planes := List.replicate P.nPlane (initSwitch P) }

def hostAt (P : Params) (s : St) (h : HostId) : HostUb :=
  (s.hosts[h]?).getD (initHost P)

def planeAt (P : Params) (s : St) (p : PlaneId) : SwitchSt :=
  (s.planes[p]?).getD (initSwitch P)

def setHost (P : Params) (s : St) (h : HostId) (hu : HostUb) : St :=
  let hs := s.hosts ++ List.replicate (h + 1 - s.hosts.length) (initHost P)
  { s with hosts := hs.set h hu }

def setPlane (P : Params) (s : St) (p : PlaneId) (sw : SwitchSt) : St :=
  let ps := s.planes ++ List.replicate (p + 1 - s.planes.length) (initSwitch P)
  { s with planes := ps.set p sw }

def planeEgressLen (hu : HostUb) (plane : PlaneId) : Nat :=
  ((hu.planeEgress[plane]?).getD []).length

def planeIngressLen (hu : HostUb) (plane : PlaneId) : Nat :=
  ((hu.planeIngress[plane]?).getD []).length

def pushPlaneEgress (hu : HostUb) (_ : Params) (plane : PlaneId) (fp : FabricPkt) : HostUb :=
  let q := (hu.planeEgress[plane]?).getD []
  let pe := hu.planeEgress ++ List.replicate (plane + 1 - hu.planeEgress.length) []
  { hu with planeEgress := pe.set plane (q ++ [fp]) }

def popPlaneEgress (hu : HostUb) (_ : Params) (plane : PlaneId) : Option (FabricPkt × HostUb) :=
  match (hu.planeEgress[plane]?) with
  | none | some [] => none
  | some (x :: xs) =>
    let pe := hu.planeEgress ++ List.replicate (plane + 1 - hu.planeEgress.length) []
    some (x, { hu with planeEgress := pe.set plane xs })

def pushPlaneIngress (hu : HostUb) (_ : Params) (plane : PlaneId) (fp : FabricPkt) : HostUb :=
  let q := (hu.planeIngress[plane]?).getD []
  let pi := hu.planeIngress ++ List.replicate (plane + 1 - hu.planeIngress.length) []
  { hu with planeIngress := pi.set plane (q ++ [fp]) }

def popPlaneIngress (hu : HostUb) (_ : Params) (plane : PlaneId) : Option (FabricPkt × HostUb) :=
  match (hu.planeIngress[plane]?) with
  | none | some [] => none
  | some (x :: xs) =>
    let pi := hu.planeIngress ++ List.replicate (plane + 1 - hu.planeIngress.length) []
    some (x, { hu with planeIngress := pi.set plane xs })

namespace Step

variable (P : Params)

/-- **inject** (env): offer a store request from `h` toward `dest`. -/
def inject (h dest : Nat) (s : St) : List St :=
  if h < P.nHost && dest < P.nHost && h ≠ dest then
    let hu := hostAt P s h
    let m := msgParams P
    if hu.ubEgress.length < P.cap then
      let d := m.vlmap .req
      let fp : FabricPkt := { src := h, dest := dest, pkt := { dim := d, payload := { cls := .req } } }
      [setHost P s h { hu with ubEgress := hu.ubEgress ++ [fp] }]
    else []
  else []

/-- Move one message from the UB egress queue to a plane staging queue. -/
def stageToPlane (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane && linkUpAt P h plane then
    let hu := hostAt P s h
    match hu.ubEgress with
    | [] => []
    | fp :: rest =>
      if planeEgressLen hu plane < P.hostEgressCap then
        let hu' := { hu with ubEgress := rest }
        [setHost P s h (pushPlaneEgress hu' P plane fp)]
      else []
  else []

def hostTransmit (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane && linkUpAt P h plane then
    let hu := hostAt P s h
    match popPlaneEgress hu P plane with
    | none => []
    | some (fp, hu') =>
        let sw := planeAt P s plane
        let lane := fp.pkt.dim
        let ui := upIdx P h lane
        if natAt sw.upCredit ui > 0 &&
            countByInputLane h lane sw.voq < P.voqCap &&
            hu'.replay.length < P.window then
          let routed : UbRoutedPkt := { input := h, out := fp.dest, lane := lane, cls := fp.pkt.payload.cls }
          let sw' := { sw with
            voq := sw.voq ++ [routed],
            upCredit := decNat sw.upCredit ui }
          let hu'' := { hu' with replay := hu'.replay ++ [fp] }
          [setPlane P (setHost P s h hu'') plane sw']
        else []
  else []

def switchTransmit (plane input out lane : Nat) (s : St) : List St :=
  if plane < P.nPlane && input < P.nHost && out < P.nHost && lane < P.nDim &&
      linkUpAt P out plane then
    let sw := planeAt P s plane
    let di := downIdx P out lane
    match headVOQ input out lane sw.voq with
    | none => []
    | some (rpkt, rest) =>
        if natAt sw.downCredit di > 0 then
          let hu := hostAt P s out
          if planeIngressLen hu plane < P.hostIngressCap then
            let fp : FabricPkt := { src := input, dest := out, pkt := { dim := lane, payload := { cls := rpkt.cls } } }
            let hu' := pushPlaneIngress hu P plane fp
            let ui := upIdx P input lane
            let sw' := { sw with
              voq := rest,
              upCredit := incNat sw.upCredit ui,
              downCredit := decNat sw.downCredit di }
            [setPlane P (setHost P s out hu') plane sw']
          else []
        else []
  else []

/-- Deliver fabric ingress to the local UB ingress queue. -/
def fabricDeliver (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane then
    let hu := hostAt P s h
    match popPlaneIngress hu P plane with
    | none => []
    | some (fp, hu') =>
        let sw := planeAt P s plane
        let di := downIdx P h fp.pkt.dim
        if natAt sw.downCredit di < P.hostIngressCap then
          let hu'' := { hu' with ubIngress := hu'.ubIngress ++ [fp.pkt] }
          let sw' := { sw with downCredit := incNat sw.downCredit di }
          [setPlane P (setHost P s h hu'') plane sw']
        else []
  else []

/-- Process a received `req`; reply to the requester named in the matching fabric history.
We track the requester implicitly: the head `req` on the request VL was sent by
exactly one peer in valid runs; for multi-destination we pair process with the
first waiting `req` and emit `resp` toward all peers that have outstanding reqs
in 2-host workloads this is unique. -/
def processReq (h peer : Nat) (s : St) : List St :=
  if h < P.nHost && peer < P.nHost && h ≠ peer then
    let hu := hostAt P s h
    let m := msgParams P
    let d := m.vlmap .req
    match MsgStep.process m d hu.ubIngress (hu.ubEgress.map (·.pkt)) P.cap with
    | none => []
    | some (ingress', _) =>
      let rd := m.vlmap .resp
      if hu.ubEgress.length < P.cap then
        let fp : FabricPkt := { src := h, dest := peer, pkt := { dim := rd, payload := { cls := .resp } } }
        [setHost P s h { hu with ubIngress := ingress', ubEgress := hu.ubEgress ++ [fp] }]
      else []
  else []

def consumeResp (h : Nat) (s : St) : List St :=
  if h < P.nHost then
    let hu := hostAt P s h
    let m := msgParams P
    let d := m.vlmap .resp
    match MsgStep.consume d hu.ubIngress with
    | none => []
    | some ingress' => [setHost P s h { hu with ubIngress := ingress' }]
  else []

def linkAck (h : Nat) (s : St) : List St :=
  if h < P.nHost then
    let hu := hostAt P s h
    match hu.replay with
    | [] => []
    | _ :: rest => [setHost P s h { hu with replay := rest }]
  else []

def retransmit (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane && linkUpAt P h plane then
    let hu := hostAt P s h
    match hu.replay with
    | [] => []
    | fp :: _ =>
        if planeEgressLen hu plane < P.hostEgressCap then
          [setHost P s h (pushPlaneEgress hu P plane fp)]
        else []
  else []

def dropInflight (h : Nat) (s : St) : List St :=
  if h < P.nHost then
    let hu := hostAt P s h
    match hu.replay with
    | [] => []
    | _ :: rest => [setHost P s h { hu with replay := rest }]
  else []

def progress (s : St) : List St :=
  let hosts := List.range P.nHost
  let planes := List.range P.nPlane
  let lanes := List.range P.nDim
  let stage := hosts.flatMap (fun h => planes.flatMap (fun p => stageToPlane P h p s))
  let htx := hosts.flatMap (fun h => planes.flatMap (fun p => hostTransmit P h p s))
  let swtx := planes.flatMap (fun p =>
    hosts.flatMap (fun i =>
      hosts.flatMap (fun o =>
        lanes.flatMap (fun l => switchTransmit P p i o l s))))
  let deliver := hosts.flatMap (fun h => planes.flatMap (fun p => fabricDeliver P h p s))
  let peers := hosts.flatMap (fun h =>
    hosts.filterMap (fun peer => if peer ≠ h then some (h, peer) else none))
  let proc := peers.flatMap (fun (h, peer) => processReq P h peer s)
  let cons := hosts.flatMap (fun h => consumeResp P h s)
  let ack := hosts.flatMap (fun h => linkAck P h s)
  let retx := hosts.flatMap (fun h => planes.flatMap (fun p => retransmit P h p s))
  stage ++ htx ++ swtx ++ deliver ++ proc ++ cons ++ ack ++ retx

def env (s : St) : List St :=
  let hosts := List.range P.nHost
  let injects := hosts.flatMap (fun h =>
    hosts.flatMap (fun d => if d ≠ h then inject P h d s else []))
  let drops := hosts.flatMap (fun h => dropInflight P h s)
  injects ++ drops

end Step

def system (P : Params) : DLFTK.System St where
  init := [initClosSt P]
  progress := Step.progress P
  env := Step.env P

/-- Cross traffic on plane 0 between hosts 0 and 1. -/
def crossTrafficEnv (P : Params) (s : St) : List St :=
  Step.inject P 0 1 s ++ Step.inject P 1 0 s

def crossTrafficSys (P : Params) : DLFTK.System St where
  init := [initClosSt P]
  progress := Step.progress P
  env := crossTrafficEnv P

def hasWork (s : St) : Bool :=
  s.hosts.any (fun hu =>
    ¬ hu.ubIngress.isEmpty || ¬ hu.ubEgress.isEmpty || ¬ hu.replay.isEmpty ||
    hu.planeEgress.any (¬ ·.isEmpty) || hu.planeIngress.any (¬ ·.isEmpty)) ||
  s.planes.any (fun sw => ¬ sw.voq.isEmpty)

end DLFTK.Compose.UbOnClos
