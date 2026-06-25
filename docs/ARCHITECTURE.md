# dlftk architecture — versioned core + isolated studies

This document describes how to organize `dlftk` as a **research framework**:
a stable, versioned modeling library with **independent studies** that pin
library versions and compose only the features they need.

## Design goals

| Goal | Mechanism |
|------|-----------|
| Core evolves without breaking old papers | Semantic versioning + git tags on `dlftk` |
| Studies stay reproducible | Each study records `dlftk_version` and builds against a pinned `rev` |
| Flexible model / feature selection | Studies import only the modules they need; no monolithic scenario tree in core |
| Multiple concurrent research threads | One folder per study; no cross-imports between studies |
| Executable claims stay cheap | Shared `DLFTK.Core` + `DLFTK.Analysis` search layer |

## Repository layout

```
dlftk/                          # Lake package: the library (semver)
├── lakefile.toml               # version = "0.1.0"
├── lean-toolchain
├── DLFTK.lean                  # default library root (core + models, no studies)
├── DLFTK/
│   ├── Core.lean               # transition system, BFS reachability
│   ├── Analysis.lean           # deadlock predicates, findDeadlock
│   ├── UB/                     # UB protocol *models* (no case studies)
│   │   ├── Types.lean
│   │   ├── Model.lean
│   │   └── Transitions.lean
│   └── Switch/                 # switch models + reusable topologies
│       ├── Types.lean
│       ├── CreditConservative.lean
│       ├── CreditSplit.lean
│       ├── PFC.lean
│       └── Topology/
│           └── OneLayerClos.lean
├── studies/                    # research artifacts (not part of the library API)
│   ├── ub-vl-separation/
│   │   ├── study.toml          # manifest: id, dlftk pin, models used
│   │   ├── README.md           # human-readable result summary
│   │   ├── lakefile.toml       # standalone build; pins dlftk rev
│   │   ├── lean-toolchain      # usually same as core; may diverge later
│   │   └── StudyUbVlSeparation.lean
│   └── clos-fabric/
│       ├── study.toml
│       ├── README.md
│       ├── lakefile.toml
│       ├── lean-toolchain
│       ├── StudyClosFabric.lean
│       ├── OneLayerClos.lean
│       └── BrokenLink.lean
└── docs/
    └── ARCHITECTURE.md         # this file
```

### What lives in core vs a study

**Core (`DLFTK/`)** — reusable, documented, semver-governed:

- transition-system kernel and analysis tools
- protocol / switch **models** and composable **topologies**
- small shared helpers (`Types`, list indexing, VOQ counters)
- *no* `#eval` case studies, *no* `native_decide` theorems about a particular paper

**Study (`studies/<id>/`)** — a single research thread:

- hypothesis, parameters, workloads, init states
- `#eval` diagnostics and `native_decide` claims
- `README.md` results table for humans
- `study.toml` machine-readable manifest

## Versioning

### Library (`dlftk`)

Follow [semver](https://semver.org/) on the root `lakefile.toml` `version`:

| Bump | When |
|------|------|
| **MAJOR** | Breaking change to a exported type, transition step, or `System` interface |
| **MINOR** | New model, topology, or backward-compatible feature flag |
| **PATCH** | Bug fix, performance, documentation; no model semantics change |

Release process:

1. Update `version` in `lakefile.toml`.
2. Tag: `git tag v0.2.0 && git push origin v0.2.0`.
3. Record changelog (what models/steps changed).

Studies **never** bump the library version; they pin a tag.

### Study manifest (`study.toml`)

Each study carries metadata (TOML for easy parsing in CI):

```toml
id = "clos-fabric"
title = "One-layer CLOS fabric and broken-link failover"
dlftk_version = "0.1.0"          # semver the study was written against
dlftk_rev = "v0.1.0"             # exact git tag / commit for reproduction

[models]
ub = false
switch = ["CreditConservative"]
topology = ["OneLayerClos"]

[features]
link_faults = true
cross_traffic = true

[[claims]]
name = "failover_deadlock_free"
file = "BrokenLink.lean"
line = 42
```

CI can verify: checkout `dlftk_rev`, build study, check claims still pass.

### Pinning dependencies in `studies/*/lakefile.toml`

During active development (monorepo):

```toml
[[require]]
name = "dlftk"
path = "../.."
```

After a study is published / frozen:

```toml
[[require]]
name = "dlftk"
git = "https://github.com/ylxdzsw/dlftk.git"
rev = "v0.1.0"
```

To upgrade a study to a newer library, copy the folder (or branch), bump
`dlftk_rev`, fix breakages, update claims — the old folder stays as the
historical record.

## Composing models and features

Studies choose capabilities by **import**, not by configuration files in core:

```lean
import DLFTK.Analysis
import DLFTK.UB.Transitions              -- UB endpoint model
import DLFTK.Switch.CreditConservative    -- switch backpressure variant
import DLFTK.Switch.Topology.OneLayerClos -- topology composer
```

Conventions:

- **`Params` + `St` + `system` + `hasWork`** — every model/topology exports this
  quad so `DLFTK.Analysis` works uniformly.
- **Progress vs env** — progress = fabric steps; env = offered load, faults,
  external credit return. Studies define workload via custom `env` wrappers
  (see `crossTrafficSys`, `crossTrafficOnPlaneSys`).
- **Feature flags in `Params`** — e.g. `linkUp` for faults; avoid global
  `def`s that silently change model semantics.

Future optional layer: a typed `ModelBundle` structure for dynamic selection
in metaprograms — only add when a study actually needs runtime model picking.

## Study lifecycle

```
1. scaffold     lake init study from template (studies/_template/)
2. develop      import dlftk modules; iterate on model/workload
3. freeze       fill study.toml, write README results table
4. pin          set dlftk_rev to a release tag
5. maintain     new library version → new study folder or explicit upgrade PR
```

Studies must **not** import other studies. Shared code that becomes reusable
belongs in `DLFTK/`, not copied between study folders.

## Build targets

| Command | Builds |
|---------|--------|
| `lake build DLFTK` | Core library only (default for downstream consumers) |
| `lake build` | Core + all registered study libs (monorepo CI) |
| `cd studies/clos-fabric && lake build` | Single study against pinned/path dlftk |

Root `lakefile.toml` registers study libs for convenience:

```toml
[[lean_lib]]
name = "DLFTK"

[[lean_lib]]
name = "StudyUbVlSeparation"
srcDir = "studies/ub-vl-separation"

[[lean_lib]]
name = "StudyClosFabric"
srcDir = "studies/clos-fabric"
```

Each study also has its own `lakefile.toml` so it can be extracted to a
standalone repo later without structural changes.

## Migration from the current layout

Previously, case studies lived under `DLFTK/*/Scenario/`. The migration:

| Old path | New path |
|----------|----------|
| `DLFTK/UB/Scenario/TwoHostStore.lean` | `studies/ub-vl-separation/TwoHostStore.lean` |
| `DLFTK/Switch/Scenario/OneLayerClos.lean` | `studies/clos-fabric/OneLayerClos.lean` |
| `DLFTK/Switch/Scenario/BrokenLink.lean` | `studies/clos-fabric/BrokenLink.lean` |

`DLFTK.lean` re-exports **models only**. Studies import `DLFTK` modules
directly.

## Roadmap integration

Planned core additions stay in `DLFTK/`:

- `DLFTK/Theory/` — wait-for-graph layer (Mathlib)
- `DLFTK/UB/` — in-band ACK path, posted writes
- `DLFTK/Switch/` — additional backpressure models
- `DLFTK/Falcon/`, `DLFTK/CXL/` — new fabric families

Each gets its own study (or study chapter) when there is a concrete claim to
discharge — the core MR adds the model; the study MR adds the theorem.

## Template for a new study

Copy `studies/_template/`:

```
studies/my-study/
├── study.toml
├── README.md
├── lakefile.toml
├── lean-toolchain -> ../../lean-toolchain
└── StudyMyStudy.lean    # imports sibling modules + re-exports for Lake root
```

Minimum `StudyMyStudy.lean`:

```lean
import DLFTK.Analysis
-- import the models this study uses
import MyClaim
```

Minimum `README.md` sections: **Question**, **Models**, **Setup**, **Results**,
**dlftk pin**.
