/-
# DLFTK.RoCE.Dependency — PFC pause wait-for graphs

Extracts **pause / buffer wait-for** structure from RoCE fabric states. Unlike
UB's message-dependent req→resp cycle, RoCE deadlock is characterized by
**PFC pause propagation** and **cyclic buffer dependency** across hops.

For `TwoSwitchLine`, vertices are `H0`, `SW0`, `SW1`, `H1`. An edge `x → y`
means `x` cannot make progress because `y` (or a resource `y` holds) blocks it.
-/
import DLFTK.Graph
import DLFTK.RoCE.Topology.TwoSwitchLine
import DLFTK.Switch.PFC
import DLFTK.Switch.Types

namespace DLFTK.RoCE

open DLFTK.Switch

/-- Fabric entity in the two-switch line topology. -/
inductive LineNode | H0 | SW0 | SW1 | H1
deriving DecidableEq, Repr, BEq, Hashable

namespace LineNode

def all : List LineNode := [.H0, .SW0, .SW1, .H1]

end LineNode

namespace TwoSwitchLineDep

abbrev Params := Topology.TwoSwitchLine.Params
abbrev St := Topology.TwoSwitchLine.St

open Topology.TwoSwitchLine.Port

/-- `true` when host has a non-empty egress queue on `prio`. -/
def hostEgressWaiting (hs : RoCE.HostSide) (prio : Nat) : Bool :=
  RoCE.egressLen hs prio > 0

/-- `true` when switch has asserted PFC pause toward input `inp` on `prio`. -/
def switchPausedUpstream (P : Params) (sw : PFC.St) (inp : Nat) (prio : Nat) : Bool :=
  boolAt sw.upstreamPaused (PFC.upIdx (Topology.TwoSwitchLine.sp P) inp prio)

/-- `true` when downstream pause blocks switch output `out` on `prio`. -/
def switchPausedDownstream (P : Params) (sw : PFC.St) (out : Nat) (prio : Nat) : Bool :=
  boolAt sw.downstreamPaused (PFC.downIdx (Topology.TwoSwitchLine.sp P) out prio)

/-- Host waits on its attached switch when egress is non-empty but the switch
has paused that host's input priority. -/
def h0WaitsOnSw0 (P : Params) (s : St) (prio : Nat) : Bool :=
  hostEgressWaiting s.h0 prio &&
  switchPausedUpstream P s.sw0 sw0H0 prio

def h1WaitsOnSw1 (P : Params) (s : St) (prio : Nat) : Bool :=
  hostEgressWaiting s.h1 prio &&
  switchPausedUpstream P s.sw1 sw1H1 prio

/-- SW0 waits on SW1 when it cannot forward toward SW1. -/
def sw0WaitsOnSw1 (P : Params) (s : St) (prio : Nat) : Bool :=
  (countByInputLane sw0FromSw1 prio s.sw0.q > 0 ||
   countByInputLane sw0H0 prio s.sw0.q > 0 &&
     (switchPausedDownstream P s.sw0 sw0ToSw1 prio ||
      switchPausedUpstream P s.sw1 sw1FromSw0 prio))

/-- SW1 waits on SW0 symmetrically. -/
def sw1WaitsOnSw0 (P : Params) (s : St) (prio : Nat) : Bool :=
  (countByInputLane sw1FromSw0 prio s.sw1.q > 0 ||
   countByInputLane sw1H1 prio s.sw1.q > 0 &&
     (switchPausedDownstream P s.sw1 sw1ToSw0 prio ||
      switchPausedUpstream P s.sw0 sw0FromSw1 prio))

/-- Build line-topology WFG for a single priority. -/
def lineWfg (P : Params) (s : St) (prio : Nat) : Digraph LineNode :=
  let edges :=
    (if h0WaitsOnSw0 P s prio then [(LineNode.H0, LineNode.SW0)] else []) ++
    (if h1WaitsOnSw1 P s prio then [(LineNode.H1, LineNode.SW1)] else []) ++
    (if sw0WaitsOnSw1 P s prio then [(LineNode.SW0, LineNode.SW1)] else []) ++
    (if sw1WaitsOnSw0 P s prio then [(LineNode.SW1, LineNode.SW0)] else [])
  { vertices := LineNode.all, edges := edges }

/-- `true` when the line WFG has a directed cycle (PFC pause ring). -/
def linePauseCycle (P : Params) (s : St) (prio : Nat) : Bool :=
  (lineWfg P s prio).hasCycle

end TwoSwitchLineDep

end DLFTK.RoCE
