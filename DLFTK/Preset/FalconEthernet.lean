/-
# DLFTK.Preset.FalconEthernet — Falcon L4 on Ethernet L3

Falcon runs over switched Ethernet (PFC lossless hops on a CLOS or line
topology). This preset names the feature bundle:

* **L4** — `DLFTK.Falcon` transaction / resource pools,
* **L2+L3** — `DLFTK.Layer.L3.Ethernet` PFC switches + `RoCE.Topology` wiring.

Full endpoint composition (Falcon steps at each host, Ethernet forwarding
between hosts) is the next integration step; this module fixes the parameter
bundle and documents the intended assembly.
-/
import DLFTK.Falcon.Model
import DLFTK.Falcon.Transitions
import DLFTK.Layer.L3.Ethernet
import DLFTK.RoCE.Topology.OneLayerClos

namespace DLFTK.Preset.FalconEthernet

open DLFTK.Falcon
open DLFTK.Layer.L3.Ethernet
open DLFTK.RoCE.Topology.OneLayerClos

/-- Falcon transaction parameters paired with an Ethernet CLOS fabric. -/
structure Params where
  falcon : Falcon.Params
  fabric : FabricParams

/-- Ethernet CLOS parameters derived from the fabric bundle. -/
def closParams (P : Params) : RoCE.Topology.OneLayerClos.Params :=
  { nHost := P.fabric.nHost,
    nPlane := P.fabric.nPlane,
    nPrio := P.fabric.nDim,
    queueCap := P.fabric.queueCap,
    pauseThreshold := P.fabric.pauseThreshold,
    resumeThreshold := P.fabric.resumeThreshold,
    hostEgressCap := 1,
    hostIngressCap := 1,
    linkUp := P.fabric.linkUp }

/-- Default small Falcon-on-Ethernet instance (2 hosts, 1 plane, PFC). -/
def defaultParams : Params :=
  { falcon := {
      poolCap := 1, rxUlpReqCap := 1, sharedCap := 2,
      reqWindow := 1, dataWindow := 1, txnWindow := 1,
      ordered := true, design := .crCompliant },
    fabric := {
      nHost := 2, nPlane := 1, nDim := 1, mode := .pfc,
      queueCap := 1, pauseThreshold := 1, resumeThreshold := 0 } }

/-- Underlying Ethernet fabric system (PFC CLOS). Falcon L4 attaches at hosts. -/
def fabricSys (P : Params) : DLFTK.System RoCE.Topology.OneLayerClos.St :=
  system (closParams P)

end DLFTK.Preset.FalconEthernet
