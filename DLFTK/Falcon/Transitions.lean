/-
# DLFTK.Falcon.Transitions — Step relation for the two-peer Falcon model

Progress steps implement the initiator/target pipeline and PDL windows; environment
steps offer ULP load (pull) and store (push) transactions.

## Where deadlock binds

Falcon avoids protocol deadlock via **resource dedication** and **independent
sequence-number / scheduler lanes** (CR Rules #1–#2) plus **RSN ordering** on
ordered connections (UR rules). The `shared*` `ResourceDesign` variants remove
one independence axis so the BFS search can exhibit the corresponding cycle:

| design | violation | typical cycle |
|--------|-----------|---------------|
| `sharedTxRx` | CR #1 | outgoing push data holds the only Rx slot needed for peer's pull request |
| `sharedReqData` | CR #2 | pull request and pull data compete for one PDL window |
| `sharedScheduler` | CR #2 | initiator push data blocks target pull data on the same queue |
-/
import DLFTK.Falcon.Model

namespace DLFTK.Falcon

def removeFirst (p : WirePkt → Bool) : List WirePkt → Option (WirePkt × List WirePkt)
  | [] => none
  | x :: xs =>
    if p x then some (x, xs)
    else (removeFirst p xs).map (fun (y, rest) => (y, x :: rest))

def minRsn : List WirePkt → Option Nat
  | [] => none
  | p :: ps =>
    match minRsn ps with
    | none => some p.rsn
    | some m => some (min p.rsn m)

def isHol (P : Params) (xs : List WirePkt) (pkt : WirePkt) : Bool :=
  if P.ordered then
    match minRsn xs with
    | none => true
    | some m => pkt.rsn == m
  else true

namespace PoolOps

def dedicatedCap (P : Params) (sd : Side) (region : DedicatedPools → Nat) : Bool :=
  region sd.pools < P.poolCap

def sharedPoolCap (P : Params) (sd : Side) : Bool :=
  sd.sharedPool < P.sharedCap

/-- Push / pull inject: ULP request Tx + proactive ULP request Rx. -/
def canAllocUlpReq (P : Params) (sd : Side) : Bool :=
  match P.design with
  | .crCompliant =>
    dedicatedCap P sd (·.txUlpReq) ∧ dedicatedCap P sd (·.rxUlpReq)
  | .sharedTxRx => sharedPoolCap P sd
  | _ =>
    dedicatedCap P sd (·.txUlpReq) ∧ dedicatedCap P sd (·.rxUlpReq)

def allocUlpReq (P : Params) (sd : Side) : Side :=
  match P.design with
  | .crCompliant =>
    { sd with pools := { sd.pools with
        txUlpReq := sd.pools.txUlpReq + 1,
        rxUlpReq := sd.pools.rxUlpReq + 1 } }
  | .sharedTxRx => { sd with sharedPool := sd.sharedPool + 1 }
  | _ =>
    { sd with pools := { sd.pools with
        txUlpReq := sd.pools.txUlpReq + 1,
        rxUlpReq := sd.pools.rxUlpReq + 1 } }

def canAllocUlpData (P : Params) (sd : Side) : Bool :=
  match P.design with
  | .crCompliant => dedicatedCap P sd (·.txUlpData)
  | .sharedTxRx => sharedPoolCap P sd
  | _ => dedicatedCap P sd (·.txUlpData)

def allocUlpData (P : Params) (sd : Side) : Side :=
  match P.design with
  | .crCompliant => { sd with pools := { sd.pools with txUlpData := sd.pools.txUlpData + 1 } }
  | .sharedTxRx => { sd with sharedPool := sd.sharedPool + 1 }
  | _ => { sd with pools := { sd.pools with txUlpData := sd.pools.txUlpData + 1 } }

def canAllocNetReq (P : Params) (sd : Side) : Bool :=
  match P.design with
  | .crCompliant => dedicatedCap P sd (·.rxNetReq)
  | .sharedTxRx => sharedPoolCap P sd
  | _ => dedicatedCap P sd (·.rxNetReq)

def allocNetReq (P : Params) (sd : Side) : Side :=
  match P.design with
  | .crCompliant => { sd with pools := { sd.pools with rxNetReq := sd.pools.rxNetReq + 1 } }
  | .sharedTxRx => { sd with sharedPool := sd.sharedPool + 1 }
  | _ => { sd with pools := { sd.pools with rxNetReq := sd.pools.rxNetReq + 1 } }

/-- Free initiator ULP-request resources after transaction completion. -/
def freeUlpReqTxn (P : Params) (sd : Side) : Side :=
  match P.design with
  | .crCompliant =>
    { sd with pools := { sd.pools with
        txUlpReq := sd.pools.txUlpReq - 1,
        rxUlpReq := sd.pools.rxUlpReq - 1 } }
  | .sharedTxRx => { sd with sharedPool := sd.sharedPool - 1 }
  | _ =>
    { sd with pools := { sd.pools with
        txUlpReq := sd.pools.txUlpReq - 1,
        rxUlpReq := sd.pools.rxUlpReq - 1 } }

/-- Free target ULP-data resources after pull data is fully sent. -/
def freeUlpData (P : Params) (sd : Side) : Side :=
  match P.design with
  | .crCompliant => { sd with pools := { sd.pools with txUlpData := sd.pools.txUlpData - 1 } }
  | .sharedTxRx => { sd with sharedPool := sd.sharedPool - 1 }
  | _ => { sd with pools := { sd.pools with txUlpData := sd.pools.txUlpData - 1 } }

def freeNetReq (P : Params) (sd : Side) : Side :=
  match P.design with
  | .crCompliant => { sd with pools := { sd.pools with rxNetReq := sd.pools.rxNetReq - 1 } }
  | .sharedTxRx => { sd with sharedPool := sd.sharedPool - 1 }
  | _ => { sd with pools := { sd.pools with rxNetReq := sd.pools.rxNetReq - 1 } }

end PoolOps

namespace Step

/-- **inject** (env): ULP offers a push (store) or pull (load) transaction. -/
def inject (P : Params) (n : Peer) (kind : TxnKind) (s : St) : List St :=
  let sd := s.side n
  if canInject P sd ∧ PoolOps.canAllocUlpReq P sd then
    let txn : Txn := { kind, rsn := sd.nextRsn }
    let sd' := PoolOps.allocUlpReq P { sd with
      pending := sd.pending ++ [txn],
      nextRsn := sd.nextRsn + 1 }
    [s.setSide n sd']
  else []

/-- **scheduleTxn** (progress): move a pending transaction to the initiator lane. -/
def scheduleTxn (P : Params) (n : Peer) (s : St) : List St :=
  let sd := s.side n
  match sd.pending with
  | [] => []
  | txn :: rest =>
    let pkt : WirePkt :=
      match txn.kind with
      | .pull  => { kind := .pullReq, rsn := txn.rsn }
      | .push  => { kind := .pushData, rsn := txn.rsn }
    let sd' := match P.design with
      | .sharedScheduler => { sd with pending := rest, unifiedLane := sd.unifiedLane ++ [pkt] }
      | _ => { sd with pending := rest, reqLane := sd.reqLane ++ [pkt] }
    [s.setSide n sd']

/-- Pick the head schedulable initiator packet. -/
def schedHead (P : Params) (sd : Side) : Option (WirePkt × Side) :=
  match P.design with
  | .sharedScheduler =>
    match sd.unifiedLane with
    | [] => none
    | p :: rest => some (p, { sd with unifiedLane := rest })
  | _ =>
    match sd.reqLane with
    | [] => none
    | p :: rest => some (p, { sd with reqLane := rest })

/-- **transmitReq** (progress): send `pullReq` on the request PDL window. -/
def transmitReq (P : Params) (n : Peer) (s : St) : List St :=
  let sd := s.side n
  match schedHead P sd with
  | none => []
  | some (pkt, sd') =>
    if pkt.kind != .pullReq then []
    else if P.design == .sharedReqData then
      if sd'.unifiedFlight.length < P.reqWindow then
        let peer := s.side n.peer
        if PoolOps.canAllocNetReq P peer then
          let sd'' := { sd' with unifiedFlight := sd'.unifiedFlight ++ [pkt] }
          let peer' := PoolOps.allocNetReq P peer
          let peer'' := { peer' with netReq := peer'.netReq ++ [pkt] }
          [(s.setSide n sd'').setSide n.peer peer'']
        else []
      else []
    else if sd'.reqFlight.length < P.reqWindow then
      let peer := s.side n.peer
      if PoolOps.canAllocNetReq P peer then
        let sd'' := { sd' with reqFlight := sd'.reqFlight ++ [pkt] }
        let peer' := PoolOps.allocNetReq P peer
        let peer'' := { peer' with netReq := peer'.netReq ++ [pkt] }
        [(s.setSide n sd'').setSide n.peer peer'']
      else []
    else []

/-- **transmitPush** (progress): send `pushData` on the data PDL window. -/
def transmitPush (P : Params) (n : Peer) (s : St) : List St :=
  let sd := s.side n
  match schedHead P sd with
  | none => []
  | some (pkt, sd') =>
    if pkt.kind != .pushData then []
    else if P.design == .sharedReqData then
      if sd'.unifiedFlight.length < P.dataWindow then
        let peer := s.side n.peer
        if PoolOps.canAllocNetReq P peer then
          let sd'' := { sd' with unifiedFlight := sd'.unifiedFlight ++ [pkt] }
          let peer' := PoolOps.allocNetReq P peer
          let peer'' := { peer' with pushWait := peer'.pushWait ++ [pkt] }
          [(s.setSide n sd'').setSide n.peer peer'']
        else []
      else []
    else if sd'.dataFlight.length < P.dataWindow then
      let peer := s.side n.peer
      if PoolOps.canAllocNetReq P peer then
        let sd'' := { sd' with dataFlight := sd'.dataFlight ++ [pkt] }
        let peer' := PoolOps.allocNetReq P peer
        let peer'' := { peer' with pushWait := peer'.pushWait ++ [pkt] }
        [(s.setSide n sd'').setSide n.peer peer'']
      else []
    else []

/-- **targetPull** (progress): target accepts HoL pull request and queues pull data. -/
def targetPull (P : Params) (n : Peer) (s : St) : List St :=
  let sd := s.side n
  match removeFirst (·.kind == .pullReq) sd.netReq with
  | none => []
  | some (pkt, rest) =>
    if ¬ isHol P sd.netReq pkt then []
    else if ¬ PoolOps.canAllocUlpData P sd then []
    else
      let dataPkt : WirePkt := { kind := .pullData, rsn := pkt.rsn }
      let sd' := PoolOps.allocUlpData P (PoolOps.freeNetReq P { sd with netReq := rest })
      let sd'' := match P.design with
        | .sharedScheduler => { sd' with unifiedLane := sd'.unifiedLane ++ [dataPkt] }
        | _ => { sd' with dataLane := sd'.dataLane ++ [dataPkt] }
      [s.setSide n sd'']

/-- **deliverPush** (progress): target ULP accepts HoL push (UR dependency). -/
def deliverPush (P : Params) (n : Peer) (s : St) : List St :=
  let sd := s.side n
  match removeFirst (·.kind == .pushData) sd.pushWait with
  | none => []
  | some (pkt, rest) =>
    if ¬ isHol P sd.pushWait pkt then []
    else if P.ordered && !sd.netReq.isEmpty then []
    else
      let sd' := PoolOps.freeNetReq P { sd with pushWait := rest }
      let completion : WirePkt := { kind := .pushData, rsn := pkt.rsn }
      let peer := s.side n.peer
      let peer' := { peer with completions := peer.completions ++ [completion] }
      [(s.setSide n sd').setSide n.peer peer']

/-- **transmitData** (progress): target sends pull data on the data window. -/
def transmitData (P : Params) (n : Peer) (s : St) : List St :=
  let sd := s.side n
  let lane := match P.design with
    | .sharedScheduler => sd.unifiedLane
    | _ => sd.dataLane
  match lane with
  | [] => []
  | pkt :: rest =>
    if pkt.kind != .pullData then []
    else
      let sd' := match P.design with
        | .sharedScheduler => { sd with unifiedLane := rest }
        | _ => { sd with dataLane := rest }
      if P.design == .sharedReqData then
        if sd'.unifiedFlight.length < P.dataWindow then
          let peer := s.side n.peer
          let sd'' := { sd' with unifiedFlight := sd'.unifiedFlight ++ [pkt] }
          let peer' := { peer with completions := peer.completions ++ [pkt] }
          [(s.setSide n sd'').setSide n.peer peer']
        else []
      else if sd'.dataFlight.length < P.dataWindow then
        let peer := s.side n.peer
        let sd'' := { sd' with dataFlight := sd'.dataFlight ++ [pkt] }
        let peer' := { peer with completions := peer.completions ++ [pkt] }
        [(s.setSide n sd'').setSide n.peer peer']
      else []

/-- **complete** (progress): deliver initiator completion to ULP in RSN order. -/
def complete (P : Params) (n : Peer) (s : St) : List St :=
  let sd := s.side n
  match sd.completions with
  | [] => []
  | pkt :: rest =>
    if P.ordered && pkt.rsn != sd.brsn then []
    else
      let sd' := PoolOps.freeUlpReqTxn P { sd with
        completions := rest,
        brsn := sd.brsn + 1 }
      [s.setSide n sd']

/-- **ackReq** (progress): request-window ACK frees a PDL slot after peer processing. -/
def ackReq (P : Params) (n : Peer) (s : St) : List St :=
  if P.design == .sharedReqData then [] else
  let sd := s.side n
  let peer := s.side n.peer
  match sd.reqFlight with
  | [] => []
  | pkt :: rest =>
    let processed : Bool := match pkt.kind with
      | .pullReq => ¬ peer.netReq.any (fun q => q.rsn == pkt.rsn)
      | _ => true
    if processed then [s.setSide n { sd with reqFlight := rest }] else []

/-- **ackData** (progress): data-window ACK frees a PDL slot and target data pool. -/
def ackData (P : Params) (n : Peer) (s : St) : List St :=
  let sd := s.side n
  let peer := s.side n.peer
  if P.design == .sharedReqData then
    match sd.unifiedFlight with
    | [] => []
    | pkt :: rest =>
      let done : Bool := match pkt.kind with
        | .pullReq => sd.completions.any (fun q => q.kind == .pullData && q.rsn == pkt.rsn)
        | .pushData => sd.completions.any (fun q => q.kind == .pushData && q.rsn == pkt.rsn)
        | _ => true
      if done then [s.setSide n { sd with unifiedFlight := rest }] else []
  else
    match sd.dataFlight with
    | [] => []
    | pkt :: rest =>
      let processed : Bool := match pkt.kind with
        | .pushData => ¬ peer.pushWait.any (fun q => q.rsn == pkt.rsn)
        | _ => true
      if processed then
        let sd' := { sd with dataFlight := rest }
        let sd'' := if pkt.kind == .pullData then PoolOps.freeUlpData P sd' else sd'
        [s.setSide n sd'']
      else []

def perPeer (P : Params) (n : Peer) (s : St) : List St :=
  scheduleTxn P n s
  ++ transmitReq P n s
  ++ transmitPush P n s
  ++ targetPull P n s
  ++ deliverPush P n s
  ++ transmitData P n s
  ++ complete P n s
  ++ ackReq P n s
  ++ ackData P n s

def progress (P : Params) (s : St) : List St :=
  perPeer P Peer.A s ++ perPeer P Peer.B s

def env (P : Params) (s : St) : List St :=
  let peers := [Peer.A, Peer.B]
  let kinds := [TxnKind.push, TxnKind.pull]
  peers.flatMap (fun n => kinds.flatMap (fun k => inject P n k s))

end Step

def initSt : St := {}

def system (P : Params) : DLFTK.System St where
  init := [initSt]
  progress := Step.progress P
  env := Step.env P

def hasWork (s : St) : Bool :=
  let busy (sd : Side) : Bool :=
    ¬ (sd.pending.isEmpty ∧ sd.reqLane.isEmpty ∧ sd.dataLane.isEmpty
       ∧ sd.unifiedLane.isEmpty ∧ sd.reqFlight.isEmpty ∧ sd.dataFlight.isEmpty
       ∧ sd.unifiedFlight.isEmpty ∧ sd.netReq.isEmpty ∧ sd.pushWait.isEmpty
       ∧ sd.completions.isEmpty)
  busy s.a || busy s.b

end DLFTK.Falcon
