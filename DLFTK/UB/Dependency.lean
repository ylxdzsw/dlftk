/-
# DLFTK.UB.Dependency — Message-dependent wait-for graphs

Extracts a **peer wait-for graph** from a UB link state. The graph has one
vertex per node (`A`, `B`); an edge `n → peer` means node `n` is stalled on
progress because the peer holds a resource `n` needs.

This is the mathematical counterpart to brute-force BFS: instead of enumerating
all buffer configurations, we read off the **dependency structure** that
characterises message-dependent deadlock.

## Lane partition (separate VL)

When `vlmap .req ≠ vlmap .resp`, request and response packets never compete
for the same per-lane buffer pool. Response production is blocked only by the
**response** egress lane, not by congestion on the request lane — breaking the
req→resp cycle that shared-VL designs admit.
-/
import DLFTK.Graph
import DLFTK.UB.Transitions

namespace DLFTK.UB

/-- Request and response use disjoint virtual lanes. -/
def lanesPartitioned (P : Params) : Bool :=
  P.vlmap .req ≠ P.vlmap .resp

/-- Head packet on the request VL ingress, if any. -/
def reqIngressHead (P : Params) (sd : Side) : Option Pkt :=
  (laneOf (P.vlmap .req) sd.ingress).head?

/-- `true` when `sd` has a store request waiting at the head of the request
ingress lane. -/
def hasReqHead (P : Params) (sd : Side) : Bool :=
  match reqIngressHead P sd with
  | some pkt => pkt.cls == .req
  | none => false

/-- `true` when response production is blocked because the response egress
lane is full. -/
def respEgressFull (P : Params) (sd : Side) : Bool :=
  laneLen (P.vlmap .resp) sd.egress ≥ P.cap

/-- `true` when the request egress lane head cannot transmit: no credit, send
window full, or peer ingress on that VL is full. -/
def reqEgressStuck (P : Params) (n : Node) (s : St) : Bool :=
  let self := s.side n
  let peer := s.side n.peer
  let v := P.vlmap .req
  match laneHead v self.egress with
  | none => false
  | some _ =>
    creditAt self.credit v == 0
      || self.replay.length ≥ P.window
      || laneLen v peer.ingress ≥ P.cap

/-- Node `n` waits for its peer when it cannot process a waiting request
because the response egress is full, and the request egress head is stuck
waiting on the peer (credit / ingress back-pressure). This is the local
pattern behind the classic shared-VL req→resp cycle. -/
def waitsForPeer (P : Params) (s : St) (n : Node) : Bool :=
  let self := s.side n
  hasReqHead P self
    && respEgressFull P self
    && reqEgressStuck P n s

/-- Build the 2-node peer WFG from wait flags. -/
def twoNodeWfg (waitsAB waitsBA : Bool) : Digraph Node :=
  { vertices := [Node.A, Node.B]
    edges :=
      (if waitsAB then [(Node.A, Node.B)] else [])
      ++ (if waitsBA then [(Node.B, Node.A)] else []) }

/-- Peer wait-for digraph for state `s`. -/
def wfg (P : Params) (s : St) : Digraph Node :=
  twoNodeWfg (waitsForPeer P s .A) (waitsForPeer P s .B)

/-- A 2-node message-dependent deadlock exhibits mutual waiting. -/
def mutualPeerWait (P : Params) (s : St) : Bool :=
  waitsForPeer P s .A && waitsForPeer P s .B

/-- Under lane partition, response production depends only on the response
egress lane (not the request lane). Computable formulation used in claims. -/
def processBlockedOnReq (P : Params) (n : Node) (s : St) : Bool :=
  hasReqHead P (s.side n)
    && (Step.processVL P n (P.vlmap .req) s).isEmpty

/-- When lanes are partitioned, processing is blocked iff the response egress
lane is full (checked pointwise by `native_decide` in studies). -/
def processBlocked_iff_respFull (P : Params) (n : Node) (s : St) : Bool :=
  processBlockedOnReq P n s = (hasReqHead P (s.side n) && respEgressFull P (s.side n))

end DLFTK.UB
