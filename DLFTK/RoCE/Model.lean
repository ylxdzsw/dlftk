/-
# DLFTK.RoCE.Model — Host NIC queues for RoCE

Each host maintains per-priority **egress** (send queue) and **ingress**
(receive / completion queue) FIFOs. RoCE relies on the fabric — modeled with
`DLFTK.Switch.PFC` — for lossless delivery; the host blocks transmission on a
priority when the attached switch has asserted **PFC pause** toward that host on
that priority.

## Key modeling assumptions (documented on purpose)

* **Losslessness via PFC**, not per-packet link credits (contrast `DLFTK.UB`).
* **Threshold pause/resume** on switches follows `DLFTK.Switch.PFC`.
* **RDMA completion** is a single `deliver` progress step that drains ingress;
  no go-back-N retransmit or ECN/CNP reaction (planned extensions).
* **One packet per RDMA operation** — enough to expose buffer-occupancy cycles.
-/
import DLFTK.RoCE.Types
import DLFTK.Core
import DLFTK.Analysis

namespace DLFTK.RoCE

/-- Per-host queue capacities. -/
structure HostCaps where
  nPrio : Nat
  egressCap : Nat
  ingressCap : Nat
deriving DecidableEq, Repr, BEq, Hashable

/-- Per-host NIC state: one egress and one ingress FIFO per PFC priority. -/
structure HostSide where
  egress : List (List Pkt) := []
  ingress : List (List IngressPkt) := []
deriving DecidableEq, Repr, BEq, Hashable

def initHost (C : HostCaps) : HostSide :=
  { egress := List.replicate C.nPrio [],
    ingress := List.replicate C.nPrio [] }

def egressLen (hs : HostSide) (prio : Prio) : Nat :=
  ((hs.egress[prio]?).getD []).length

def ingressLen (hs : HostSide) (prio : Prio) : Nat :=
  ((hs.ingress[prio]?).getD []).length

def pushEgress (hs : HostSide) (prio : Prio) (pkt : Pkt) : HostSide :=
  let q := (hs.egress[prio]?).getD []
  let egress := hs.egress ++ List.replicate (prio + 1 - hs.egress.length) []
  { hs with egress := egress.set prio (q ++ [pkt]) }

def popEgress (hs : HostSide) (prio : Prio) : Option (Pkt × HostSide) :=
  match hs.egress[prio]? with
  | none | some [] => none
  | some (x :: xs) =>
      let egress := hs.egress ++ List.replicate (prio + 1 - hs.egress.length) []
      some (x, { hs with egress := egress.set prio xs })

def pushIngress (hs : HostSide) (prio : Prio) (pkt : IngressPkt) : HostSide :=
  let q := (hs.ingress[prio]?).getD []
  let ingress := hs.ingress ++ List.replicate (prio + 1 - hs.ingress.length) []
  { hs with ingress := ingress.set prio (q ++ [pkt]) }

def popIngress (hs : HostSide) (prio : Prio) : Option (IngressPkt × HostSide) :=
  match hs.ingress[prio]? with
  | none | some [] => none
  | some (x :: xs) =>
      let ingress := hs.ingress ++ List.replicate (prio + 1 - hs.ingress.length) []
      some (x, { hs with ingress := ingress.set prio xs })

def hasHostWork (hs : HostSide) : Bool :=
  hs.egress.any (¬ ·.isEmpty) || hs.ingress.any (¬ ·.isEmpty)

end DLFTK.RoCE
