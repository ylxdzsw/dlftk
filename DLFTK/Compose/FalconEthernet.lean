/-
# DLFTK.Compose.FalconEthernet — Falcon L4 on PFC Ethernet CLOS

Two-host mapping: `Peer.A` = host 0, `Peer.B` = host 1. Falcon `transmit*`
steps stage `WirePkt` into fabric egress; fabric forwarding delivers them
into the peer Falcon network queues.
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.Falcon.Transitions
import DLFTK.Topology.OneLayerClos

namespace DLFTK.Compose.FalconEthernet

open DLFTK.Falcon
open DLFTK.Topology.OneLayerClos

structure Params where
  falcon : Falcon.Params
  fabric : Topology.OneLayerClos.Params

def defaultFabric : Topology.OneLayerClos.Params :=
  { nHost := 2, nPlane := 1, nDim := 1, mode := .pfc,
    queueCap := 1, pauseThreshold := 1, resumeThreshold := 0,
    hostEgressCap := 1, hostIngressCap := 1 }

def defaultParams : Params :=
  { falcon := {
      poolCap := 1, rxUlpReqCap := 1, sharedCap := 2,
      reqWindow := 1, dataWindow := 1, txnWindow := 1,
      ordered := true, design := .crCompliant },
    fabric := defaultFabric }

def peerHost : Peer → Nat
  | .A => 0
  | .B => 1

def hostPeer (h : Nat) : Peer := if h == 0 then .A else .B

structure HostOverlay where
  staged : List WirePkt := []
  arrived : List WirePkt := []
deriving DecidableEq, Repr, BEq, Hashable

structure St where
  falcon : Falcon.St := {}
  fabric : Topology.OneLayerClos.St := {}
  overlay : List HostOverlay := []
  inTransit : List (Nat × WirePkt) := []
deriving DecidableEq, Repr, BEq, Hashable

def emptyOverlay : HostOverlay := {}

def initSt (P : Params) : St :=
  { falcon := Falcon.initSt,
    fabric := initClosSt P.fabric,
    overlay := List.replicate P.fabric.nHost emptyOverlay }

def overlayAt (_ : Params) (s : St) (h : Nat) : HostOverlay :=
  (s.overlay[h]?).getD emptyOverlay

def setOverlay (_P : Params) (s : St) (h : Nat) (o : HostOverlay) : St :=
  let o' := s.overlay ++ List.replicate (h + 1 - s.overlay.length) emptyOverlay
  { s with overlay := o'.set h o }

namespace ComposeStep

open DLFTK.Falcon

variable (P : Params)

def stageToFabric (src dest : Nat) (pkt : WirePkt) (s : St) : List St :=
  let Fab := P.fabric
  if src < Fab.nHost && dest < Fab.nHost then
    let plane := 0
    let lane := 0
    let hs := hostAt Fab s.fabric src
    if egressLen hs plane < Fab.hostEgressCap then
      let o := overlayAt P s src
      let s' := setOverlay P s src { o with staged := o.staged ++ [pkt] }
      Topology.OneLayerClos.Step.hostInject Fab src plane dest lane s'.fabric |>.map fun fab =>
        { s' with fabric := fab }
    else []
  else []

def popStaged (src : Nat) (s : St) : Option (WirePkt × St) :=
  let o := overlayAt P s src
  match o.staged with
  | [] => none
  | pkt :: rest => some (pkt, setOverlay P s src { o with staged := rest })

def fabricHostTransmit (h plane : Nat) (s : St) : List St :=
  let Fab := P.fabric
  Topology.OneLayerClos.Step.hostTransmit Fab h plane s.fabric |>.flatMap fun fab =>
    match popStaged P h { s with fabric := fab } with
    | none => [{ s with fabric := fab }]
    | some (pkt, s') =>
      let hs' := hostAt Fab s'.fabric h
      match popEgress hs' plane with
      | none => [{ s with fabric := fab }]
      | some (hpkt, _) =>
        [{ s' with inTransit := s'.inTransit ++ [(hpkt.dest, pkt)] }]

def fabricSwitchTransmit (plane input out lane : Nat) (s : St) : List St :=
  Topology.OneLayerClos.Step.switchTransmit P.fabric plane input out lane s.fabric |>.map fun fab =>
    { s with fabric := fab }

def fabricDeliver (h plane : Nat) (s : St) : List St :=
  let Fab := P.fabric
  let hs := hostAt Fab s.fabric h
  if ingressLen hs plane > 0 then
    Topology.OneLayerClos.Step.hostDeliver Fab h plane s.fabric |>.flatMap fun fab =>
      match s.inTransit.find? (fun (d, _) => d == h) with
      | none => [{ s with fabric := fab }]
      | some (_, pkt) =>
        let rest := s.inTransit.filter (fun (d, p) => !(d == h && p == pkt))
        let s' := { s with fabric := fab, inTransit := rest }
        let o := overlayAt P s' h
        [setOverlay P s' h { o with arrived := o.arrived ++ [pkt] }]
  else []

def admitArrived (h : Nat) (s : St) : List St :=
  let o := overlayAt P s h
  match o.arrived with
  | [] => []
  | pkt :: rest =>
    let n := hostPeer h
    let sd := s.falcon.side n
    let s' := setOverlay P s h { o with arrived := rest }
    match pkt.kind with
    | PktKind.pullReq =>
      [ { s' with falcon := s'.falcon.setSide n { sd with netReq := sd.netReq ++ [pkt] } } ]
    | PktKind.pushData =>
      [ { s' with falcon := s'.falcon.setSide n { sd with pushWait := sd.pushWait ++ [pkt] } } ]
    | PktKind.pullData =>
      let peer := hostPeer (if h == 0 then 1 else 0)
      let psd := s'.falcon.side peer
      let f' := s'.falcon.setSide peer { psd with inFlightPullData := psd.inFlightPullData ++ [pkt] }
      [ { s' with falcon := f' } ]

def bridgedTransmitReq (n : Peer) (s : St) : List St :=
  let F := P.falcon
  let sd := s.falcon.side n
  match Falcon.Step.schedHead F sd with
  | none => []
  | some (pkt, sd') =>
    if pkt.kind != PktKind.pullReq then []
    else if sd'.reqFlight.length < F.reqWindow then
      let peer := s.falcon.side n.peer
      if PoolOps.canAllocNetReq F peer then
        let sd'' : Side := { sd' with reqFlight := sd'.reqFlight ++ [pkt] }
        let peer' := PoolOps.allocNetReq F peer
        let f := s.falcon.setSide n sd'' |>.setSide n.peer peer'
        stageToFabric P (peerHost n) (peerHost n.peer) pkt { s with falcon := f }
      else []
    else []

def bridgedTransmitPush (n : Peer) (s : St) : List St :=
  let F := P.falcon
  let sd := s.falcon.side n
  match Falcon.Step.schedHead F sd with
  | none => []
  | some (pkt, sd') =>
    if pkt.kind != PktKind.pushData then []
    else if sd'.dataFlight.length < F.dataWindow then
      let peer := s.falcon.side n.peer
      if PoolOps.canAllocNetReq F peer then
        let sd'' : Side := { sd' with dataFlight := sd'.dataFlight ++ [pkt] }
        let peer' := PoolOps.allocNetReq F peer
        let f := s.falcon.setSide n sd'' |>.setSide n.peer peer'
        stageToFabric P (peerHost n) (peerHost n.peer) pkt { s with falcon := f }
      else []
    else []

def bridgedTransmitData (n : Peer) (s : St) : List St :=
  let F := P.falcon
  let sd := s.falcon.side n
  match sd.dataLane with
  | [] => []
  | pkt :: rest =>
    if pkt.kind != PktKind.pullData then []
    else if sd.dataFlight.length < F.dataWindow then
      let peer := s.falcon.side n.peer
      if PoolOps.canAllocPullDataRx F peer then
        let sd' := { sd with dataLane := rest, dataFlight := sd.dataFlight ++ [pkt] }
        let peer' := { peer with inFlightPullData := peer.inFlightPullData ++ [pkt] }
        let s' := { s with falcon := s.falcon.setSide n sd' |>.setSide n.peer peer' }
        stageToFabric P (peerHost n) (peerHost n.peer) pkt s'
      else []
    else []

def falconLocal (s : St) : List St :=
  let F := P.falcon
  let peers := [Peer.A, Peer.B]
  peers.flatMap (fun n => Falcon.Step.scheduleTxn F n s.falcon |>.map fun f => { s with falcon := f })
  ++ peers.flatMap (fun n => Falcon.Step.targetPull F n s.falcon |>.map fun f => { s with falcon := f })
  ++ peers.flatMap (fun n => Falcon.Step.deliverPush F n s.falcon |>.map fun f => { s with falcon := f })
  ++ peers.flatMap (fun n => Falcon.Step.landPullData F n s.falcon |>.map fun f => { s with falcon := f })
  ++ peers.flatMap (fun n => Falcon.Step.complete F n s.falcon |>.map fun f => { s with falcon := f })
  ++ peers.flatMap (fun n => Falcon.Step.ackReq F n s.falcon |>.map fun f => { s with falcon := f })
  ++ peers.flatMap (fun n => Falcon.Step.ackData F n s.falcon |>.map fun f => { s with falcon := f })

def fabricSteps (s : St) : List St :=
  let Fab := P.fabric
  let hosts := List.range Fab.nHost
  let planes := List.range Fab.nPlane
  let dims := List.range Fab.nDim
  hosts.flatMap (fun h => planes.flatMap (fun p => fabricHostTransmit P h p s))
  ++ planes.flatMap (fun p =>
    hosts.flatMap (fun i =>
      hosts.flatMap (fun o =>
        dims.flatMap (fun l => fabricSwitchTransmit P p i o l s))))
  ++ hosts.flatMap (fun h => planes.flatMap (fun p => fabricDeliver P h p s))
  ++ planes.flatMap (fun p =>
    Topology.OneLayerClos.Step.switchPfc Fab p s.fabric |>.map fun fab => { s with fabric := fab })

def progress (s : St) : List St :=
  falconLocal P s
  ++ [Peer.A, Peer.B].flatMap (fun n => bridgedTransmitReq P n s)
  ++ [Peer.A, Peer.B].flatMap (fun n => bridgedTransmitPush P n s)
  ++ [Peer.A, Peer.B].flatMap (fun n => bridgedTransmitData P n s)
  ++ fabricSteps P s
  ++ (List.range P.fabric.nHost).flatMap (fun h => admitArrived P h s)

def env (s : St) : List St :=
  [Peer.A, Peer.B].flatMap (fun n =>
    [TxnKind.push, TxnKind.pull].flatMap (fun k =>
      Falcon.Step.inject P.falcon n k s.falcon |>.map fun f => { s with falcon := f }))

end ComposeStep

def system (P : Params) : DLFTK.System St where
  init := [initSt P]
  progress := ComposeStep.progress P
  env := ComposeStep.env P

def hasWork (s : St) : Bool :=
  Falcon.hasWork s.falcon ||
  Topology.OneLayerClos.hasWork s.fabric ||
  s.inTransit.length > 0 ||
  s.overlay.any (fun o => ¬ o.staged.isEmpty || ¬ o.arrived.isEmpty)

end DLFTK.Compose.FalconEthernet
