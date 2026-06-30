/-
# DLFTK.RoCE.Topology.TwoSwitchLine — two hosts, two PFC switches in series

Minimal **multi-hop** RoCE fabric for PFC pause propagation:

  H0 ===== SW0 ===== SW1 ===== H1
         (in0)  (out0/in0)  (in1)

Port wiring:

| Switch | Input port | Source |
|--------|------------|--------|
| SW0    | 0          | H0     |
| SW0    | 1          | SW1    |
| SW1    | 0          | SW0    |
| SW1    | 1          | H1     |

Cross traffic H0→H1 traverses SW0→SW1; H1→H0 traverses SW1→SW0. When buffers
fill, **PFC pause** can propagate around the ring and stall both directions —
the classic datacenter **cyclic buffer dependency** pattern.
-/
import DLFTK.Core
import DLFTK.Analysis
import DLFTK.RoCE.Host
import DLFTK.RoCE.Model
import DLFTK.RoCE.Types
import DLFTK.Switch.PFC
import DLFTK.Switch.Types

namespace DLFTK.RoCE.Topology.TwoSwitchLine

open DLFTK.Switch
open DLFTK.Switch.PFC
open DLFTK.RoCE

namespace Port

def sw0H0 : InPort := 0
def sw0FromSw1 : InPort := 1
def sw0ToSw1 : OutPort := 0
def sw0ToH0 : OutPort := 1

def sw1FromSw0 : InPort := 0
def sw1H1 : InPort := 1
def sw1ToH1 : OutPort := 0
def sw1ToSw0 : OutPort := 1

end Port

open Port

structure Params where
  nPrio : Nat
  queueCap : Nat
  pauseThreshold : Nat
  resumeThreshold : Nat
  hostEgressCap : Nat
  hostIngressCap : Nat
deriving DecidableEq, Repr, BEq, Hashable

def hostCaps (P : Params) : HostCaps :=
  { nPrio := P.nPrio, egressCap := P.hostEgressCap, ingressCap := P.hostIngressCap }

def switchParams (P : Params) : PFC.Params :=
  { nIn := 2, nOut := 2, nPrio := P.nPrio,
    queueCap := P.queueCap, pauseThreshold := P.pauseThreshold,
    resumeThreshold := P.resumeThreshold }

def attachH0 (P : Params) : Attach :=
  { caps := hostCaps P, swIn := sw0H0, swOut := sw0ToH0, linkUp := true }

def attachH1 (P : Params) : Attach :=
  { caps := hostCaps P, swIn := sw1H1, swOut := sw1ToH1, linkUp := true }

structure St where
  h0 : HostSide := {}
  h1 : HostSide := {}
  sw0 : PFC.St := {}
  sw1 : PFC.St := {}
deriving DecidableEq, Repr, BEq, Hashable

def initLineSt (P : Params) : St :=
  { h0 := initHost (hostCaps P), h1 := initHost (hostCaps P),
    sw0 := PFC.initSt (switchParams P), sw1 := PFC.initSt (switchParams P) }

def sp (P : Params) : PFC.Params := switchParams P

/-- Inter-switch transmit: move VOQ head from `sw` output `outPort` into peer
switch input `inPort`, remapping to `peerOut` on the peer switch. -/
def interSwitchTx (P : Params) (sw peer : PFC.St) (input out prio : Nat)
    (inPort : InPort) (peerOut : OutPort) : List (PFC.St × PFC.St) :=
  let di := downIdx (sp P) out prio
  if boolAt sw.downstreamPaused di then []
  else
    match headVOQ input out prio sw.q with
    | none => []
    | some (_, rest) =>
        let ui := upIdx (sp P) inPort prio
        if boolAt peer.upstreamPaused ui then []
        else if countByInputLane inPort prio peer.q < P.queueCap then
          let routed : RoutedPkt := { input := inPort, out := peerOut, lane := prio }
          let sw' := { sw with q := rest }
          let peer' := { peer with q := peer.q ++ [routed] }
          [(sw', peer')]
        else []

namespace Step

def h0Deliver (P : Params) (s : St) : List St :=
  (List.range P.nPrio).flatMap (fun prio =>
    hostDeliver s.h0 prio |>.map fun h0' => { s with h0 := h0' })

def h1Deliver (P : Params) (s : St) : List St :=
  (List.range P.nPrio).flatMap (fun prio =>
    hostDeliver s.h1 prio |>.map fun h1' => { s with h1 := h1' })

/-- SW0 → H0 delivery (packets arriving from SW1 on the inter-switch link). -/
def deliverSw0ToH0 (P : Params) (prio : Nat) (s : St) : List St :=
  if prio < P.nPrio && ingressLen s.h0 prio < P.hostIngressCap then
    match headVOQ sw0FromSw1 sw0ToH0 prio s.sw0.q with
    | none => []
    | some (pkt, rest) =>
        let h0' := pushIngress s.h0 prio { src := pkt.input, prio := pkt.lane }
        let sw0' := { s.sw0 with q := rest }
        [{ s with h0 := h0', sw0 := sw0' }]
  else []

/-- SW1 → H1 delivery (packets arriving from SW0 on the inter-switch link). -/
def deliverSw1ToH1 (P : Params) (prio : Nat) (s : St) : List St :=
  if prio < P.nPrio && ingressLen s.h1 prio < P.hostIngressCap then
    match headVOQ sw1FromSw0 sw1ToH1 prio s.sw1.q with
    | none => []
    | some (pkt, rest) =>
        let h1' := pushIngress s.h1 prio { src := pkt.input, prio := pkt.lane }
        let sw1' := { s.sw1 with q := rest }
        [{ s with h1 := h1', sw1 := sw1' }]
  else []

def forwardSw0ToSw1 (P : Params) (prio : Nat) (s : St) : List St :=
  interSwitchTx P s.sw0 s.sw1 sw0H0 sw0ToSw1 prio sw1FromSw0 sw1ToH1 |>.map
    fun (sw0', sw1') => { s with sw0 := sw0', sw1 := sw1' }

def forwardSw1ToSw0 (P : Params) (prio : Nat) (s : St) : List St :=
  interSwitchTx P s.sw1 s.sw0 sw1H1 sw1ToSw0 prio sw0FromSw1 sw0ToH0 |>.map
    fun (sw1', sw0') => { s with sw1 := sw1', sw0 := sw0' }

/-- H0 → SW0 → SW1 → H1. -/
def pathH0ToH1 (P : Params) (prio : Nat) (s : St) : List St :=
  if prio >= P.nPrio then []
  else
    match popEgress s.h0 prio with
    | none => []
    | some (_, h0') =>
        let ui0 := upIdx (sp P) sw0H0 prio
        if boolAt s.sw0.upstreamPaused ui0 then []
        else if countByInputLane sw0H0 prio s.sw0.q >= P.queueCap then []
        else
          let routed0 : RoutedPkt := { input := sw0H0, out := sw0ToSw1, lane := prio }
          let sw0' := { s.sw0 with q := s.sw0.q ++ [routed0] }
          let s' := { s with h0 := h0', sw0 := sw0' }
          forwardSw0ToSw1 P prio s' ++ deliverSw1ToH1 P prio s'

/-- H1 → SW1 → SW0 → H0. -/
def pathH1ToH0 (P : Params) (prio : Nat) (s : St) : List St :=
  if prio >= P.nPrio then []
  else
    match popEgress s.h1 prio with
    | none => []
    | some (_, h1') =>
        let ui1 := upIdx (sp P) sw1H1 prio
        if boolAt s.sw1.upstreamPaused ui1 then []
        else if countByInputLane sw1H1 prio s.sw1.q >= P.queueCap then []
        else
          let routed1 : RoutedPkt := { input := sw1H1, out := sw1ToSw0, lane := prio }
          let sw1' := { s.sw1 with q := s.sw1.q ++ [routed1] }
          let s' := { s with h1 := h1', sw1 := sw1' }
          forwardSw1ToSw0 P prio s' ++ deliverSw0ToH0 P prio s'

def switchPfc (P : Params) (s : St) : List St :=
  let prios := List.range P.nPrio
  let inputs0 := List.range 2
  let inputs1 := List.range 2
  let pause0 := inputs0.flatMap (fun i => prios.flatMap (fun p =>
    PFC.Step.pauseUpstream (sp P) i p s.sw0))
  let resume0 := inputs0.flatMap (fun i => prios.flatMap (fun p =>
    PFC.Step.resumeUpstream (sp P) i p s.sw0))
  let pause1 := inputs1.flatMap (fun i => prios.flatMap (fun p =>
    PFC.Step.pauseUpstream (sp P) i p s.sw1))
  let resume1 := inputs1.flatMap (fun i => prios.flatMap (fun p =>
    PFC.Step.resumeUpstream (sp P) i p s.sw1))
  (pause0 ++ resume0).map (fun sw0' => { s with sw0 := sw0' }) ++
  (pause1 ++ resume1).map (fun sw1' => { s with sw1 := sw1' })

def progress (P : Params) (s : St) : List St :=
  let prios := List.range P.nPrio
  h0Deliver P s ++ h1Deliver P s ++
  prios.flatMap (fun p => deliverSw0ToH0 P p s ++ deliverSw1ToH1 P p s) ++
  prios.flatMap (fun p => forwardSw0ToSw1 P p s ++ forwardSw1ToSw0 P p s) ++
  prios.flatMap (fun p => pathH0ToH1 P p s ++ pathH1ToH0 P p s) ++
  switchPfc P s

def h0Inject (P : Params) (prio : Nat) (s : St) : List St :=
  HostStep.inject (attachH0 P) s.h0 prio 1 |>.map fun h0' => { s with h0 := h0' }

def h1Inject (P : Params) (prio : Nat) (s : St) : List St :=
  HostStep.inject (attachH1 P) s.h1 prio 0 |>.map fun h1' => { s with h1 := h1' }

def env (P : Params) (s : St) : List St :=
  (List.range P.nPrio).flatMap (fun p => h0Inject P p s ++ h1Inject P p s)

def crossTrafficEnv (P : Params) (s : St) : List St :=
  h0Inject P 0 s ++ h1Inject P 0 s

end Step

def system (P : Params) : DLFTK.System St where
  init := [initLineSt P]
  progress := Step.progress P
  env := Step.env P

def crossTrafficSys (P : Params) : DLFTK.System St where
  init := [initLineSt P]
  progress := Step.progress P
  env := Step.crossTrafficEnv P

def hasWork (s : St) : Bool :=
  hasHostWork s.h0 || hasHostWork s.h1 ||
  hasRoutedWork s.sw0.q || hasRoutedWork s.sw1.q

end DLFTK.RoCE.Topology.TwoSwitchLine
