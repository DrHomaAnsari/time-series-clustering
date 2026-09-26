---
name: config
status: draft
phase: 1
last-reviewed: 2026-09-26
---

# Config — The Public API

**The config *is* the public API.** There is no other supported way to drive a run. Everything a
caller can influence appears here; anything not here is not configurable, deliberately.

Implemented as a nested **pydantic v2** model with `extra="forbid"` at every level. Forbidding
unknown fields is not pedantry — an agent that misremembers a field name must get a loud
`ValidationError` naming the valid alternatives, not a silently ignored setting and a wrong
result.

A config is fully serialisable to and from YAML and JSON. That property is what makes the Phase 7
plugin surface close to a direct mapping of this document.

> Each field below states its **effect on results**, not just its type. A default whose
> consequence isn't documented will eventually be changed by someone who didn't know what it was
> holding up — see rule 2 in [`CLAUDE.md`](../../CLAUDE.md).

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

---

## `seed`

| Field | Type | Default | Effect |
|---|---|---|---|
| `seed` | `int` | `0` | Seeds every stochastic component. Same config + same seed **must** produce identical labels |

See [§ Determinism](#determinism) — this is a hard requirement, not best effort.

---

## `input`

Governs the validation rules in [`01-data-contract.md` §3](01-data-contract.md).

| Field | Type | Default | Effect |
|---|---|---|---|
| `assume_regular` | `bool` | `false` | `true` skips regularity check `E012` and records the user's assertion in the manifest. Use for semantically-regular-but-not-constant spacing (month-ends, trading days) |
| `regularity_tolerance` | `float` | `0.0` | Permitted relative jitter in successive column deltas before `E012` fires |
| `on_nan` | `"error" \| "drop_entity"` | `"error"` | No impute option exists at input stage. `drop_entity` records removed ids in the manifest |
| `on_constant_series` | `"error" \| "drop_entity"` | `"error"` | Constant series make many tsfresh features undefined. Forcing an explicit choice is the point |
| `min_series_length` | `int ≥ 2` | `16` | Below this, much of the tsfresh catalogue is degenerate |
| `min_entities` | `int ≥ 2` | `10` | Below this, density clustering cannot produce a meaningful partition |

---

## `features`

tsfresh extraction.

| Field | Type | Default | Effect |
|---|---|---|---|
| `parameter_set` | `"minimal" \| "efficient" \| "comprehensive"` | `"efficient"` | Maps to tsfresh's `Minimal`/`Efficient`/`Comprehensive` `FCParameters`. **Comprehensive** adds features flagged high-computation-cost and is too slow to be a sane default even at laptop scale. **Minimal** (~10 features) is for smoke tests, not analysis |
| `n_jobs` | `int` | `-1` | `-1` = all cores. Extraction is deterministic regardless of parallelism, so this affects runtime only — never results |
| `on_nonfinite` | `"drop_feature" \| "impute" \| "error"` | `"drop_feature"` | See below |
| `max_nonfinite_feature_fraction` | `float ∈ [0,1]` | `0.3` | If more than this share of feature columns would be dropped, raise instead — a signal something is wrong upstream, not a matrix to quietly shrink |

### `on_nonfinite` — why the default differs from tsfresh

tsfresh unavoidably emits `NaN` and `±inf` for some feature/series combinations. tsfresh's own
`impute()` replaces them column-wise with median/max/min.

The default here is **`drop_feature`**, not impute, because imputation **fabricates values that
then define the geometry** the clusterer operates on — an entity gets pulled toward the median on
a feature that was genuinely undefined for it, and nothing in the output reveals this. Dropping a
few dozen columns out of ~780 costs little; inventing coordinates costs correctness.

`"impute"` remains available, uses tsfresh's own semantics, and is recorded in the manifest.
Dropped feature names are always recorded.

---

## `selection`

| Field | Type | Default | Effect |
|---|---|---|---|
| `method` | `"none" \| "unsupervised" \| "supervised"` | `"unsupervised"` | See below |
| `variance_threshold` | `float ≥ 0` | `0.0` | Drops features with variance at or below this. `0.0` removes exactly the constant columns |
| `correlation_threshold` | `float ∈ (0,1]` | `0.95` | Above this absolute Pearson correlation, one of the pair is dropped. Lower = more aggressive pruning |
| `target_type` | `"real" \| "binary" \| null` | `null` | Required when `method = "supervised"` |
| `fdr_level` | `float ∈ (0,1)` | `0.05` | tsfresh `select_features` false-discovery-rate level. Higher keeps more features |

**`unsupervised`** (default): variance filter, then redundancy pruning by absolute correlation.
tsfresh's ~780 features are heavily collinear by construction — many are parameterised variants
of each other — and that redundancy distorts distances by effectively re-weighting whatever the
duplicated features measure. Tie-breaks resolve by column order so the result is deterministic.

**`supervised`**: tsfresh `select_features` against the target from
[`01-data-contract.md` §4](01-data-contract.md). Requires `target_type`; tsfresh auto-detects, but
an explicit declaration makes the run reproducible from the config alone.

> The target is **never** a cluster label. See `01-data-contract.md` §4.

---

## `scaling`

| Field | Type | Default | Effect |
|---|---|---|---|
| `method` | `"robust" \| "standard" \| "quantile" \| "none"` | `"robust"` | See below |
| `quantile_output` | `"uniform" \| "normal"` | `"normal"` | Only when `method = "quantile"` |

Default is **robust** (median / IQR), not `StandardScaler`. tsfresh features are heavy-tailed and
span many orders of magnitude; under mean/std scaling a single extreme entity inflates the
standard deviation of a feature, compressing every other entity into a narrow band on that axis
and effectively deleting it from the distance computation. Robust scaling keeps that feature
usable.

`"quantile"` is the strongest option for severely non-normal features but is non-linear and
distorts relative distances — appropriate when features are badly behaved, not as a default.
`"none"` will let high-magnitude features dominate the geometry outright and exists for
diagnostics only.

---

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

Reduction is **not optional in practice**. HDBSCAN's density estimates degrade sharply as
dimensionality rises, and a tsfresh matrix has hundreds of columns. `"none"` exists for
diagnostics and small curated feature sets; expect poor results past a few dozen features.

**Default is `pca`**, despite UMAP usually separating clusters better, because PCA is
deterministic, linear, and gives a stable coordinate system across refits — which Phase 2 label
stability depends on. UMAP's embedding is not stable between fits, so choosing it trades Phase 2
groundwork for Phase 1 cluster quality. Both must work; the default picks the conservative side.

**`umap.min_dist = 0.0`** is deliberate and differs from umap-learn's own default of `0.1`. UMAP's
documentation recommends `0.0` when the embedding feeds a clusterer: `min_dist` controls how
tightly points may pack, and any value above zero artificially spreads dense regions apart,
eroding exactly the density contrast HDBSCAN relies on. The library default is tuned for
visualisation, not clustering.

---

## `clustering`

HDBSCAN. Implementation is the standalone `hdbscan` package — see
[`02-pipeline.md`](02-pipeline.md) for why.

| Field | Type | Default | Effect |
|---|---|---|---|
| `min_cluster_size` | `int ≥ 2` | `5` | Smallest admissible cluster. **The most consequential single parameter** — raising it merges small groups into noise |
| `min_samples` | `int ≥ 1` \| `null` | `null` | `null` = follow `min_cluster_size`. Higher = more conservative, more noise |
| `metric` | `str` | `"euclidean"` | Distance in the embedding |
| `cluster_selection_method` | `"eom" \| "leaf"` | `"eom"` | `eom` favours fewer, larger clusters; `leaf` gives finer, more homogeneous ones |
| `cluster_selection_epsilon` | `float ≥ 0` | `0.0` | Merges clusters closer than this. `0.0` disables |
| `gen_min_span_tree` | `bool` | `true` | **Must stay `true`** — `relative_validity_` is unavailable without it, and that metric is the primary internal score in [`05-evaluation.md`](05-evaluation.md) |
| `prediction_data` | `bool` | `false` | > Phase 2 — `approximate_predict` on unseen entities requires `true`. Costs memory; off in Phase 1 |

---

## `evaluation`

| Field | Type | Default | Effect |
|---|---|---|---|
| `internal_metrics` | `list[str]` | `["relative_validity", "n_clusters", "noise_fraction", "cluster_size_distribution"]` | Computed on every run |
| `external_metrics` | `list[str]` | `["ari", "ami"]` | Computed only when ground-truth labels are supplied (simulated data) |
| `noise_fraction_warn_above` | `float ∈ [0,1]` | `0.5` | Emits a manifest warning, **never** an error. `-1` is a real answer |

---

## `output`

Everything the library writes — run artifacts, run logs, and generated datasets — lands under a
single configurable root. A library that scatters files across the working tree is one whose
outputs cannot be found, relocated, or excluded from version control as a unit.

| Field | Type | Default | Effect |
|---|---|---|---|
| `root` | `Path` | `"outputs"` | The one directory everything the library writes lands under. Relative values resolve against the process working directory, so the default is `./outputs` — inside the repo, and gitignored. Set an absolute path to send output elsewhere entirely |
| `run_dir` | `Path` | `"runs"` | Parent directory for run directories, resolved **under `root`**. Must be relative; an absolute value raises. Relocating output is `root`'s job, and allowing both to escape gives two ways to express one thing |
| `log_dir` | `Path` | `"logs"` | Where per-run log files are written, resolved under `root`. Must be relative. Deliberately **not** inside `run_dir` — see [`06-artifacts.md` §2](06-artifacts.md) |
| `dataset_dir` | `Path` | `"datasets"` | Where [`04-simulation.md`](04-simulation.md) writes generated datasets, resolved under `root`. Must be relative |
| `run_name` | `str` \| `null` | `null` | `null` = `{timestamp}-{config_hash[:8]}`. Names both the run directory and its log file, so the two are matched by inspection |
| `persist` | `bool` | `true` | `false` returns results in memory only and writes **no run directory**. The log file is still written — see below |
| `log_level` | `"DEBUG" \| "INFO" \| "WARNING" \| "ERROR"` | `"INFO"` | Verbosity of both the log file and the stream. Affects the log only, never results. There is no option to disable the log file in Phase 1 |
| `write_feature_matrix` | `bool` | `true` | The largest artifact; disable when disk-bound |
| `write_embedding` | `bool` | `true` | — |

Layout and the JSON summary schema are specified in [`06-artifacts.md`](06-artifacts.md).

### Why the log survives `persist = false`

`persist = false` is for exploratory runs whose artifacts nobody wants to keep. Those are exactly
the runs that misbehave, and a diagnostic trace is the one thing worth having when one does. The
log is small, bounded by the run's duration, and costs nothing to keep.

This is the single exception to "`persist = false` writes nothing", and it is narrow by
construction: the log carries no results. Anything a caller might need is in the manifest and the
summary, which `persist = false` genuinely does not write.

---

## Determinism

A hard requirement: **same config + same seed → identical labels.** Not "statistically similar".

| Component | Determinism |
|---|---|
| tsfresh extraction | Deterministic. `n_jobs` affects runtime only |
| Selection | Deterministic; correlation-pruning tie-breaks resolve by column order |
| Scaling | Deterministic |
| PCA | Deterministic given `seed` (sign convention fixed by scikit-learn) |
| UMAP | Deterministic **only** when `random_state` is set — and umap-learn then forces single-threaded optimisation, emitting a warning. Reproducibility costs wall-clock here; we pay it |
| HDBSCAN | Deterministic |

The UMAP behaviour is the one genuinely surprising item: an unseeded UMAP run gives different
clusters every time, and nothing in the output says so. `seed` is always applied; there is no
option to disable it.

## Config hash and provenance

The config hash is `sha256` of the **fully resolved** config (defaults materialised) serialised as
canonical JSON — sorted keys, no whitespace. It names run directories and appears in the manifest.

Resolving before hashing matters: two configs that differ only in which fields were written
explicitly describe the same run and must hash identically.

## Related specs

- [`01-data-contract.md`](01-data-contract.md) · [`02-pipeline.md`](02-pipeline.md)
- [`05-evaluation.md`](05-evaluation.md) · [`06-artifacts.md`](06-artifacts.md)
- `schemas/config.schema.json` — generated from this model; never hand-edited
