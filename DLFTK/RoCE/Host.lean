/-
# DLFTK.RoCE.Host — Shared host-side progress and environment steps

Host **inject** (env) offers RDMA work into the egress queue.
Host **transmit** (progress) moves the egress head into an attached PFC switch
when the switch has not paused that `(input, priority)`.
Host **deliver** (progress) completes ingress packets (RDMA CQ drain).
-/
import DLFTK.RoCE.Model
import DLFTK.Switch.PFC
import DLFTK.Switch.Types

namespace DLFTK.RoCE

open DLFTK.Switch
open DLFTK.Switch.PFC

/-- Context for wiring one host to one PFC switch input port. -/
structure Attach where
  caps : HostCaps
  /-- Switch input port this host feeds. -/
  swIn : InPort
  /-- Switch output port that delivers to this host. -/
  swOut : OutPort
  /-- Link up: both host→switch and switch→host directions. -/
  linkUp : Bool := true
deriving DecidableEq, Repr, BEq, Hashable

/-- Deliver ingress head on `prio` (RDMA completion). -/
def hostDeliver (hs : HostSide) (prio : Prio) : List HostSide :=
  match popIngress hs prio with
  | none => []
  | some (_, hs') => [hs']

namespace HostStep

/-- Offer a new RDMA message on `prio` toward `dest`. -/
def inject (A : Attach) (hs : HostSide) (prio : Prio) (dest : HostId) : List HostSide :=
  if A.linkUp && prio < A.caps.nPrio && egressLen hs prio < A.caps.egressCap then
    [pushEgress hs prio { dest := dest, prio := prio }]
  else []

/-- Transmit egress head into switch `sw` on `prio` (caller updates switch).
Routing uses `routeOut pkt` so each topology can map destination host → egress port. -/
def transmit (A : Attach) (P : Params) (hs : HostSide) (sw : St) (prio : Prio)
    (routeOut : Pkt → OutPort) : List (HostSide × St) :=
  if !A.linkUp || prio >= A.caps.nPrio then []
  else
    let ui := upIdx P A.swIn prio
    if boolAt sw.upstreamPaused ui then []
    else
      match popEgress hs prio with
      | none => []
      | some (pkt, hs') =>
          if countByInputLane A.swIn prio sw.q < P.queueCap then
            let routed : RoutedPkt := { input := A.swIn, out := routeOut pkt, lane := prio }
            let sw' := { sw with q := sw.q ++ [routed] }
            [(hs', sw')]
          else []

end HostStep

end DLFTK.RoCE
