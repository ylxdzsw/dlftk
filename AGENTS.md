# dlftk — agent guide

Formal deadlock research for scale-up fabrics (UB, Falcon, CXL). Models are
executable transition systems; finite claims use BFS + `native_decide`.

## Layout

```
DLFTK/           library — models & topologies only (no case-study theorems)
studies/<id>/    one research thread per folder; never import other studies
studies/_template/   copy to start a new study
```

**Core modules:** `Core` (System + BFS), `Analysis` (deadlock search),
`UB/*` (two-node store link), `Switch/*` (CreditConservative, CreditSplit,
PFC, Topology/OneLayerClos).

**Studies today:** `ub-vl-separation`, `clos-fabric`.

## Conventions

Every model/topology exports: `Params`, `St`, `system`, `hasWork`.

- **progress** — fabric steps (transmit, process, route, deliver, …)
- **env** — offered load, faults, external credit return

Feature flags live in `Params` (e.g. `linkUp`, `VLMap`), not global defs.
Studies pick models via `import`; workloads via custom `env` wrappers
(e.g. `crossTrafficSys`, `crossTrafficOnPlaneSys` in OneLayerClos).

Deadlock = reachable + `hasWork` + no progress successor. Pair freedom
claims with `reachableSaturated` when possible.

## Where to put changes

| Change | Location |
|--------|----------|
| Reusable protocol/switch/topology | `DLFTK/` |
| Hypothesis, params, theorems | `studies/<id>/` |
| Shared between studies | promote to `DLFTK/`, don't copy |

Core semver in root `lakefile.toml`. Tag releases `v0.x.y`. Studies pin
`[[require]] rev` in their own `lakefile.toml`; commit `lake-manifest.json`
when frozen.

Monorepo dev: `path = "../.."` in study lakefile. Root lakefile registers
study libs with `srcDir` + `roots`.

## Build

```bash
lake build DLFTK              # library only
lake build                    # library + all studies
cd studies/clos-fabric && lake build   # standalone study
```

New study: copy `studies/_template/`, rename root module, list all `.lean`
files in `roots`, write README (Question / Models / Results / dlftk pin).

## Roadmap (core only)

WFG theory (Mathlib), UB in-band ACK, posted writes, Falcon/CXL models —
each lands in `DLFTK/` first; claims go in a new `studies/` folder.
