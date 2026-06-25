/-
# DLFTK.Switch.Topology.OneLayerClos — one-layer CLOS with full host–plane mesh

A **one-layer CLOS** (single switching stage) with **P parallel planes** (switches):

```
        Plane 0                Plane 1
       /  |  \                /  |  \
   H0 ----+---- H1        H0 ----+---- H1
       \  |  /                \  |  /
        ...                      ...
```

Every host connects to **every plane**; each plane is an independent
`CreditConservative` switch with `nIn = nOut = nHost`. A packet from host `h`
destined for host `d` on plane `p` traverses:

1. host `h` egress queue for plane `p`
2. switch `p` input port `h` → VOQ → output port `d`
3. host `d` ingress queue from plane `p`

Link flow control is wired as follows:

* **Host → plane**: switch upstream credit on `(input = h, lane)` and VOQ capacity.
* **Plane → host**: switch downstream credit on `(output = d, lane)`, sized to the
  host ingress capacity; returned when the host **delivers** the packet.

A **broken host↔plane link** disables host transmission on that plane and
switch→host delivery on that plane, but already-delivered host ingress can still
be consumed (`hostDeliver`). This models a bidirectional link failure while
keeping local delivery progress possible.

Hosts offer load via environment `inject`; switches do not accept external inject
in this topology (all traffic enters at hosts).
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.Switch.Types
import DLFTK.Switch.CreditConservative

namespace DLFTK.Switch.Topology.OneLayerClos

open DLFTK.Switch
open DLFTK.Switch.CreditConservative

abbrev HostId := Nat
abbrev PlaneId := Nat

/-- Static parameters for a CLOS instance. -/
structure Params where
  nHost : Nat
  nPlane : Nat
  nLane : Nat
  /-- Switch VOQ capacity per `(input, lane)` (upstream credit pool). -/
  voqCap : Nat
  /-- Host ingress capacity per `(plane, lane)` at each switch output. -/
  hostIngressCap : Nat
  /-- Max packets a host may queue per plane before transmission. -/
  hostEgressCap : Nat
  /-- Host↔plane link status, flattened as `(host, plane)` via `linkIdx`.
  `true` = link up; `false` = broken (no host transmit or switch→host delivery). -/
  linkUp : List Bool := []
deriving DecidableEq, Repr, BEq, Hashable

def linkIdx (P : Params) (h p : Nat) : Nat := h * P.nPlane + p

def allLinksUp (P : Params) : List Bool :=
  List.replicate (P.nHost * P.nPlane) true

def linkUpAt (P : Params) (h p : Nat) : Bool :=
  (P.linkUp[linkIdx P h p]?).getD true

def withLinkUp (P : Params) (linkUp : List Bool) : Params :=
  { P with linkUp := linkUp }

def normalizedLinkUp (P : Params) : List Bool :=
  if P.linkUp.isEmpty then allLinksUp P else P.linkUp

/-- Mark the `(host, plane)` bidirectional link as broken. -/
def withBrokenLink (P : Params) (h p : Nat) : Params :=
  withLinkUp P (normalizedLinkUp P |>.set (linkIdx P h p) false)

/-- Mark every link incident to a plane as broken. -/
def withBrokenPlane (P : Params) (plane : Nat) : Params :=
  (List.range P.nHost).foldl (fun P' h => withBrokenLink P' h plane) P

def switchParams (P : Params) : CreditConservative.Params :=
  { nIn := P.nHost, nOut := P.nHost, nLane := P.nLane,
    voqCap := P.voqCap, downCap := P.hostIngressCap }

/-- Egress packet waiting at a host for a chosen plane. -/
structure HostPkt where
  dest : HostId
  lane : Lane
deriving DecidableEq, Repr, BEq, Hashable

/-- Packet received at a host from a plane. -/
structure HostIngressPkt where
  src : HostId
  lane : Lane
deriving DecidableEq, Repr, BEq, Hashable

structure HostSide where
  /-- One FIFO egress queue per plane. -/
  egress : List (List HostPkt) := []
  /-- One FIFO ingress queue per plane. -/
  ingress : List (List HostIngressPkt) := []
deriving DecidableEq, Repr, BEq, Hashable

structure St where
  hosts : List HostSide := []
  planes : List CreditConservative.St := []
deriving DecidableEq, Repr, BEq, Hashable

/-! ## Host-side list helpers -/

def initHost (P : Params) : HostSide :=
  { egress := List.replicate P.nPlane [],
    ingress := List.replicate P.nPlane [] }

def hostAt (P : Params) (s : St) (h : HostId) : HostSide :=
  (s.hosts[h]?).getD (initHost P)

def planeAt (P : Params) (s : St) (p : PlaneId) : CreditConservative.St :=
  (s.planes[p]?).getD (CreditConservative.initSt (switchParams P))

def setHost (P : Params) (s : St) (h : HostId) (hs : HostSide) : St :=
  let hs' := s.hosts ++ List.replicate (h + 1 - s.hosts.length) (initHost P)
  { s with hosts := hs'.set h hs }

def setPlane (P : Params) (s : St) (p : PlaneId) (ps : CreditConservative.St) : St :=
  let ps' := s.planes ++ List.replicate (p + 1 - s.planes.length) (CreditConservative.initSt (switchParams P))
  { s with planes := ps'.set p ps }

def initClosSt (P : Params) : St :=
  { hosts := List.replicate P.nHost (initHost P),
    planes := List.replicate P.nPlane (CreditConservative.initSt (switchParams P)) }

def egressLen (hs : HostSide) (plane : PlaneId) : Nat :=
  ((hs.egress[plane]?).getD []).length

def ingressLen (hs : HostSide) (plane : PlaneId) : Nat :=
  ((hs.ingress[plane]?).getD []).length

def pushEgress (hs : HostSide) (plane : PlaneId) (pkt : HostPkt) : HostSide :=
  let q := (hs.egress[plane]?).getD []
  let egress := hs.egress ++ List.replicate (plane + 1 - hs.egress.length) []
  { hs with egress := egress.set plane (q ++ [pkt]) }

def popEgress (hs : HostSide) (plane : PlaneId) : Option (HostPkt × HostSide) :=
  match (hs.egress[plane]?) with
  | none | some [] => none
  | some (x :: xs) =>
      let egress := hs.egress ++ List.replicate (plane + 1 - hs.egress.length) []
      some (x, { hs with egress := egress.set plane xs })

def pushIngress (hs : HostSide) (plane : PlaneId) (pkt : HostIngressPkt) : HostSide :=
  let q := (hs.ingress[plane]?).getD []
  let ingress := hs.ingress ++ List.replicate (plane + 1 - hs.ingress.length) []
  { hs with ingress := ingress.set plane (q ++ [pkt]) }

def popIngress (hs : HostSide) (plane : PlaneId) : Option (HostIngressPkt × HostSide) :=
  match (hs.ingress[plane]?) with
  | none | some [] => none
  | some (x :: xs) =>
      let ingress := hs.ingress ++ List.replicate (plane + 1 - hs.ingress.length) []
      some (x, { hs with ingress := ingress.set plane xs })

/-- Queue one egress packet at host `h` for plane `plane`. -/
def withHostEgress (P : Params) (s : St) (h plane dest lane : Nat) : St :=
  setHost P s h (pushEgress (hostAt P s h) plane { dest := dest, lane := lane })

/-- Queue one ingress packet at host `h` from plane `plane`, consuming downstream
credit on that plane (consistent with a completed switch→host transfer). -/
def withHostIngress (P : Params) (s : St) (h plane src lane : Nat) : St :=
  let hs' := pushIngress (hostAt P s h) plane { src := src, lane := lane }
  let s' := setHost P s h hs'
  let sw := planeAt P s' plane
  let di := CreditConservative.downIdx (switchParams P) h lane
  let sw' := { sw with downCredit := decNat sw.downCredit di }
  setPlane P s' plane sw'

/-- Place one packet inside plane `plane`'s VOQ (upstream credit already consumed). -/
def withSwitchVOQ (P : Params) (s : St) (plane input out lane : Nat) : St :=
  let sw := planeAt P s plane
  let routed : RoutedPkt := { input := input, out := out, lane := lane }
  let ui := CreditConservative.upIdx (switchParams P) input lane
  let sw' := { sw with
    voq := sw.voq ++ [routed],
    upCredit := decNat sw.upCredit ui }
  setPlane P s plane sw'

namespace Step

variable (P : Params)

def sp : CreditConservative.Params := switchParams P

/-- Host transmits the head of its plane-`plane` egress queue into switch `plane`. -/
def hostTransmit (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane && linkUpAt P h plane then
    let hs := hostAt P s h
    match popEgress hs plane with
    | none => []
    | some (pkt, hs') =>
        let sw := planeAt P s plane
        let ui := CreditConservative.upIdx (sp P) h pkt.lane
        if natAt sw.upCredit ui > 0 &&
            countByInputLane h pkt.lane sw.voq < (sp P).voqCap then
          let routed : RoutedPkt := { input := h, out := pkt.dest, lane := pkt.lane }
          let sw' := { sw with
            voq := sw.voq ++ [routed],
            upCredit := decNat sw.upCredit ui }
          [setPlane P (setHost P s h hs') plane sw']
        else []
  else []

/-- Host delivers the head of its plane-`plane` ingress queue, returning downstream
credit to that plane's switch. -/
def hostDeliver (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane then
    let hs := hostAt P s h
    match popIngress hs plane with
    | none => []
    | some (pkt, hs') =>
        let sw := planeAt P s plane
        let di := CreditConservative.downIdx (sp P) h pkt.lane
        if natAt sw.downCredit di < (sp P).downCap then
          let sw' := { sw with downCredit := incNat sw.downCredit di }
          [setPlane P (setHost P s h hs') plane sw']
        else []
  else []

/-- Switch transmits from VOQ toward a host; packet lands in host ingress. -/
def switchTransmit (plane input out lane : Nat) (s : St) : List St :=
  if plane < P.nPlane && input < P.nHost && out < P.nHost && lane < P.nLane &&
      linkUpAt P out plane then
    let sw := planeAt P s plane
    let di := CreditConservative.downIdx (sp P) out lane
    match headVOQ input out lane sw.voq with
    | none => []
    | some (pkt, rest) =>
        if natAt sw.downCredit di > 0 then
          let hs := hostAt P s out
          if ingressLen hs plane < P.hostIngressCap then
            let pkt' : HostIngressPkt := { src := pkt.input, lane := pkt.lane }
            let hs' := pushIngress hs plane pkt'
            let ui := CreditConservative.upIdx (sp P) input lane
            let sw' := { sw with
              voq := rest,
              upCredit := incNat sw.upCredit ui,
              downCredit := decNat sw.downCredit di }
            [setPlane P (setHost P s out hs') plane sw']
          else []
        else []
  else []

def progress (s : St) : List St :=
  let hosts := List.range P.nHost
  let planes := List.range P.nPlane
  let lanes := List.range P.nLane
  let hostTx := hosts.flatMap (fun h => planes.flatMap (fun p => hostTransmit P h p s))
  let hostDel := hosts.flatMap (fun h => planes.flatMap (fun p => hostDeliver P h p s))
  let swTx := planes.flatMap (fun p =>
    hosts.flatMap (fun i =>
      hosts.flatMap (fun o =>
        lanes.flatMap (fun l => switchTransmit P p i o l s))))
  hostTx ++ hostDel ++ swTx

/-- Offer load at a host: queue a packet on a chosen plane toward `dest`. -/
def hostInject (h plane dest lane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane && dest < P.nHost && lane < P.nLane &&
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
  let lanes := List.range P.nLane
  hosts.flatMap (fun h =>
    planes.flatMap (fun p =>
      hosts.flatMap (fun d =>
        lanes.flatMap (fun l => hostInject P h p d l s))))

end Step

def system (P : Params) : DLFTK.System St where
  init := [initClosSt P]
  progress := Step.progress P
  env := Step.env P

def systemFrom (P : Params) (init : List St) : DLFTK.System St where
  init := init
  progress := Step.progress P
  env := Step.env P

/-- Offer cross traffic on plane 0: H0→H1 and H1→H0 (lane 0). -/
def crossTrafficEnv (P : Params) (s : St) : List St :=
  Step.hostInject P 0 0 1 0 s ++ Step.hostInject P 1 0 0 0 s

/-- Cross traffic on plane `p` (only if that plane's host links are up). -/
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
  s.planes.any (fun sw => hasRoutedWork sw.voq)

end DLFTK.Switch.Topology.OneLayerClos
