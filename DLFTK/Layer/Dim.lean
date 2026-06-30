/-
# DLFTK.Layer.Dim — L2 multiplex dimension

Virtual lanes, switch lanes, and Ethernet priorities are the same indexing
idea at the **link layer**: independent buffer / flow-control pools multiplexed
on one physical hop. Protocol code (L4) assigns semantics; L2 only tracks `dim`.
-/
namespace DLFTK.Layer

/-- L2 multiplex index (VL, lane, priority, …). -/
abbrev Dim := Nat

end DLFTK.Layer
