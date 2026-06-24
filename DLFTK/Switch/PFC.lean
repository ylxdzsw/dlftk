/-
# DLFTK.Switch.PFC

Priority Flow Control model.

PFC is threshold backpressure, not exact per-packet credit. The switch pauses an
upstream input/priority when the corresponding buffered occupancy reaches a
pause threshold, and resumes it when occupancy falls to a resume threshold.

Downstream pause state is modeled as environment-controlled because it is sent
by the next hop.
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.Switch.Types

namespace DLFTK.Switch.PFC

open DLFTK.Switch

structure Params where
  nIn : Nat
  nOut : Nat
  nPrio : Nat
  /-- Buffer capacity per `(input, priority)`. -/
  queueCap : Nat
  pauseThreshold : Nat
  resumeThreshold : Nat
deriving DecidableEq, Repr, BEq, Hashable

structure St where
  q : List RoutedPkt := []
  /-- PFC state this switch has asserted toward upstream links. -/
  upstreamPaused : List Bool := []
  /-- PFC state asserted by downstream links toward this switch. -/
  downstreamPaused : List Bool := []
deriving DecidableEq, Repr, BEq, Hashable

def upIdx (P : Params) (input : InPort) (prio : Priority) : Nat := idx2 P.nPrio input prio
def downIdx (P : Params) (out : OutPort) (prio : Priority) : Nat := idx2 P.nPrio out prio

namespace Step

variable (P : Params)

/-- Environment arrival is allowed only while the upstream priority is unpaused. -/
def inject (input : InPort) (out : OutPort) (prio : Priority) (s : St) : List St :=
  let ui := upIdx P input prio
  if !boolAt s.upstreamPaused ui && countByInputLane input prio s.q < P.queueCap then
    let p : RoutedPkt := { input := input, out := out, lane := prio }
    [{ s with q := s.q ++ [p] }]
  else []

/-- Data transmission is blocked while the next hop has paused this priority. -/
def transmit (input : InPort) (out : OutPort) (prio : Priority) (s : St) : List St :=
  let di := downIdx P out prio
  match headVOQ input out prio s.q with
  | none => []
  | some (_, rest) =>
      if !boolAt s.downstreamPaused di then
        [{ s with q := rest }]
      else []

/-- Assert pause upstream once buffered occupancy reaches the pause threshold. -/
def pauseUpstream (input : InPort) (prio : Priority) (s : St) : List St :=
  let ui := upIdx P input prio
  if !boolAt s.upstreamPaused ui && P.pauseThreshold <= countByInputLane input prio s.q then
    [{ s with upstreamPaused := setBool s.upstreamPaused ui true }]
  else []

/-- Resume upstream once occupancy has drained to the resume threshold. -/
def resumeUpstream (input : InPort) (prio : Priority) (s : St) : List St :=
  let ui := upIdx P input prio
  if boolAt s.upstreamPaused ui && countByInputLane input prio s.q <= P.resumeThreshold then
    [{ s with upstreamPaused := setBool s.upstreamPaused ui false }]
  else []

def setDownstreamPause (out : OutPort) (prio : Priority) (paused : Bool) (s : St) : List St :=
  let di := downIdx P out prio
  if boolAt s.downstreamPaused di == paused then []
  else [{ s with downstreamPaused := setBool s.downstreamPaused di paused }]

def progress (s : St) : List St :=
  let inputs := List.range P.nIn
  let outputs := List.range P.nOut
  let prios := List.range P.nPrio
  let send := inputs.flatMap (fun i =>
    outputs.flatMap (fun o =>
      prios.flatMap (fun p => transmit P i o p s)))
  let pause := inputs.flatMap (fun i => prios.flatMap (fun p => pauseUpstream P i p s))
  let resume := inputs.flatMap (fun i => prios.flatMap (fun p => resumeUpstream P i p s))
  send ++ pause ++ resume

def env (s : St) : List St :=
  let inputs := List.range P.nIn
  let outputs := List.range P.nOut
  let prios := List.range P.nPrio
  let arrivals := inputs.flatMap (fun i =>
    outputs.flatMap (fun o =>
      prios.flatMap (fun p => inject P i o p s)))
  let downstream := outputs.flatMap (fun o =>
    prios.flatMap (fun p => setDownstreamPause P o p true s ++ setDownstreamPause P o p false s))
  arrivals ++ downstream

end Step

def initSt (P : Params) : St :=
  { upstreamPaused := initBool2 P.nIn P.nPrio,
    downstreamPaused := initBool2 P.nOut P.nPrio }

def system (P : Params) : DLFTK.System St where
  init := [initSt P]
  progress := Step.progress P
  env := Step.env P

def hasWork (s : St) : Bool := hasRoutedWork s.q

end DLFTK.Switch.PFC
