/-
# DLFTK.RoCE.Topology.OneLayerClos — PFC CLOS (compat layer)

Delegates to `DLFTK.Topology.OneLayerClos` with `mode = pfc`.
-/
import DLFTK.Topology.OneLayerClos
import DLFTK.RoCE.Model

namespace DLFTK.RoCE.Topology.OneLayerClos

open DLFTK.Topology.OneLayerClos (HostId St linkIdx allLinksUp linkUpAt normalizedLinkUp
  hasWork initClosSt hostAt setHost system crossTrafficEnv crossTrafficSys pfcSwitchParams)

open DLFTK.RoCE

abbrev PlaneId := Nat

structure Params where
  nHost : Nat
  nPlane : Nat
  nPrio : Nat
  queueCap : Nat
  pauseThreshold : Nat
  resumeThreshold : Nat
  hostEgressCap : Nat
  hostIngressCap : Nat
  linkUp : List Bool := []
deriving DecidableEq, Repr, BEq, Hashable

def toFabric (P : Params) : DLFTK.Topology.OneLayerClos.Params :=
  { nHost := P.nHost, nPlane := P.nPlane, nDim := P.nPrio,
    mode := .pfc,
    queueCap := P.queueCap, pauseThreshold := P.pauseThreshold,
    resumeThreshold := P.resumeThreshold,
    hostEgressCap := P.hostEgressCap, hostIngressCap := P.hostIngressCap,
    linkUp := P.linkUp }

def withLinkUp (P : Params) (linkUp : List Bool) : Params :=
  { P with linkUp := linkUp }

def withBrokenLink (P : Params) (h p : Nat) : Params :=
  withLinkUp P ((if P.linkUp.isEmpty then allLinksUp (toFabric P) else P.linkUp)
    |>.set (linkIdx (toFabric P) h p) false)

def hostCaps (P : Params) : HostCaps :=
  { nPrio := P.nPrio, egressCap := P.hostEgressCap, ingressCap := P.hostIngressCap }

def switchParams (P : Params) : DLFTK.Switch.PFC.Params :=
  pfcSwitchParams (toFabric P)

def planeAt (P : Params) (s : St) (p : PlaneId) : DLFTK.Switch.PFC.St :=
  match DLFTK.Topology.OneLayerClos.planeAt (toFabric P) s p with
  | .pfc sw => sw
  | .credit _ => DLFTK.Switch.PFC.initSt (switchParams P)

def setPlane (P : Params) (s : St) (p : PlaneId) (sw : DLFTK.Switch.PFC.St) : St :=
  DLFTK.Topology.OneLayerClos.setPlane (toFabric P) s p (.pfc sw)

namespace Step
def hostTransmit (P : Params) := DLFTK.Topology.OneLayerClos.Step.hostTransmit (toFabric P)
def hostDeliverHost (P : Params) := DLFTK.Topology.OneLayerClos.Step.hostDeliver (toFabric P)
def switchTransmit (P : Params) := DLFTK.Topology.OneLayerClos.Step.switchTransmit (toFabric P)
def switchPfc (P : Params) := DLFTK.Topology.OneLayerClos.Step.switchPfc (toFabric P)
def progress (P : Params) := DLFTK.Topology.OneLayerClos.Step.progress (toFabric P)
def hostInject (P : Params) := DLFTK.Topology.OneLayerClos.Step.hostInject (toFabric P)
def env (P : Params) := DLFTK.Topology.OneLayerClos.Step.env (toFabric P)
end Step

def hostDeliver := Step.hostDeliverHost

end DLFTK.RoCE.Topology.OneLayerClos
