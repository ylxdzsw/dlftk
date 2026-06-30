/-
# DLFTK.Compose.UbOnClos — UB protocol on a one-layer CLOS fabric

**Topology** (`Topology.OneLayerClos`) is separate from **protocol** (UB L4):

* hosts inject / process / consume UB messages,
* each plane runs credit-based switching with `lane = VL`,
* per-host replay / ACK / drop / retransmit on fabric transfers.

This generalizes the two-node UB study: the same `VLMap` knob applies, but
packets traverse switch VOQs instead of a single direct link.
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.Protocol.UB.Message
import DLFTK.Topology.OneLayerClos

namespace DLFTK.Compose.UbOnClos

open DLFTK.Protocol.UB

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

def fabricParams (P : Params) : Topology.OneLayerClos.Params :=
  { nHost := P.nHost, nPlane := P.nPlane, nDim := P.nDim,
    mode := .creditConservative,
    voqCap := P.voqCap, downCap := P.hostIngressCap,
    hostEgressCap := P.hostEgressCap, hostIngressCap := P.hostIngressCap,
    linkUp := P.linkUp }

def msgParams (P : Params) : MsgParams :=
  { vlmap := P.vlmap }

/-- A UB message routed across the fabric. -/
structure FabricPkt where
  src : HostId
  dest : HostId
  pkt : Pkt
deriving DecidableEq, Repr, BEq, Hashable

/-- Per-host UB endpoint state (L4 queues + L2 staging / replay). -/
structure HostUb where
  ubIngress : List Pkt := []
  ubEgress : List FabricPkt := []
  staged : List FabricPkt := []
  replay : List FabricPkt := []
deriving DecidableEq, Repr, BEq, Hashable

structure St where
  fabric : Topology.OneLayerClos.St := {}
  hosts : List HostUb := []
  inTransit : List FabricPkt := []
deriving DecidableEq, Repr, BEq, Hashable

def initHost (_P : Params) : HostUb := {}

def initSt (P : Params) : St :=
  { fabric := Topology.OneLayerClos.initClosSt (fabricParams P),
    hosts := List.replicate P.nHost (initHost P) }

def ubAt (_P : Params) (s : St) (h : HostId) : HostUb :=
  (s.hosts[h]?).getD {}

def setHost (P : Params) (s : St) (h : HostId) (hu : HostUb) : St :=
  let hs := s.hosts ++ List.replicate (h + 1 - s.hosts.length) (initHost P)
  { s with hosts := hs.set h hu }

namespace ComposeStep

variable (P : Params)

/-- **inject** (env): offer a store request from `h` toward `dest`. -/
def inject (h dest : Nat) (s : St) : List St :=
  if h < P.nHost && dest < P.nHost && h ≠ dest then
    let hu := ubAt P s h
    let m := msgParams P
    if hu.ubEgress.length < P.cap then
      let d := m.vlmap .req
      let fp : FabricPkt := { src := h, dest := dest, pkt := { dim := d, payload := { cls := .req } } }
      [setHost P s h { hu with ubEgress := hu.ubEgress ++ [fp] }]
    else []
  else []

/-- Stage one UB egress message onto fabric host egress (L3 header only). -/
def stageToFabric (h plane : Nat) (s : St) : List St :=
  let fab := fabricParams P
  if h < P.nHost && plane < P.nPlane && Topology.OneLayerClos.linkUpAt fab h plane then
    let hu := ubAt P s h
    match hu.ubEgress with
    | [] => []
    | fp :: rest =>
        let fhs := Topology.OneLayerClos.hostAt fab s.fabric h
        if Topology.OneLayerClos.egressLen fhs plane < fab.hostEgressCap then
          let s' := setHost P s h { hu with ubEgress := rest, staged := hu.staged ++ [fp] }
          Topology.OneLayerClos.Step.hostInject fab h plane fp.dest fp.pkt.dim s'.fabric |>.map fun fabric =>
            { s' with fabric := fabric }
        else []
  else []

/-- Peek fabric egress before transmit so staged / inTransit stay in sync. -/
def fabricHostTransmit (h plane : Nat) (s : St) : List St :=
  let fab := fabricParams P
  let hu := ubAt P s h
  if hu.staged.isEmpty || hu.replay.length ≥ P.window then []
  else
    match hu.staged with
    | fp :: stagedRest =>
        let fhs := Topology.OneLayerClos.hostAt fab s.fabric h
        match (fhs.egress[plane]?).getD [] with
        | [] => []
        | hpkt :: _ =>
          if hpkt.dest == fp.dest && hpkt.lane == fp.pkt.dim then
            Topology.OneLayerClos.Step.hostTransmit fab h plane s.fabric |>.map fun fabric =>
              let hu' := { hu with staged := stagedRest, replay := hu.replay ++ [fp] }
              setHost P { s with fabric := fabric, inTransit := s.inTransit ++ [fp] } h hu'
          else []
    | [] => []

def fabricSwitchTransmit (plane input out lane : Nat) (s : St) : List St :=
  Topology.OneLayerClos.Step.switchTransmit (fabricParams P) plane input out lane s.fabric |>.map fun fabric =>
    { s with fabric := fabric }

def fabricDeliver (h plane : Nat) (s : St) : List St :=
  let fab := fabricParams P
  let fhs := Topology.OneLayerClos.hostAt fab s.fabric h
  if Topology.OneLayerClos.ingressLen fhs plane > 0 then
    match (fhs.ingress[plane]?).getD [] with
    | [] => []
    | ipkt :: _ =>
        match s.inTransit.find? (fun fp => fp.dest == h && fp.src == ipkt.src && fp.pkt.dim == ipkt.lane) with
        | none => []
        | some fp =>
            Topology.OneLayerClos.Step.hostDeliver fab h plane s.fabric |>.map fun fabric =>
              let rest := s.inTransit.filter (fun x => !(x == fp))
              let hu := ubAt P s h
              setHost P { s with fabric := fabric, inTransit := rest } h
                { hu with ubIngress := hu.ubIngress ++ [fp.pkt] }
  else []

def processReq (h peer : Nat) (s : St) : List St :=
  if h < P.nHost && peer < P.nHost && h ≠ peer then
    let hu := ubAt P s h
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
    let hu := ubAt P s h
    let m := msgParams P
    let d := m.vlmap .resp
    match MsgStep.consume d hu.ubIngress with
    | none => []
    | some ingress' => [setHost P s h { hu with ubIngress := ingress' }]
  else []

def linkAck (h : Nat) (s : St) : List St :=
  if h < P.nHost then
    let hu := ubAt P s h
    match hu.replay with
    | [] => []
    | _ :: rest => [setHost P s h { hu with replay := rest }]
  else []

def retransmit (h plane : Nat) (s : St) : List St :=
  let fab := fabricParams P
  if h < P.nHost && plane < P.nPlane && Topology.OneLayerClos.linkUpAt fab h plane then
    let hu := ubAt P s h
    match hu.replay with
    | [] => []
    | fp :: _ =>
        let fhs := Topology.OneLayerClos.hostAt fab s.fabric h
        if Topology.OneLayerClos.egressLen fhs plane < fab.hostEgressCap then
          let s' := setHost P s h { hu with staged := hu.staged ++ [fp] }
          Topology.OneLayerClos.Step.hostInject fab h plane fp.dest fp.pkt.dim s'.fabric |>.map fun fabric =>
            { s' with fabric := fabric }
        else []
  else []

def dropInflight (h : Nat) (s : St) : List St :=
  if h < P.nHost then
    let hu := ubAt P s h
    match hu.replay with
    | [] => []
    | _ :: rest => [setHost P s h { hu with replay := rest }]
  else []

def fabricSteps (s : St) : List St :=
  let hosts := List.range P.nHost
  let planes := List.range P.nPlane
  let dims := List.range P.nDim
  hosts.flatMap (fun h => planes.flatMap (fun p => fabricHostTransmit P h p s))
  ++ planes.flatMap (fun p =>
    hosts.flatMap (fun i =>
      hosts.flatMap (fun o =>
        dims.flatMap (fun l => fabricSwitchTransmit P p i o l s))))
  ++ hosts.flatMap (fun h => planes.flatMap (fun p => fabricDeliver P h p s))

def progress (s : St) : List St :=
  let hosts := List.range P.nHost
  let planes := List.range P.nPlane
  let stage := hosts.flatMap (fun h => planes.flatMap (fun p => stageToFabric P h p s))
  let peers := hosts.flatMap (fun h =>
    hosts.filterMap (fun peer => if peer ≠ h then some (h, peer) else none))
  let proc := peers.flatMap (fun (h, peer) => processReq P h peer s)
  let cons := hosts.flatMap (fun h => consumeResp P h s)
  let ack := hosts.flatMap (fun h => linkAck P h s)
  let retx := hosts.flatMap (fun h => planes.flatMap (fun p => retransmit P h p s))
  stage ++ fabricSteps P s ++ proc ++ cons ++ ack ++ retx

def env (s : St) : List St :=
  let hosts := List.range P.nHost
  let injects := hosts.flatMap (fun h =>
    hosts.flatMap (fun d => if d ≠ h then inject P h d s else []))
  let drops := hosts.flatMap (fun h => dropInflight P h s)
  injects ++ drops

end ComposeStep

def system (P : Params) : DLFTK.System St where
  init := [initSt P]
  progress := ComposeStep.progress P
  env := ComposeStep.env P

/-- Cross traffic on plane 0 between hosts 0 and 1. -/
def crossTrafficEnv (P : Params) (s : St) : List St :=
  ComposeStep.inject P 0 1 s ++ ComposeStep.inject P 1 0 s

def crossTrafficSys (P : Params) : DLFTK.System St where
  init := [initSt P]
  progress := ComposeStep.progress P
  env := crossTrafficEnv P

def hasWork (s : St) : Bool :=
  Topology.OneLayerClos.hasWork s.fabric ||
  s.inTransit.length > 0 ||
  s.hosts.any (fun hu =>
    ¬ hu.ubIngress.isEmpty || ¬ hu.ubEgress.isEmpty ||
    ¬ hu.staged.isEmpty || ¬ hu.replay.isEmpty)

end DLFTK.Compose.UbOnClos
