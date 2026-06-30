/-
# DLFTK.Layer.L3.Ethernet — Switched Ethernet fabric (L3)

Falcon and RoCE deployments assume **Ethernet switching** with PFC (or similar
lossless hop behavior) on a CLOS or line topology. This module names that L3
preset and re-exports the switch primitives studies already use.

L4 protocols (Falcon, UB-over-Ethernet, …) attach at host endpoints; L3 only
forwards routed frames/blocks.
-/
import DLFTK.Switch.Types
import DLFTK.Switch.PFC
import DLFTK.Switch.CreditConservative
import DLFTK.Switch.CreditSplit

namespace DLFTK.Layer.L3.Ethernet

/-- Ethernet switching backpressure mode at L3. -/
inductive SwitchMode
  | pfc
  | creditConservative
  | creditSplit
deriving DecidableEq, Repr, BEq, Hashable

/-- Common CLOS / line parameters for an Ethernet L3 fabric. -/
structure FabricParams where
  nHost : Nat
  nPlane : Nat
  nDim : Nat
  mode : SwitchMode := .pfc
  /-- PFC queue capacity per `(input, dim)` when `mode = pfc`. -/
  queueCap : Nat := 1
  pauseThreshold : Nat := 1
  resumeThreshold : Nat := 0
  /-- VOQ capacity when `mode = creditConservative`. -/
  voqCap : Nat := 1
  downCap : Nat := 1
  /-- Host↔plane link status (`true` = up). -/
  linkUp : List Bool := []
deriving DecidableEq, Repr, BEq, Hashable

end DLFTK.Layer.L3.Ethernet
