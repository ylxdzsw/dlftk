# Research journal: Falcon deadlock avoidance

**dlftk pin:** v0.2.0 · **Claims:** `TwoPeerLoadStore.lean`

## Question

Do Falcon's CR deadlock rules (resource dedication, separate request/data
sequence-number spaces, separate initiator/target scheduler lanes) prevent
message-dependent deadlock under mixed load (pull) and store (push) traffic?

## Model

`DLFTK.Falcon.Transitions` — two peers, one bidirectional connection:

1. Push and pull transactions with RSN assignment and ordered HoL processing.
2. Dedicated ULP-request / ULP-data / network-request pools (or shared).
3. Separate request vs data PDL windows (or merged `sharedReqData`).
4. Separate initiator (`pullReq`+`pushData`) vs target (`pullData`) scheduler
   lanes (or merged `sharedScheduler`).

**Documented assumptions:** per-packet pool slots; PDL ACKs on a side-band
(`ackReq`/`ackData`); for `sharedReqData` the unified window slot is held until
the full transaction completes.

Parameters: `poolCap = 1`, `reqWindow = dataWindow = 1`.

## Workloads

* **Cross push/pull** — each peer may inject stores and loads at each other.
* **Pull-only** — both peers stream loads (isolates request/data window sharing).

## Results

| design | workload | reachable | saturated | result |
|--------|----------|-----------|-----------|--------|
| `crCompliant` | cross | ≥ 4.6M states explored | **deadlock-free** |
| `sharedTxRx` | cross | ≥ 2.3M states explored | **deadlock** |
| `sharedReqData` | pull-only | 238 (saturated) | **deadlock** |

### `sharedTxRx` witness

Both peers hold scheduled packets but `sharedPool = sharedCap`; neither can
allocate peer receive slots for transmission — classic CR #1 resource cycle.

### `sharedReqData` witness

Each peer has a pull request occupying the unified PDL window while the
matching pull data response waits in `dataLane`; neither can release the window
until the peer completes the round trip.

## Pull ACK ablation (`PullAckStudy.lean`)

**Question:** Is pull's early request ACK necessary? What if pull were one
request and one response with no ACK-for-request and no ACK-for-response?

| variant | workload | result |
|---------|----------|--------|
| `crCompliant` + both ACKs | pull-only | ≥1.3M explored, no deadlock found |
| `crCompliant`, no `ackReq` | pull-only | **deadlock** (saturated) — `reqFlight` never drains |
| `crCompliant`, no `ackData` | pull-only | **deadlock** (saturated) |
| `crCompliant`, no ACKs | pull-only | **deadlock** (saturated) |
| `sharedReqData` (late ACK) | pull-only | **deadlock** (see `TwoPeerLoadStore`) |
| `sharedReqData`, no ACKs | pull-only | **deadlock** (saturated) |

**Interpretation**

* **Early ACK (`ackReq`)** frees the request PDL slot after the peer consumes
  `pullReq` (`targetPull`) but before `pullData` returns. With **merged**
  request/data windows (`sharedReqData`), omitting it deadlocks even on
  pull-only traffic: each peer's `pullReq` blocks the peer's `pullData`.
* With **separate** request/data windows (`crCompliant`), early ACK is not
  required to *complete* a single pull round-trip (the data window is
  independent), but **some** ACK mechanism is still needed to drain PDL flight
  tracking — without `ackReq`, completed pulls leave `reqFlight` occupied and
  the system deadlocks before reaching idle.
* A literal one-request/one-response design with **no** ACK-for-request and
  **no** ACK-for-response cannot reuse Falcon's bounded PDL windows as modeled
  here; slots must be released implicitly on delivery (different semantics) or
  the connection stalls.

## Open follow-ups

* Discharge a `sharedScheduler` deadlock claim (model supports the design knob;
  witness not yet found in bounded search).
* Extend to CLOS topology with Falcon endpoints.
* Add byte-granular buffer pools and RNR/CIE flows.
