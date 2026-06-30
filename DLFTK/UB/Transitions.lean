/-
# DLFTK.UB.Transitions — Step relation for the two-node UB model

We give `St` a `DLFTK.System` structure. Steps are split:

* **progress**: `transmit`, `process`, `consume`, `linkAck`, `retransmit`
* **env**:      `inject` (offered store load)

## Where the deadlock binds

The message-dependent deadlock is created by the interaction of three things:

* **credit** (you cannot transmit on VL `v` without a free buffer slot at the
  peer's ingress for `v`), and
* **bounded egress** (you cannot *produce* a response if the egress lane it must
  go to is full), and
* **VL sharing** (if `req` and `resp` share a lane, a full egress lane of
  requests blocks the production of the response that would drain the peer).

With requests and responses on **separate** lanes, the response lane is never
blocked by the request lane, responses always drain, and the dependency order
`resp ≺ req` is acyclic — no deadlock. The search machinery makes this concrete.
-/
import DLFTK.UB.Model

namespace DLFTK.UB

/-- Remove the first element of `xs` satisfying `p`, returning it and the rest
(order preserved). `none` if no element matches. -/
def removeFirst (p : Pkt → Bool) : List Pkt → Option (Pkt × List Pkt)
  | [] => none
  | x :: xs =>
    if p x then some (x, xs)
    else (removeFirst p xs).map (fun (y, rest) => (y, x :: rest))

/-- FIFO head of lane `v` in `q` (first packet with that VL), with the rest. -/
def laneHead (v : VL) (q : List Pkt) : Option (Pkt × List Pkt) :=
  removeFirst (fun p => p.vl == v) q

/-- Get/replace a node's side. -/
def St.side (s : St) : Node → Side
  | .A => s.a
  | .B => s.b

def St.setSide (s : St) : Node → Side → St
  | .A, sd => { s with a := sd }
  | .B, sd => { s with b := sd }

namespace Step

variable (P : Params)

/-- **inject** (env): offer a new store request into the local egress, on the
request VL, if that egress lane has room. -/
def inject (n : Node) (s : St) : List St :=
  let self := s.side n
  let v := P.vlmap .req
  if laneLen v self.egress < P.cap then
    let pkt : Pkt := { cls := .req, vl := v }
    let self' := { self with egress := self.egress ++ [pkt] }
    [s.setSide n self']
  else []

/-- **transmit** (progress) on VL `v`: move lane-`v` egress head to the peer's
ingress. Requires a credit on `v` and an open send-window slot. Consumes a
credit and records the packet in the replay buffer (for link-level retry). -/
def transmitVL (n : Node) (v : VL) (s : St) : List St :=
  let self := s.side n
  let peer := s.side n.peer
  match laneHead v self.egress with
  | none => []
  | some (pkt, rest) =>
    if creditAt self.credit v > 0 && self.replay.length < P.window
        && laneLen v peer.ingress < P.cap then
      let self' := { self with
        egress := rest,
        credit := setCredit self.credit v (creditAt self.credit v - 1),
        replay := self.replay ++ [pkt] }
      let peer' := { peer with ingress := peer.ingress ++ [pkt] }
      [(s.setSide n self').setSide n.peer peer']
    else []

/-- **process** (progress) on VL `v`: take a `req` at lane-`v` ingress head,
consume it (returning a credit to the peer for `v`), and *produce* a `resp`
into the egress lane assigned to responses — requires room on that egress lane.
This is where shared-VL back-pressure can block response production. -/
def processVL (n : Node) (v : VL) (s : St) : List St :=
  let self := s.side n
  let peer := s.side n.peer
  match laneHead v self.ingress with
  | none => []
  | some (pkt, rest) =>
    if pkt.cls == .req then
      let rv := P.vlmap .resp
      if laneLen rv self.egress < P.cap then
        let resp : Pkt := { cls := .resp, vl := rv }
        let self' := { self with
          ingress := rest,
          egress := self.egress ++ [resp] }
        -- returning a credit to the peer (we freed an ingress slot on VL `v`)
        let peer' := { peer with
          credit := setCredit peer.credit v (creditAt peer.credit v + 1) }
        [(s.setSide n self').setSide n.peer peer']
      else []
    else []

/-- **consume** (progress) on VL `v`: a `resp` at lane-`v` ingress head sinks
(the store completion is delivered), freeing the ingress slot and returning a
credit to the peer. Responses produce no further fabric packet — this is the
*consumption assumption* that makes separated lanes deadlock-free. -/
def consumeVL (n : Node) (v : VL) (s : St) : List St :=
  let self := s.side n
  let peer := s.side n.peer
  match laneHead v self.ingress with
  | none => []
  | some (pkt, rest) =>
    if pkt.cls == .resp then
      let self' := { self with ingress := rest }
      let peer' := { peer with
        credit := setCredit peer.credit v (creditAt peer.credit v + 1) }
      [(s.setSide n self').setSide n.peer peer']
    else []

/-- **linkAck** (progress): the oldest in-flight packet is acknowledged at the
link layer (reliable delivery), freeing a send-window slot. Modeled as a
non-blocking side-band effect (see Model.lean assumption). -/
def linkAck (n : Node) (s : St) : List St :=
  let self := s.side n
  match self.replay with
  | [] => []
  | _ :: rest => [s.setSide n { self with replay := rest }]

/-- **retransmit** (progress): resend the oldest replayed packet on VL `v`. -/
def retransmitVL (n : Node) (v : VL) (s : St) : List St :=
  let self := s.side n
  let peer := s.side n.peer
  match self.replay with
  | [] => []
  | pkt :: _ =>
    if pkt.vl == v && creditAt self.credit v > 0 && laneLen v peer.ingress < P.cap then
      let self' := { self with
        credit := setCredit self.credit v (creditAt self.credit v - 1) }
      let peer' := { peer with ingress := peer.ingress ++ [pkt] }
      [(s.setSide n self').setSide n.peer peer']
    else []

/-- **dropInflight** (env): L2 loss of the oldest unACKed packet. -/
def dropInflight (n : Node) (s : St) : List St :=
  let self := s.side n
  match self.replay with
  | [] => []
  | _ :: rest => [s.setSide n { self with replay := rest }]

/-- All progress successors of `s` for a parameter set `P`. -/
def progress (s : St) : List St :=
  let nodes := [Node.A, Node.B]
  let vls := (List.range P.nVL)
  let perNode (n : Node) : List St :=
    (vls.flatMap (fun v => transmitVL P n v s))
    ++ (vls.flatMap (fun v => processVL P n v s))
    ++ (vls.flatMap (fun v => consumeVL n v s))
    ++ (vls.flatMap (fun v => retransmitVL P n v s))
    ++ linkAck n s
  nodes.flatMap perNode

/-- All environment successors of `s` (offered load + L2 loss). -/
def env (s : St) : List St :=
  [Node.A, Node.B].flatMap (fun n => inject P n s)
    ++ [Node.A, Node.B].flatMap (fun n => dropInflight n s)

end Step

/-- Initial state: empty buffers, full credits on every lane, seq 0. -/
def initSt (P : Params) : St :=
  let sd : Side := { credit := initCredit P }
  { a := sd, b := sd }

/-- The UB two-node link as a `DLFTK.System`. -/
def system (P : Params) : DLFTK.System St where
  init := [initSt P]
  progress := Step.progress P
  env := Step.env P

/-- A state has *work* if any buffer (ingress/egress/replay) is non-empty. -/
def hasWork (s : St) : Bool :=
  ¬ (s.a.ingress.isEmpty ∧ s.a.egress.isEmpty ∧ s.a.replay.isEmpty
     ∧ s.b.ingress.isEmpty ∧ s.b.egress.isEmpty ∧ s.b.replay.isEmpty)

end DLFTK.UB
