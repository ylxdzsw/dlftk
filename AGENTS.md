# dlftk — development guide

Repo-specific reference for extending the library and running new studies.
Human-oriented overview and research list: [README.md](README.md).

## Architecture

Two layers, versioned independently:

```
DLFTK/              semver library — models & topologies (no study theorems)
studies/<id>/       one research thread; pins dlftk via lakefile.toml
studies/_template/  scaffold for new studies
```

**Library** (`DLFTK/`) — reusable, tag releases `v0.x.y`:

| Path | Contents |
|------|----------|
| `Core.lean` | `System`, BFS reachability, saturation |
| `Analysis.lean` | `findDeadlock`, `deadlockFree`, `reachableSaturated` |
| `UB/` | Two-node store link: Types, Model, Transitions |
| `Switch/` | CreditConservative, CreditSplit, PFC, Topology/OneLayerClos |

**Study** (`studies/<id>/`) — hypothesis, params, claims, prose:

| File | Role |
|------|------|
| `*.lean` | `#eval` diagnostics, `native_decide` claims |
| `README.md` | Short summary (motivation, approach, key results) |
| `report.md` | Full journal: failures, rejected ideas, parameter search |
| `lakefile.toml` | Build + dlftk pin (`rev` when frozen) |

Studies must not import other studies. Promote shared code to `DLFTK/`.

## Model conventions

Every model/topology exports: **`Params`**, **`St`**, **`system`**, **`hasWork`**.

- **`progress`** — fabric-internal steps (transmit, process, route, deliver, …)
- **`env`** — external load, faults, credit return from outside

Select models by `import`. Select features via `Params` fields (`linkUp`,
`VLMap`, buffer caps) — not global defs.

Workloads: wrap `system` with a custom `env` (e.g. `crossTrafficSys`,
`crossTrafficOnPlaneSys` in OneLayerClos) or custom `init`.

Claims: pair `deadlockFree` / `findDeadlock` with `reachableSaturated` when
possible so results are over the exact reachable set.

## File organization rules

| Adding… | Put it in… |
|---------|------------|
| New protocol, switch, topology | `DLFTK/` |
| Theorem about a specific design | `studies/<id>/*.lean` |
| Narrative, dead ends | `studies/<id>/report.md` |
| Public summary of a study | `studies/<id>/README.md` |

Register new study libs in root `lakefile.toml` (`srcDir` + `roots` listing
every `.lean` file in the study).

## Versioning

- Library version: root `lakefile.toml` `version`; release with git tag `v0.x.y`
- **MAJOR** — breaking `System` / step / exported type change
- **MINOR** — new model or backward-compatible `Params` field
- **PATCH** — fix, no semantic change

Studies pin a tag in `studies/<id>/lakefile.toml`:

```toml
[[require]]
name = "dlftk"
git = "https://github.com/ylxdzsw/dlftk.git"
rev = "v0.1.0"
```

Monorepo development uses `path = "../.."`. When freezing a study, switch to
`git`/`rev`, run `lake update`, commit `lake-manifest.json`.

To upgrade a study against a newer library: copy the folder, bump `rev`, fix
breakages; leave the old folder as historical record.

## Workflows

**Build library only**

```
lake build DLFTK
```

**Build library + all registered studies**

```
lake build
```

**Build one study from repo root**

```
lake build StudyUbVlSeparation
lake build StudyClosFabric
```

**Build study standalone** (uses study's own lakefile + dlftk dep)

```
cd studies/clos-fabric && lake build
```

**Start a new study**

1. `cp -r studies/_template studies/<id>`
2. Edit `lakefile.toml` — rename package, set `roots` to all study `.lean` files
3. Rename `StudyTemplate.lean` to match; add claim modules
4. Write `README.md` (summary) and `report.md` (journal)
5. Add `[[lean_lib]]` entry to root `lakefile.toml`
6. `lake build Study<id>`

**Add a reusable model**

1. Implement under `DLFTK/` following `Params` / `St` / `system` / `hasWork`
2. Export from `DLFTK.lean` if part of the default library surface
3. Bump minor version; tag release
4. New or existing study imports the module and adds claims

## Core roadmap

Land in `DLFTK/` first; discharge claims in a new `studies/` folder:

- Wait-for-graph theory layer (Mathlib)
- UB in-band ACK / credit-return path
- Posted writes, longer dependency chains
- Falcon, CXL.mem fabric models
- CreditSplit vs CreditConservative comparison studies

## Active studies

| Id | Lake target | Modules used |
|----|-------------|--------------|
| `ub-vl-separation` | `StudyUbVlSeparation` | `DLFTK.UB.Transitions` |
| `clos-fabric` | `StudyClosFabric` | `Switch.CreditConservative`, `Topology.OneLayerClos` |
| `falcon-deadlock` | `StudyFalconDeadlock` | `Falcon.Transitions` |
