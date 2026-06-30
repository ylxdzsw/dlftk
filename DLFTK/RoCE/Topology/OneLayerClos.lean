/-
# DLFTK.RoCE.Topology.OneLayerClos — RoCE hosts on PFC-enabled CLOS planes

Same mesh shape as `DLFTK.Switch.Topology.OneLayerClos`, but each plane is a
**PFC switch** instead of a credit-conservative switch. This is the natural RoCE
datacenter pattern: hosts fan out across parallel lossless planes; deadlock
arises from **PFC pause** and **buffer occupancy**, not per-packet credits.

```
        Plane 0 (PFC)          Plane 1 (PFC)
       /  |  \                 /  |  \
   H0 ----+---- H1         H0 ----+---- H1
```

Packet path on plane `p`: host egress → switch `p` VOQ → host ingress → deliver.
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.RoCE.Host
import DLFTK.RoCE.Model
import DLFTK.RoCE.Types
import DLFTK.Switch.PFC
import DLFTK.Switch.Types

namespace DLFTK.RoCE.Topology.OneLayerClos

open DLFTK.Switch
open DLFTK.Switch.PFC
open DLFTK.RoCE

abbrev PlaneId := Nat

structure Params where
  nHost : Nat
  nPlane : Nat
  nPrio : Nat
  /-- PFC switch buffer capacity per `(input, priority)`. -/
  queueCap : Nat
  pauseThreshold : Nat
  resumeThreshold : Nat
  hostEgressCap : Nat
  hostIngressCap : Nat
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

def withBrokenLink (P : Params) (h p : Nat) : Params :=
  withLinkUp P (normalizedLinkUp P |>.set (linkIdx P h p) false)

def hostCaps (P : Params) : HostCaps :=
  { nPrio := P.nPrio, egressCap := P.hostEgressCap, ingressCap := P.hostIngressCap }

def switchParams (P : Params) : PFC.Params :=
  { nIn := P.nHost, nOut := P.nHost, nPrio := P.nPrio,
    queueCap := P.queueCap, pauseThreshold := P.pauseThreshold,
    resumeThreshold := P.resumeThreshold }

def attach (P : Params) (h : HostId) (plane : PlaneId) : Attach :=
  { caps := hostCaps P, swIn := h, swOut := h,
    linkUp := linkUpAt P h plane }

structure St where
  hosts : List HostSide := []
  planes : List PFC.St := []
deriving DecidableEq, Repr, BEq, Hashable

def initClosSt (P : Params) : St :=
  { hosts := List.replicate P.nHost (initHost (hostCaps P)),
    planes := List.replicate P.nPlane (PFC.initSt (switchParams P)) }

def hostAt (P : Params) (s : St) (h : HostId) : HostSide :=
  (s.hosts[h]?).getD (initHost (hostCaps P))

def planeAt (P : Params) (s : St) (p : PlaneId) : PFC.St :=
  (s.planes[p]?).getD (PFC.initSt (switchParams P))

def setHost (P : Params) (s : St) (h : HostId) (hs : HostSide) : St :=
  let hs' := s.hosts ++ List.replicate (h + 1 - s.hosts.length) (initHost (hostCaps P))
  { s with hosts := hs'.set h hs }

def setPlane (P : Params) (s : St) (p : PlaneId) (ps : PFC.St) : St :=
  let ps' := s.planes ++ List.replicate (p + 1 - s.planes.length) (PFC.initSt (switchParams P))
  { s with planes := ps'.set p ps }

namespace Step

variable (P : Params)

def sp : PFC.Params := switchParams P

/-- Host transmits egress head into plane `plane`'s switch. -/
def hostTransmit (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane then
    let A := attach P h plane
    let hs := hostAt P s h
    let sw := planeAt P s plane
    let prios := List.range P.nPrio
    prios.flatMap (fun prio =>
      HostStep.transmit A (sp P) hs sw prio (fun pkt => pkt.dest) |>.map fun (hs', sw') =>
        setPlane P (setHost P s h hs') plane sw')
  else []

/-- Host delivers ingress head on plane `plane`. -/
def hostDeliverHost (h plane : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane then
    let hs := hostAt P s h
    let prios := List.range P.nPrio
    prios.flatMap (fun prio =>
      RoCE.hostDeliver hs prio |>.map fun hs' => setHost P s h hs')
  else []

/-- Switch forwards VOQ head to destination host ingress. Blocked when the
destination host's ingress is full (host-asserted PFC toward the switch). -/
def switchTransmit (plane input out prio : Nat) (s : St) : List St :=
  if plane < P.nPlane && input < P.nHost && out < P.nHost && prio < P.nPrio &&
      linkUpAt P out plane then
    let sw := planeAt P s plane
    let di := downIdx (sp P) out prio
    if boolAt sw.downstreamPaused di then []
    else
      match headVOQ input out prio sw.q with
      | none => []
      | some (pkt, rest) =>
          let hs := hostAt P s out
          if ingressLen hs prio < P.hostIngressCap then
            let pkt' : IngressPkt := { src := pkt.input, prio := pkt.lane }
            let hs' := pushIngress hs prio pkt'
            let sw' := { sw with q := rest }
            [setPlane P (setHost P s out hs') plane sw']
          else []
  else []

/-- PFC pause/resume on plane `plane`'s switch. -/
def switchPfc (plane : Nat) (s : St) : List St :=
  if plane < P.nPlane then
    let sw := planeAt P s plane
    let inputs := List.range P.nHost
    let prios := List.range P.nPrio
    let pause := inputs.flatMap (fun i => prios.flatMap (fun p =>
      PFC.Step.pauseUpstream (sp P) i p sw))
    let resume := inputs.flatMap (fun i => prios.flatMap (fun p =>
      PFC.Step.resumeUpstream (sp P) i p sw))
    (pause ++ resume).map fun sw' => setPlane P s plane sw'
  else []

def progress (s : St) : List St :=
  let hosts := List.range P.nHost
  let planes := List.range P.nPlane
  let lanes := List.range P.nPrio
  let hostTx := hosts.flatMap (fun h => planes.flatMap (fun p => hostTransmit P h p s))
  let hostDel := hosts.flatMap (fun h => planes.flatMap (fun p => hostDeliverHost P h p s))
  let swTx := planes.flatMap (fun p =>
    hosts.flatMap (fun i =>
      hosts.flatMap (fun o =>
        lanes.flatMap (fun l => switchTransmit P p i o l s))))
  let pfc := planes.flatMap (fun p => switchPfc P p s)
  hostTx ++ hostDel ++ swTx ++ pfc

def hostInject (h plane dest prio : Nat) (s : St) : List St :=
  if h < P.nHost && plane < P.nPlane && dest < P.nHost && prio < P.nPrio then
    let A := attach P h plane
    HostStep.inject A (hostAt P s h) prio dest |>.map fun hs' => setHost P s h hs'
  else []

def env (s : St) : List St :=
  let hosts := List.range P.nHost
  let planes := List.range P.nPlane
  let prios := List.range P.nPrio
  hosts.flatMap (fun h =>
    planes.flatMap (fun p =>
      hosts.flatMap (fun d =>
        prios.flatMap (fun pr => hostInject P h p d pr s))))

end Step

def system (P : Params) : DLFTK.System St where
  init := [initClosSt P]
  progress := Step.progress P
  env := Step.env P

def crossTrafficEnv (P : Params) (s : St) : List St :=
  Step.hostInject P 0 0 1 0 s ++ Step.hostInject P 1 0 0 0 s

def crossTrafficSys (P : Params) : DLFTK.System St where
  init := [initClosSt P]
  progress := Step.progress P
  env := crossTrafficEnv P

def hasWork (s : St) : Bool :=
  s.hosts.any hasHostWork || s.planes.any (fun sw => hasRoutedWork sw.q)

end DLFTK.RoCE.Topology.OneLayerClos
