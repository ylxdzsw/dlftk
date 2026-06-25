# Study: CLOS fabric and broken-link failover

**dlftk pin:** `v0.1.0` (see `study.toml`)

## Question

On a one-layer CLOS with parallel planes, can traffic failover to surviving
planes after a link/plane failure? When does residual state on the dead plane
cause deadlock?

## Models

- `DLFTK.Switch.CreditConservative`
- `DLFTK.Switch.Topology.OneLayerClos`

## Results

### Cross traffic (`OneLayerClos.lean`)

| design | reachable states | result |
|--------|------------------|--------|
| tight buffers | 80 (saturated) | deadlock-free |
| relaxed VOQ | 304 (saturated) | deadlock-free |

### Broken plane 0 (`BrokenLink.lean`)

| scenario | result |
|----------|--------|
| failover to plane 1 | deadlock-free |
| stuck egress on dead plane | **deadlocks** |
| stuck VOQ on dead plane | **deadlocks** |
| drain ingress, then failover | deadlock-free |

## Build

```
lake build StudyClosFabric
```

Standalone:

```
cd studies/clos-fabric && lake build
```
