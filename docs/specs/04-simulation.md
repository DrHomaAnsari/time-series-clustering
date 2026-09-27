---
name: simulation
status: draft
phase: 1
last-reviewed: 2026-09-27
---

# Simulation

`ts_cluster.simulate` is product code, not test scaffolding: a public, documented module that
writes generated datasets to disk explicitly. It serves three jobs, which is why it is built early
— immediately after validation — rather than last:

1. **Ground truth for testing** — the only way to assert that an unsupervised pipeline is correct.
2. **Documentation and examples** — the README walkthrough and example notebook run on it, so
   nobody needs a proprietary dataset to evaluate the library.
3. **The Phase 6 benchmark corpus** — comparative evaluation needs a stable, versioned corpus.

## 1. Hard invariant

Simulated output passes [01](01-data-contract.md) validation with zero errors and zero warnings,
tested directly ([07 §2](07-testing.md)). The simulator is the reference implementation of valid
input, so any disagreement with the validator surfaces here rather than at a user's first real
dataset.

## 2. Processes

Each process generates one univariate series of length `n` from a seeded generator. Parameters are
drawn per entity, so entities vary within a group without leaving it.

| Process | Generates | Group-defining parameter | Purpose |
|---|---|---|---|
| `ar` | AR(p), default p=1 | Coefficient φ — persistence | Groups differing in autocorrelation structure |
| `seasonal` | Sinusoid + noise | Period; amplitude and phase vary within group | Groups differing in cyclicity |
| `trend_step` | Linear trend + level shift | Slope and step magnitude; changepoint varies | Groups with non-stationary mean |
| `random_walk` | Cumulative sum of noise | Step scale | Non-stationary, no fixed level |
| `white_noise` | i.i.d. Gaussian | — (structureless by construction) | **Entities that should be labelled noise** |

`white_noise` tests what nothing else can: a correct pipeline labels these entities `-1` rather
than manufacturing a cluster out of them. Measured as `noise_recall` ([05](05-evaluation.md)).

Every process accepts a noise scale — the primary knob for how separable the groups are.

## 3. Seeding

One dataset seed determines everything. Per-entity generators are derived with
`numpy.random.SeedSequence.spawn`, never by incrementing a seed or drawing sequentially from a
shared generator.

Spawned child seeds are independent and position-stable: entity *k* gets the same series however
many entities precede it, whether or not generation is parallelised, and when an unrelated group is
added to the spec. Sequential draws guarantee none of this, and a dataset that silently changes when
its spec is edited voids every threshold calibrated against it.

## 4. API

```python
@dataclass(frozen=True)
class GroupSpec:
    process: str            # one of the table in §2
    n_entities: int
    params: dict            # process-specific
    label: int              # ground-truth group id; -1 for structureless groups

@dataclass(frozen=True)
class DatasetSpec:
    name: str
    n_timesteps: int
    groups: tuple[GroupSpec, ...]

@dataclass(frozen=True)
class SimulatedDataset:
    wide: pd.DataFrame      # conforms to 01-data-contract §1
    truth: pd.Series        # int labels, indexed identically to `wide`
    spec: DatasetSpec
    seed: int

def generate(spec: DatasetSpec, seed: int) -> SimulatedDataset: ...
def write(dataset: SimulatedDataset, path: Path) -> Path: ...
def load(path: Path) -> SimulatedDataset: ...
```

Entity ids are `f"{process}_{label}_{i:04d}"` — readable, sortable and self-describing, so a
misclustered entity is identifiable from its id alone, without a join back to the truth series.

Ground-truth labels are integers `≥ 0` for structured groups and `-1` for structureless ones —
HDBSCAN's own convention, so truth and prediction compare directly.

## 5. On-disk layout

```
<output.root>/<output.dataset_dir>/<name>/   # default ./outputs/datasets/<name>
  wide.parquet       # the input frame
  truth.parquet      # ground-truth labels
  spec.json          # DatasetSpec + seed — enough to regenerate exactly
```

`write(dataset, path)` takes its destination outright and reads no config: generating a corpus is a
deliberate act by a caller, not a stage of a run, and threading an `OutputConfig` through it would
buy nothing. The layout above is the convention — where the preset corpus, the README walkthrough
and the example notebook write, and what a bare dataset name resolves against — declared once as
`output.dataset_dir` ([03](03-config.md)) instead of hardcoded at each call site.

Datasets therefore live inside the repo by default, under the same gitignored `output.root` as runs
and logs. They are ignored rather than tracked because `spec.json` makes each one regenerable: the
corpus is reproducible from source, not from committed binaries ([07 §4](07-testing.md)).

Parquet, because it round-trips dtypes and column labels losslessly. CSV does not, and a time axis
reread as strings would trip `E010` on data we generated ourselves.

## 6. Preset corpus

Named presets are the shared vocabulary of the test suite, the docs and the Phase 6 benchmarks.
Each has a canonical seed; the thresholds in [05](05-evaluation.md) reference these names.

| Preset | Composition | Tests |
|---|---|---|
| `easy_separable` | 3 groups, well-separated processes, low noise | The pipeline works at all |
| `moderate` | 4 groups, overlapping parameters, moderate noise | Realistic difficulty |
| `hard_overlapping` | 4 groups, close parameters, high noise | Degrades gracefully rather than failing |
| `with_noise` | 3 structured groups + a `white_noise` group | Noise is identified, not absorbed into clusters |
| `single_cluster` | 1 group only | Does not split homogeneous data |
| `no_structure` | `white_noise` only | **Negative test** — does not invent structure |

`no_structure` and `single_cluster` are the two most valuable presets. Any pipeline finds groups
that exist; the failure that costs an analyst credibility is confidently reporting clusters in data
that has none. Both are enforced as hard test cases.

## 7. Scope

The simulator models shape well enough to distinguish groups. It is deliberately not a realistic
data generator: no missingness, no regime changes mid-series, no cross-entity correlation, no
irregular sampling.

> Phase 3 — irregularly sampled generation arrives with the resampling module, and not before:
> generating input the Phase 1 contract rejects would be actively misleading.
