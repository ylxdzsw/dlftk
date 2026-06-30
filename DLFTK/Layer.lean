/-
# DLFTK.Layer — Layered protocol modeling

```
L2  link hop     VL / credits / window / drop / retransmit
L3  fabric node  Ethernet switching (PFC, credit VOQ, …)
L4  protocol     UB messages, Falcon transactions, …

Topology     wiring graph (TwoNode, OneLayerClos, …) — separate from protocol
Compose      protocol × topology products (UbOnClos, …)
Preset       named bundles (FalconEthernet, …)
```

Design rules (see research discussion):

* **L1 is not modeled** — endpoints are thin injection/delivery hooks.
* **VL and multiplex dimensions are L2** — L4 only assigns class→dim policy.
* **Reliability is L2** — blocks may drop (`env`); `retransmit` replays them.
* **Topology ≠ protocol** — UB is not “two-node”; two-node is one topology.
* **Invalid feature combinations are not forbidden** — finite models stay simple.
-/
import DLFTK.Layer.Dim
import DLFTK.Layer.L2.Types
import DLFTK.Layer.L2.Link
import DLFTK.Layer.L3.Ethernet
