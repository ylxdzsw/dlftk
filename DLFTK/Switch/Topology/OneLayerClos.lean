/-
# DLFTK.Switch.Topology.OneLayerClos — credit-conservative CLOS (compat layer)

Re-exports `DLFTK.Topology.OneLayerClos` specialized to `creditConservative` mode.
-/
import DLFTK.Topology.OneLayerClos

namespace DLFTK.Switch.Topology.OneLayerClos

open DLFTK.Topology.OneLayerClos (HostId PlaneId HostPkt HostIngressPkt HostSide
  linkIdx allLinksUp linkUpAt normalizedLinkUp egressLen ingressLen
  pushEgress popEgress pushIngress popIngress initHost hostAt setHost
  crossTrafficEnv creditSwitchParams)

/-- Legacy state type (now the unified topology state). -/
abbrev St := DLFTK.Topology.OneLayerClos.St

/-- Legacy parameter record (always credit-conservative). -/
structure Params where
  nHost : Nat
  nPlane : Nat
  nLane : Nat
  voqCap : Nat
  hostIngressCap : Nat
  hostEgressCap : Nat
  linkUp : List Bool := []
deriving DecidableEq, Repr, BEq, Hashable

def toFabric (P : Params) : DLFTK.Topology.OneLayerClos.Params :=
  { nHost := P.nHost, nPlane := P.nPlane, nDim := P.nLane,
    mode := .creditConservative,
    voqCap := P.voqCap, downCap := P.hostIngressCap,
    hostEgressCap := P.hostEgressCap, hostIngressCap := P.hostIngressCap,
    linkUp := P.linkUp }

def withLinkUp (P : Params) (linkUp : List Bool) : Params :=
  { P with linkUp := linkUp }

def withBrokenLink (P : Params) (h p : Nat) : Params :=
  withLinkUp P ((if P.linkUp.isEmpty then allLinksUp (toFabric P) else P.linkUp)
    |>.set (linkIdx (toFabric P) h p) false)

def withBrokenPlane (P : Params) (plane : Nat) : Params :=
  (List.range P.nHost).foldl (fun P' h => withBrokenLink P' h plane) P

def switchParams (P : Params) : DLFTK.Switch.CreditConservative.Params :=
  creditSwitchParams (toFabric P)

def planeAt (P : Params) (s : St) (p : PlaneId) : DLFTK.Switch.CreditConservative.St :=
  match DLFTK.Topology.OneLayerClos.planeAt (toFabric P) s p with
  | .credit sw => sw
  | .pfc _ => DLFTK.Switch.CreditConservative.initSt (switchParams P)

def setPlane (P : Params) (s : St) (p : PlaneId) (sw : DLFTK.Switch.CreditConservative.St) : St :=
  DLFTK.Topology.OneLayerClos.setPlane (toFabric P) s p (.credit sw)

def withHostEgress (P : Params) (s : St) (h plane dest lane : Nat) : St :=
  DLFTK.Topology.OneLayerClos.withHostEgress (toFabric P) s h plane dest lane

def withSwitchVOQ (P : Params) (s : St) (plane input out lane : Nat) : St :=
  DLFTK.Topology.OneLayerClos.withSwitchVOQ (toFabric P) s plane input out lane

def withHostIngress (P : Params) (s : St) (h plane src lane : Nat) : St :=
  DLFTK.Topology.OneLayerClos.withHostIngress (toFabric P) s h plane src lane

def initClosSt (P : Params) : St :=
  DLFTK.Topology.OneLayerClos.initClosSt (toFabric P)

def setHost (P : Params) (s : St) (h : HostId) (hs : HostSide) : St :=
  DLFTK.Topology.OneLayerClos.setHost (toFabric P) s h hs

namespace Step
def hostTransmit (P : Params) := DLFTK.Topology.OneLayerClos.Step.hostTransmit (toFabric P)
def hostDeliver (P : Params) := DLFTK.Topology.OneLayerClos.Step.hostDeliver (toFabric P)
def switchTransmit (P : Params) := DLFTK.Topology.OneLayerClos.Step.switchTransmit (toFabric P)
def progress (P : Params) := DLFTK.Topology.OneLayerClos.Step.progress (toFabric P)
def hostInject (P : Params) := DLFTK.Topology.OneLayerClos.Step.hostInject (toFabric P)
def env (P : Params) := DLFTK.Topology.OneLayerClos.Step.env (toFabric P)
end Step

def system (P : Params) : DLFTK.System St :=
  DLFTK.Topology.OneLayerClos.system (toFabric P)

def systemFrom (P : Params) (init : List St) : DLFTK.System St :=
  DLFTK.Topology.OneLayerClos.systemFrom (toFabric P) init
def crossTrafficEnv (P : Params) (s : St) : List St :=
  DLFTK.Topology.OneLayerClos.crossTrafficEnv (toFabric P) s
def crossTrafficOnPlaneEnv (p : Nat) (P : Params) (s : St) : List St :=
  DLFTK.Topology.OneLayerClos.crossTrafficOnPlaneEnv p (toFabric P) s

def crossTrafficOnPlaneSys (p : Nat) (P : Params) : DLFTK.System St :=
  { init := [initClosSt P],
    progress := Step.progress P,
    env := crossTrafficOnPlaneEnv p P }

def crossTrafficSys (P : Params) : DLFTK.System St :=
  { init := [initClosSt P],
    progress := Step.progress P,
    env := crossTrafficEnv P }

def hasWork := DLFTK.Topology.OneLayerClos.hasWork

end DLFTK.Switch.Topology.OneLayerClos
