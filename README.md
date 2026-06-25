# dlftk — a Lean library for studying deadlock in scale-up fabrics

`dlftk` is a research framework for formalizing and studying **deadlock** in
scale-up interconnects (e.g. Huawei UB, Google Falcon, CXL). Rather than the
classic *routing* deadlock theory (Dally/Duato — channel dependency graphs), it
targets the deadlock class that actually dominates simple-topology scale-up
fabrics: **resource / flow-control / message-dependent deadlock**.

## Architecture

The repo splits into two layers:

| Layer | Path | Role |
|-------|------|------|
| **Library** | `DLFTK/` | Versioned models, topologies, analysis tools |
| **Studies** | `studies/<id>/` | Independent research threads with pinned dlftk deps |

See **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for versioning, study
layout, and how to compose models via Lean imports.

## Approach

Everything is an **executable transition system** (`DLFTK.System`). Deadlock is
defined *operationally*:

> a **reachable** state that still has outstanding **work** but from which
> **no progress step** is possible.

For finite instances the reachable set is computed by a `HashSet`-based BFS
(`DLFTK.System.explore`) that reports whether it **saturated** (explored the
*exact* reachable set). Claims are then discharged by `native_decide`.

## Library layout (`DLFTK/`)

```
DLFTK/
  Core.lean        -- generic transition system + BFS reachability
  Analysis.lean    -- operational deadlock predicates + search
  UB/              -- two-node UB protocol model
  Switch/          -- switch backpressure models + CLOS topology
```

Studies import only what they need, e.g.:

```lean
import DLFTK.Analysis
import DLFTK.UB.Transitions
import DLFTK.Switch.Topology.OneLayerClos
```

## Studies (`studies/`)

| Study | Question | dlftk pin |
|-------|----------|-----------|
| [ub-vl-separation](studies/ub-vl-separation/) | shared vs separate VL deadlock on UB | v0.1.0 |
| [clos-fabric](studies/clos-fabric/) | CLOS cross traffic + broken-link failover | v0.1.0 |

Each study has `README.md` (results) and `lakefile.toml` (build + dlftk pin).
Commit `lake-manifest.json` when a study is frozen.

## Build

Core library only:

```
lake build DLFTK
```

Core + all studies:

```
lake build
```

Single study (standalone):

```
cd studies/clos-fabric && lake build
```

Requires the Lean toolchain pinned in `lean-toolchain`.

## Roadmap (core)

- Abstract **wait-for-graph** master theorem (Mathlib)
- In-band ACK/credit-return path on UB
- Posted writes and longer message-dependency chains
- Additional fabrics: Falcon, CXL.mem

Each item lands in `DLFTK/` first; a study folder adds the concrete claims.
