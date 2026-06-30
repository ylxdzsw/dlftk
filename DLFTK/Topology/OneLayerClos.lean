/-
# DLFTK.Topology.OneLayerClos — parameterized one-layer CLOS fabric

Topology-only module: host↔plane mesh with **L3 mode** selectable per instance:

* `creditConservative` — per-packet VOQ credits (`DLFTK.Switch.CreditConservative`)
* `pfc` — threshold pause/resume (`DLFTK.Switch.PFC`)

Protocol (UB, Falcon, RoCE deliver, …) attaches at hosts separately.
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.Layer.L3.Ethernet
import DLFTK.Switch.Types
import DLFTK.Switch.CreditConservative
import DLFTK.Switch.PFC

namespace DLFTK.Topology.OneLayerClos

open DLFTK.Layer.L3.Ethernet
open DLFTK.Switch
open DLFTK.Switch.CreditConservative
open DLFTK.Switch.PFC

abbrev HostId := Nat
abbrev PlaneId := Nat

structure Params where
  nHost : Nat
  nPlane : Nat
  nDim : Nat
  mode : SwitchMode := .creditConservative
  /-- Credit VOQ capacity per `(input, dim)` when `mode = creditConservative`. -/
  voqCap : Nat := 1
  /-- Downstream credits / host ingress cap at switch outputs. -/
  downCap : Nat := 1
  /-- PFC buffer capacity per `(input, dim)` when `mode = pfc`. -/
  queueCap : Nat := 1
  pauseThreshold : Nat := 1
  resumeThreshold : Nat := 0
  hostEgressCap : Nat
  hostIngressCap : Nat
  linkUp : List Bool := []

def linkIdx (P : Params) (h p : Nat) : Nat := h * P.nPlane + p

def allLinksUp (P : Params) : List Bool :=
  List.replicate (P.nHost * P.nPlane) true

def linkUpAt (P : Params) (h p : Nat) : Bool :=
  (P.linkUp[linkIdx P h p]?).getD true

def withLinkUp (P : Params) (linkUp : List Bool) : Params :=
  { P with linkUp := linkUp }

def normalizedLinkUp (P : Params) : List Bool :=
  if P.linkUp.isEmpty then allLinksUp P else P.linkUp

def withBrokenLink (P : Params) (h p : Nat) : Params :=
  withLinkUp P (normalizedLinkUp P |>.set (linkIdx P h p) false)

def withBrokenPlane (P : Params) (plane : Nat) : Params :=
  (List.range P.nHost).foldl (fun P' h => withBrokenLink P' h plane) P

def creditSwitchParams (P : Params) : CreditConservative.Params :=
  { nIn := P.nHost, nOut := P.nHost, nLane := P.nDim,
    voqCap := P.voqCap, downCap := P.downCap }

def pfcSwitchParams (P : Params) : PFC.Params :=
  { nIn := P.nHost, nOut := P.nHost, nPrio := P.nDim,
    queueCap := P.queueCap, pauseThreshold := P.pauseThreshold,
    resumeThreshold := P.resumeThreshold }

structure HostPkt where
  dest : HostId
  lane : Lane
deriving DecidableEq, Repr, BEq, Hashable

structure HostIngressPkt where
  src : HostId
  lane : Lane
deriving DecidableEq, Repr, BEq, Hashable

structure HostSide where
  egress : List (List HostPkt) := []
  ingress : List (List HostIngressPkt) := []
deriving DecidableEq, Repr, BEq, Hashable

inductive PlaneSt where
  | credit (s : CreditConservative.St)
  | pfc (s : PFC.St)
deriving DecidableEq, Repr, BEq, Hashable

structure St where
  hosts : List HostSide := []
  planes : List PlaneSt := []
deriving DecidableEq, Repr, BEq, Hashable

def initHost (P : Params) : HostSide :=
  { egress := List.replicate P.nPlane [],
    ingress := List.replicate P.nPlane [] }

def initPlane (P : Params) : PlaneSt :=
  match P.mode with
  | .creditConservative | .creditSplit =>
    .credit (CreditConservative.initSt (creditSwitchParams P))
  | .pfc =>
    .pfc (PFC.initSt (pfcSwitchParams P))

def initClosSt (P : Params) : St :=
  { hosts := List.replicate P.nHost (initHost P),
    planes := List.replicate P.nPlane (initPlane P) }

def hostAt (P : Params) (s : St) (h : HostId) : HostSide :=
  (s.hosts[h]?).getD (initHost P)

def setHost (P : Params) (s : St) (h : HostId) (hs : HostSide) : St :=
  let hs' := s.hosts ++ List.replicate (h + 1 - s.hosts.length) (initHost P)
  { s with hosts := hs'.set h hs }

def planeAt (P : Params) (s : St) (p : PlaneId) : PlaneSt :=
  (s.planes[p]?).getD (initPlane P)

def setPlane (P : Params) (s : St) (p : PlaneId) (ps : PlaneSt) : St :=
  let ps' := s.planes ++ List.replicate (p + 1 - s.planes.length) (initPlane P)
  { s with planes := ps'.set p ps }

def egressLen (hs : HostSide) (plane : PlaneId) : Nat :=
  ((hs.egress[plane]?).getD []).length

def ingressLen (hs : HostSide) (plane : PlaneId) : Nat :=
  ((hs.ingress[plane]?).getD []).length

def pushEgress (hs : HostSide) (plane : PlaneId) (pkt : HostPkt) : HostSide :=
  let q := (hs.egress[plane]?).getD []
  let egress := hs.egress ++ List.replicate (plane + 1 - hs.egress.length) []
  { hs with egress := egress.set plane (q ++ [pkt]) }

def popEgress (hs : HostSide) (plane : PlaneId) : Option (HostPkt × HostSide) :=
  match hs.egress[plane]? with
  | none | some [] => none
  | some (x :: xs) =>
      let egress := hs.egress ++ List.replicate (plane + 1 - hs.egress.length) []
      some (x, { hs with egress := egress.set plane xs })

def pushIngress (hs : HostSide) (plane : PlaneId) (pkt : HostIngressPkt) : HostSide :=
  let q := (hs.ingress[plane]?).getD []
  let ingress := hs.ingress ++ List.replicate (plane + 1 - hs.ingress.length) []
  { hs with ingress := ingress.set plane (q ++ [pkt]) }

def popIngress (hs : HostSide) (plane : PlaneId) : Option (HostIngressPkt × HostSide) :=
  match hs.ingress[plane]? with
  | none | some [] => none
  | some (x :: xs) =>
      let ingress := hs.ingress ++ List.replicate (plane + 1 - hs.ingress.length) []
      some (x, { hs with ingress := ingress.set plane xs })

def withHostEgress (P : Params) (s : St) (h plane dest lane : Nat) : St :=
  setHost P s h (pushEgress (hostAt P s h) plane { dest := dest, lane := lane })

def withHostIngress (P : Params) (s : St) (h plane src lane : Nat) : St :=
  let hs' := pushIngress (hostAt P s h) plane { src := src, lane := lane }
  let s' := setHost P s h hs'
  match planeAt P s' plane with
  | .credit sw =>
      let di := CreditConservative.downIdx (creditSwitchParams P) h lane
      let sw' := { sw with downCredit := decNat sw.downCredit di }
      setPlane P s' plane (.credit sw')
  | .pfc _ => s'

def withSwitchVOQ (P : Params) (s : St) (plane input out lane : Nat) : St :=
  match planeAt P s plane with
  | .credit sw =>
      let routed : RoutedPkt := { input := input, out := out, lane := lane }
      let ui := CreditConservative.upIdx (creditSwitchParams P) input lane
      let sw' := { sw with
        voq := sw.voq ++ [routed],
        upCredit := decNat sw.upCredit ui }
      setPlane P s plane (.credit sw')
  | .pfc _ => s

namespace Step

variable (P : Params)

def creditHostTransmit (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane && linkUpAt P h plane then
    let hs := hostAt P s h
    match popEgress hs plane with
    | none => []
    | some (pkt, hs') =>
        match planeAt P s plane with
        | .credit sw =>
            let sp := creditSwitchParams P
            let ui := CreditConservative.upIdx sp h pkt.lane
            if natAt sw.upCredit ui > 0 &&
                countByInputLane h pkt.lane sw.voq < sp.voqCap then
              let routed : RoutedPkt := { input := h, out := pkt.dest, lane := pkt.lane }
              let sw' := { sw with
                voq := sw.voq ++ [routed],
                upCredit := decNat sw.upCredit ui }
              [setPlane P (setHost P s h hs') plane (.credit sw')]
            else []
        | .pfc _ => []
  else []

def pfcHostTransmit (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane && linkUpAt P h plane then
    let hs := hostAt P s h
    let dims := List.range P.nDim
    dims.flatMap fun lane =>
      match planeAt P s plane with
      | .pfc sw =>
          let sp := pfcSwitchParams P
          let ui := PFC.upIdx sp h lane
          if boolAt sw.upstreamPaused ui then []
          else
            match popEgress hs plane with
            | none => []
            | some (pkt, hs') =>
                if pkt.lane == lane &&
                    countByInputLane h lane sw.q < sp.queueCap then
                  let routed : RoutedPkt := { input := h, out := pkt.dest, lane := lane }
                  let sw' := { sw with q := sw.q ++ [routed] }
                  [setPlane P (setHost P s h hs') plane (.pfc sw')]
                else []
      | .credit _ => []
  else []

def hostTransmit (h plane : Nat) (s : St) : List St :=
  match P.mode with
  | .creditConservative | .creditSplit => creditHostTransmit P h plane s
  | .pfc => pfcHostTransmit P h plane s

def creditHostDeliver (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane then
    let hs := hostAt P s h
    match popIngress hs plane with
    | none => []
    | some (pkt, hs') =>
        match planeAt P s plane with
        | .credit sw =>
            let sp := creditSwitchParams P
            let di := CreditConservative.downIdx sp h pkt.lane
            if natAt sw.downCredit di < sp.downCap then
              let sw' := { sw with downCredit := incNat sw.downCredit di }
              [setPlane P (setHost P s h hs') plane (.credit sw')]
            else []
        | .pfc _ => []
  else []

def pfcHostDeliver (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane then
    let hs := hostAt P s h
    let dims := List.range P.nDim
    dims.flatMap fun lane =>
      match popIngress hs plane with
      | none => []
      | some (pkt, hs') =>
          if pkt.lane == lane then
            [setHost P s h hs']
          else []
  else []

def hostDeliver (h plane : Nat) (s : St) : List St :=
  match P.mode with
  | .creditConservative | .creditSplit => creditHostDeliver P h plane s
  | .pfc => pfcHostDeliver P h plane s

def creditSwitchTransmit (plane input out lane : Nat) (s : St) : List St :=
  if plane < P.nPlane && input < P.nHost && out < P.nHost && lane < P.nDim &&
      linkUpAt P out plane then
    match planeAt P s plane with
    | .credit sw =>
        let sp := creditSwitchParams P
        let di := CreditConservative.downIdx sp out lane
        match headVOQ input out lane sw.voq with
        | none => []
        | some (pkt, rest) =>
            if natAt sw.downCredit di > 0 then
              let hs := hostAt P s out
              if ingressLen hs plane < P.hostIngressCap then
                let pkt' : HostIngressPkt := { src := pkt.input, lane := pkt.lane }
                let hs' := pushIngress hs plane pkt'
                let ui := CreditConservative.upIdx sp input lane
                let sw' := { sw with
                  voq := rest,
                  upCredit := incNat sw.upCredit ui,
                  downCredit := decNat sw.downCredit di }
                [setPlane P (setHost P s out hs') plane (.credit sw')]
              else []
            else []
    | .pfc _ => []
  else []

def pfcSwitchTransmit (plane input out lane : Nat) (s : St) : List St :=
  if plane < P.nPlane && input < P.nHost && out < P.nHost && lane < P.nDim &&
      linkUpAt P out plane then
    match planeAt P s plane with
    | .pfc sw =>
        let sp := pfcSwitchParams P
        let di := PFC.downIdx sp out lane
        if boolAt sw.downstreamPaused di then []
        else
          match headVOQ input out lane sw.q with
          | none => []
          | some (pkt, rest) =>
              let hs := hostAt P s out
              if ingressLen hs plane < P.hostIngressCap then
                let pkt' : HostIngressPkt := { src := pkt.input, lane := pkt.lane }
                let hs' := pushIngress hs plane pkt'
                let sw' := { sw with q := rest }
                [setPlane P (setHost P s out hs') plane (.pfc sw')]
              else []
    | .credit _ => []
  else []

def switchTransmit (plane input out lane : Nat) (s : St) : List St :=
  match P.mode with
  | .creditConservative | .creditSplit => creditSwitchTransmit P plane input out lane s
  | .pfc => pfcSwitchTransmit P plane input out lane s

def switchPfc (plane : Nat) (s : St) : List St :=
  if P.mode == .pfc && plane < P.nPlane then
    match planeAt P s plane with
    | .pfc sw =>
        let sp := pfcSwitchParams P
        let inputs := List.range P.nHost
        let dims := List.range P.nDim
        let pause := inputs.flatMap (fun i => dims.flatMap (fun d =>
          PFC.Step.pauseUpstream sp i d sw))
        let resume := inputs.flatMap (fun i => dims.flatMap (fun d =>
          PFC.Step.resumeUpstream sp i d sw))
        (pause ++ resume).map fun sw' => setPlane P s plane (.pfc sw')
    | .credit _ => []
  else []

def progress (s : St) : List St :=
  let hosts := List.range P.nHost
  let planes := List.range P.nPlane
  let dims := List.range P.nDim
  let hostTx := hosts.flatMap (fun h => planes.flatMap (fun p => hostTransmit P h p s))
  let hostDel := hosts.flatMap (fun h => planes.flatMap (fun p => hostDeliver P h p s))
  let swTx := planes.flatMap (fun p =>
    hosts.flatMap (fun i =>
      hosts.flatMap (fun o =>
        dims.flatMap (fun l => switchTransmit P p i o l s))))
  let pfc := planes.flatMap (fun p => switchPfc P p s)
  hostTx ++ hostDel ++ swTx ++ pfc

def hostInject (h plane dest lane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane && dest < P.nHost && lane < P.nDim &&
      linkUpAt P h plane then
    let hs := hostAt P s h
    if egressLen hs plane < P.hostEgressCap then
      let pkt : HostPkt := { dest := dest, lane := lane }
      [setHost P s h (pushEgress hs plane pkt)]
    else []
  else []

def env (s : St) : List St :=
  let hosts := List.range P.nHost
  let planes := List.range P.nPlane
  let dims := List.range P.nDim
  hosts.flatMap (fun h =>
    planes.flatMap (fun p =>
      hosts.flatMap (fun d =>
        dims.flatMap (fun l => hostInject P h p d l s))))

end Step

def system (P : Params) : DLFTK.System St where
  init := [initClosSt P]
  progress := Step.progress P
  env := Step.env P

def systemFrom (P : Params) (init : List St) : DLFTK.System St where
  init := init
  progress := Step.progress P
  env := Step.env P

def crossTrafficEnv (P : Params) (s : St) : List St :=
  Step.hostInject P 0 0 1 0 s ++ Step.hostInject P 1 0 0 0 s

def crossTrafficOnPlaneEnv (p : Nat) (P : Params) (s : St) : List St :=
  Step.hostInject P 0 p 1 0 s ++ Step.hostInject P 1 p 0 0 s

def crossTrafficSys (P : Params) : DLFTK.System St where
  init := [initClosSt P]
  progress := Step.progress P
  env := crossTrafficEnv P

def crossTrafficOnPlaneSys (p : Nat) (P : Params) : DLFTK.System St where
  init := [initClosSt P]
  progress := Step.progress P
  env := crossTrafficOnPlaneEnv p P

def hasWork (s : St) : Bool :=
  s.hosts.any (fun hs =>
    hs.egress.any (¬ ·.isEmpty) || hs.ingress.any (¬ ·.isEmpty)) ||
  s.planes.any fun
    | .credit sw => hasRoutedWork sw.voq
    | .pfc sw => hasRoutedWork sw.q

end DLFTK.Topology.OneLayerClos
