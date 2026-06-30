/-
# DLFTK.RoCE.Types — RoCE / RDMA-over-Ethernet vocabulary

We model the **deadlock-relevant slice** of RoCE:

* **PFC priority** — lossless traffic class (DSCP / VLAN PFC class). Pause is
  asserted per `(link, priority)`, so congestion on one priority can block all
  traffic in that class (head-of-line blocking within the lossless class).
* **RDMA message** — a simplified reliable datagram: one packet per RDMA
  operation, delivered at the destination NIC and completed by a local
  `deliver` step (completion queue drain).

Full RoCE (QP state machines, go-back-N, ECN/CNP) is intentionally omitted;
those paths do not change the **PFC pause-cycle** failure mode this module
targets.
-/

namespace DLFTK.RoCE

/-- Host / NIC endpoint identifier. -/
abbrev HostId := Nat

/-- PFC-enabled lossless priority (traffic class). -/
abbrev Prio := Nat

/-- A host-queued RDMA datagram awaiting transmission or delivery. -/
structure Pkt where
  dest : HostId
  prio : Prio
deriving DecidableEq, Repr, BEq, Hashable

/-- A packet received at a host, retaining its source for dependency analysis. -/
structure IngressPkt where
  src : HostId
  prio : Prio
deriving DecidableEq, Repr, BEq, Hashable

end DLFTK.RoCE
