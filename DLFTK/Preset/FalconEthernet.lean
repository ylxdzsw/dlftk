/-
# DLFTK.Preset.FalconEthernet — Falcon L4 on Ethernet L3

Named bundle: Falcon transaction layer over PFC CLOS (`Compose.FalconEthernet`).
-/
import DLFTK.Compose.FalconEthernet
import DLFTK.Layer.L3.Ethernet

namespace DLFTK.Preset.FalconEthernet

open DLFTK.Compose.FalconEthernet
open DLFTK.Layer.L3.Ethernet

abbrev Params := Compose.FalconEthernet.Params
abbrev St := Compose.FalconEthernet.St

def defaultParams : Params := Compose.FalconEthernet.defaultParams

/-- Full Falcon-on-Ethernet system (L4 + PFC CLOS). -/
def system (P : Params) : DLFTK.System St :=
  Compose.FalconEthernet.system P

def hasWork := Compose.FalconEthernet.hasWork

end DLFTK.Preset.FalconEthernet
