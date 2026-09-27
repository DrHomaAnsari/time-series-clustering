---
name: config
status: draft
phase: 1
last-reviewed: 2026-09-27
---

# Config — The Public API

The config is the only supported way to drive a run. Everything a caller can influence is here;
anything absent is deliberately not configurable.

- **Model** — nested pydantic v2, `extra="forbid"` at every level. An agent that misremembers a
  field name must get a loud `ValidationError` naming the valid alternatives, not a silently
  ignored setting and a wrong result.
- **Serialisation** — fully to and from YAML and JSON, which makes the Phase 7 plugin surface close
  to a direct mapping of this document.
- **Documentation** — every field states its effect on results, not just its type. An undocumented
  default eventually gets changed by someone who didn't know what it was holding up (Rule 2 in
  [`CLAUDE.md`](../../CLAUDE.md)).

## Shape

```yaml
seed: 0
input:      {...}
features:   {...}
selection:  {...}
scaling:    {...}
reduction:  {method: pca, pca: {...}, umap: {...}}
clustering: {...}
evaluation: {...}
output:     {...}
```

## `seed`

| Field | Type | Default | Effect |
|---|---|---|---|
| `seed` | `int` | `0` | Seeds every stochastic component. Same config + same seed must produce identical labels — a hard requirement, not best effort ([§ Determinism](#determinism)) |

## `input`

Governs the validation rules in [01 §3](01-data-contract.md).

| Field | Type | Default | Effect |
|---|---|---|---|
| `assume_regular` | `bool` | `false` | `true` skips regularity check `E012` and records the user's assertion in the manifest. For semantically regular but not constant spacing (month-ends, trading days) |
| `regularity_tolerance` | `float` | `0.0` | Permitted relative jitter in successive column deltas before `E012` fires |
| `on_nan` | `"error" \| "drop_entity"` | `"error"` | `drop_entity` records removed ids in the manifest. No impute option exists at the input stage |
| `on_constant_series` | `"error" \| "drop_entity"` | `"error"` | Constant series make many tsfresh features undefined; forcing an explicit choice is the point |
| `min_series_length` | `int ≥ 2` | `16` | Below this, much of the tsfresh catalogue is degenerate |
| `min_entities` | `int ≥ 2` | `10` | Below this, density clustering cannot produce a meaningful partition |

## `features`

tsfresh extraction.

| Field | Type | Default | Effect |
|---|---|---|---|
| `parameter_set` | `"minimal" \| "efficient" \| "comprehensive"` | `"efficient"` | Maps to tsfresh's `Minimal`/`Efficient`/`Comprehensive` `FCParameters`. Comprehensive adds high-computation-cost features — too slow for a sane default even at laptop scale. Minimal (~10 features) is for smoke tests, not analysis |
| `n_jobs` | `int` | `-1` | `-1` = all cores. Extraction is deterministic regardless of parallelism: runtime only, never results |
| `on_nonfinite` | `"drop_feature" \| "impute" \| "error"` | `"drop_feature"` | See below |
| `max_nonfinite_feature_fraction` | `float ∈ [0,1]` | `0.3` | If more than this share of feature columns would be dropped, raise instead — something is wrong upstream, and the matrix must not quietly shrink |

**`on_nonfinite` defaults to `drop_feature`, unlike tsfresh.** tsfresh unavoidably emits `NaN` and
`±inf` for some feature/series combinations, and its `impute()` replaces them column-wise with
median/max/min. Imputation fabricates values that then define the clustering geometry — an entity
is pulled toward the median on a feature that was genuinely undefined for it, and nothing in the
output reveals it. Dropping a few dozen of ~780 columns costs little; inventing coordinates costs
correctness. `"impute"` remains available, with tsfresh's semantics, and is recorded in the
manifest. Dropped feature names are always recorded.

## `selection`

| Field | Type | Default | Effect |
|---|---|---|---|
| `method` | `"none" \| "unsupervised" \| "supervised"` | `"unsupervised"` | See below |
| `variance_threshold` | `float ≥ 0` | `0.0` | Drops features with variance at or below this. `0.0` removes exactly the constant columns |
| `correlation_threshold` | `float ∈ (0,1]` | `0.95` | Above this absolute Pearson correlation, one of the pair is dropped. Lower = more aggressive pruning |
| `target_type` | `"real" \| "binary" \| null` | `null` | Required when `method = "supervised"` |
| `fdr_level` | `float ∈ (0,1)` | `0.05` | tsfresh `select_features` false-discovery-rate level. Higher keeps more features |

- **`unsupervised`** (default) — variance filter, then redundancy pruning by absolute correlation,
  ties resolved by column order so the result is deterministic. tsfresh's ~780 features are heavily
  collinear by construction (many are parameterised variants of each other), and that redundancy
  distorts distances by re-weighting whatever the duplicated features measure.
- **`supervised`** — tsfresh `select_features` against the target from
  [01 §4](01-data-contract.md), which is never a cluster label. Requires `target_type`: tsfresh
  can auto-detect it, but declaring it makes the run reproducible from the config alone.

## `scaling`

| Field | Type | Default | Effect |
|---|---|---|---|
| `method` | `"robust" \| "standard" \| "quantile" \| "none"` | `"robust"` | See below |
| `quantile_output` | `"uniform" \| "normal"` | `"normal"` | Only when `method = "quantile"` |

**Default `robust`** (median / IQR), not `StandardScaler`. tsfresh features are heavy-tailed and
span many orders of magnitude; under mean/std scaling one extreme entity inflates a feature's
standard deviation, compressing every other entity into a narrow band on that axis and effectively
deleting the feature from the distance computation.

`"quantile"` is strongest for severely non-normal features but is non-linear and distorts relative
distances, so it is for badly behaved features, not a default. `"none"` lets high-magnitude
features dominate the geometry outright; diagnostics only.

## `reduction`

| Field | Type | Default | Effect |
|---|---|---|---|
| `method` | `"pca" \| "umap" \| "none"` | `"pca"` | See below |
| `pca.n_components` | `int ≥ 1` \| `float ∈ (0,1)` | `0.95` | Float = variance fraction retained; int = component count |
| `pca.whiten` | `bool` | `false` | Whitening equalises component variances, which changes cluster shapes |
| `umap.n_components` | `int ≥ 1` | `5` | Embedding dimension. `2` is for visualisation; clustering usually does better at 5–15 |
| `umap.n_neighbors` | `int ≥ 2` | `15` | Low = local structure and more, smaller clusters; high = global structure |
| `umap.min_dist` | `float ∈ [0,1)` | `0.0` | See below |
| `umap.metric` | `str` | `"euclidean"` | Distance in feature space |

Reduction is not optional in practice: HDBSCAN's density estimates degrade sharply as
dimensionality rises, and a tsfresh matrix has hundreds of columns. `"none"` is for diagnostics and
small curated feature sets; expect poor results past a few dozen features.

**Default `pca`**, though UMAP usually separates clusters better: PCA is deterministic, linear, and
gives a coordinate system stable across refits, which Phase 2 label stability depends on. UMAP's
embedding is not stable between fits, so choosing it trades Phase 2 groundwork for Phase 1 cluster
quality. Both must work; the default takes the conservative side.

**`umap.min_dist = 0.0`**, not umap-learn's default of `0.1`. UMAP's documentation recommends `0.0`
when the embedding feeds a clusterer: `min_dist` controls how tightly points may pack, and any value
above zero spreads dense regions apart, eroding the density contrast HDBSCAN relies on. The library
default is tuned for visualisation, not clustering.

## `clustering`

HDBSCAN, via the standalone `hdbscan` package ([02 §8](02-pipeline.md) says why).

| Field | Type | Default | Effect |
|---|---|---|---|
| `min_cluster_size` | `int ≥ 2` | `5` | Smallest admissible cluster, and the most consequential single parameter — raising it merges small groups into noise |
| `min_samples` | `int ≥ 1` \| `null` | `null` | `null` = follow `min_cluster_size`. Higher = more conservative, more noise |
| `metric` | `str` | `"euclidean"` | Distance in the embedding |
| `cluster_selection_method` | `"eom" \| "leaf"` | `"eom"` | `eom` favours fewer, larger clusters; `leaf` gives finer, more homogeneous ones |
| `cluster_selection_epsilon` | `float ≥ 0` | `0.0` | Merges clusters closer than this. `0.0` disables |
| `gen_min_span_tree` | `bool` | `true` | Must stay `true`: without it `relative_validity_`, the primary internal score in [05](05-evaluation.md), is unavailable |
| `prediction_data` | `bool` | `false` | > Phase 2 — `approximate_predict` on unseen entities requires `true`. Costs memory; off in Phase 1 |

## `evaluation`

| Field | Type | Default | Effect |
|---|---|---|---|
| `internal_metrics` | `list[str]` | `["relative_validity", "n_clusters", "noise_fraction", "cluster_size_distribution"]` | Computed on every run |
| `external_metrics` | `list[str]` | `["ari", "ami"]` | Computed only when ground-truth labels are supplied (simulated data) |
| `noise_fraction_warn_above` | `float ∈ [0,1]` | `0.5` | Emits a manifest warning, never an error |

## `output`

Everything the library writes — run artifacts, run logs, generated datasets — lands under one
configurable root, so its output can be found, relocated, or excluded from version control as a
unit.

| Field | Type | Default | Effect |
|---|---|---|---|
| `root` | `Path` | `"outputs"` | The one directory everything is written under. Relative values resolve against the process working directory, so the default is `./outputs` — inside the repo, and gitignored. An absolute path sends output elsewhere entirely |
| `run_dir` | `Path` | `"runs"` | Parent of run directories, resolved under `root`. Must be relative; an absolute value raises, because relocating output is `root`'s job and two ways to express one thing is one too many |
| `log_dir` | `Path` | `"logs"` | Where per-run log files go, resolved under `root`. Must be relative. Deliberately not inside `run_dir` ([06 §2](06-artifacts.md)) |
| `dataset_dir` | `Path` | `"datasets"` | Where [04](04-simulation.md) writes generated datasets, resolved under `root`. Must be relative |
| `run_name` | `str` \| `null` | `null` | `null` = `{timestamp}-{config_hash[:8]}`. Names both the run directory and its log file, so the two match by inspection |
| `persist` | `bool` | `true` | `false` returns results in memory only and writes no run directory. The log file is still written ([06 §5](06-artifacts.md) says why) |
| `log_level` | `"DEBUG" \| "INFO" \| "WARNING" \| "ERROR"` | `"INFO"` | Verbosity of both the log file and the stream; affects the log only, never results. The log file cannot be disabled in Phase 1 |
| `write_feature_matrix` | `bool` | `true` | The largest artifact; disable when disk-bound |
| `write_embedding` | `bool` | `true` | — |

Layout and the JSON summary schema: [06](06-artifacts.md).

## Determinism

A hard requirement: same config + same seed → identical labels. Not "statistically similar".

| Component | Determinism |
|---|---|
| tsfresh extraction | Deterministic. `n_jobs` affects runtime only |
| Selection | Deterministic; correlation-pruning tie-breaks resolve by column order |
| Scaling | Deterministic |
| PCA | Deterministic given `seed` (sign convention fixed by scikit-learn) |
| UMAP | Deterministic only when `random_state` is set — umap-learn then forces single-threaded optimisation and emits a warning. Reproducibility costs wall-clock here; we pay it |
| HDBSCAN | Deterministic |

UMAP is the surprising item: unseeded, it gives different clusters every run and nothing in the
output says so. `seed` is always applied; there is no option to disable it.

## Config hash and provenance

The config hash is `sha256` of the fully resolved config (defaults materialised), serialised as
canonical JSON — sorted keys, no whitespace. It names run directories and appears in the manifest.
Resolving first matters: configs that differ only in which fields were written explicitly describe
the same run and must hash identically.

`schemas/config.schema.json` is generated from this model and never hand-edited
([schemas](schemas/README.md)).
