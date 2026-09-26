---
name: data-contract
status: draft
phase: 1
last-reviewed: 2026-09-26
---

# Data Contract

> Vocabulary is defined in [`00-product.md` §9](00-product.md). "Entity", "series", "timestep",
> "feature matrix" and "label" mean exactly what that glossary says.

This is the most-referenced spec in the repo. Everything downstream assumes the guarantees
established here hold, so this stage **validates and refuses** — it never repairs.

## 1. Primary input — wide DataFrame

```
                 t0      t1      t2     ...    tN
entity_id
"sensor_a"     0.13    0.19    0.22    ...   0.41
"sensor_b"     1.02    0.98    1.11    ...   0.95
```

| Element | Requirement |
|---|---|
| Container | `pandas.DataFrame` |
| Index | Entity ids — unique, non-null, `int` or `str` dtype |
| Columns | Ordered timesteps, shared by every entity |
| Values | Numeric (`int*` or `float*`), finite |
| Orientation | One row per entity, one column per timestep |

Wide format implies a **shared time index**: every entity is observed at the same timesteps. This
is a real constraint, not a formatting convenience — see §3.2.

### 1.1 Integer widening

Integer values are widened to `float64` before processing. This is lossless for the magnitudes in
scope and is the only implicit conversion permitted anywhere in the pipeline. Record it in the
manifest; do not extend this exception to other dtypes.

## 2. Validation model

Validation produces a `ValidationReport` with two disjoint severities:

- **Error** — the run stops. Nothing downstream may assume anything about the offending data.
- **Warning** — the run proceeds, and the warning is **written into the run manifest**
  ([`06-artifacts.md`](06-artifacts.md)). A warning that exists only in a log stream is lost the
  moment an agent reads results from disk, so warnings are artifacts, not log lines.

All errors are collected and reported **together**, not raised on the first failure. An agent
fixing input one error per round-trip is the single most wasteful loop this library could create.

Every error message states: what was expected, what was received (with offending entity ids,
truncated to the first 10 plus a count), and what to do about it.

## 3. Validation rules

Each rule has a stable identifier so tests, error messages, and the manifest can reference the
same thing.

### 3.1 Structural

| ID | Rule | Severity |
|---|---|---|
| `E001` | Input is a `pandas.DataFrame` | Error |
| `E002` | Index values are unique | Error |
| `E003` | Index contains no nulls | Error |
| `E004` | Index dtype is `int*` or `str`/`object`-of-`str` | Error |
| `E005` | Columns are **not** a `MultiIndex` — multivariate input is rejected, not flattened | Error |
| `E006` | All value dtypes are numeric; `bool` and `object` are rejected | Error |

> Phase 1 is univariate. `E005` exists so multivariate input fails loudly rather than being
> silently reinterpreted as extra timesteps. Multivariate is deferred indefinitely
> ([`ROADMAP.md`](../../ROADMAP.md)).

### 3.2 Time axis

| ID | Rule | Severity |
|---|---|---|
| `E010` | Column labels are numeric or datetime — **string column labels are rejected** | Error |
| `E011` | Column labels are strictly monotonically increasing | Error |
| `E012` | Sampling is regular: successive column deltas are constant | Error |

`E010` is deliberately strict. With string labels there is no way to verify time order, and an
out-of-order time axis silently corrupts every order-dependent feature tsfresh computes — with no
symptom whatsoever in the output. Requiring a numeric or datetime column index makes the
ordering checkable. Users with string labels must convert before calling.

`E012` enforces the Phase 1 precondition that input is already regularly sampled. Two escapes:

- `input.assume_regular = true` skips the check and **records the user's assertion in the
  manifest**. Use when spacing is semantically regular but not numerically constant (month-ends,
  trading days).
- `input.regularity_tolerance` permits bounded jitter in the deltas.

> Phase 3 — the resampling module attaches here. On detecting irregularity it will prompt for an
> explicit resampling policy rather than choosing one. Until then, `E012` is an error, not a
> silent resample.

### 3.3 Values

| ID | Rule | Severity |
|---|---|---|
| `E020` | No `NaN` in values, subject to `input.on_nan` | Error (configurable) |
| `E021` | No `±inf` in values | Error |
| `E022` | No constant (zero-variance) series, subject to `input.on_constant_series` | Error (configurable) |

`E020` — `NaN` in a wide frame usually means entities with unequal coverage, padded to a common
index. tsfresh treats those as missing and the resulting features are not comparable across
entities with different padding. `input.on_nan = "drop_entity"` removes offending entities and
records their ids in the manifest; there is no impute option at the input stage.

`E022` — constant series make many tsfresh features undefined (`skewness`, `kurtosis`, and every
ratio with a standard-deviation denominator return `NaN` or `±inf`). A stuck sensor is legitimate
data and often *interesting*, but it must be an explicit decision: error, or
`"drop_entity"` with the ids recorded.

### 3.4 Size

| ID | Rule | Severity | Default |
|---|---|---|---|
| `E030` | Series length ≥ `input.min_series_length` | Error | 16 |
| `W031` | Series length < 50 | Warning | — |
| `E032` | Entity count ≥ `input.min_entities` | Error | 10 |
| `W033` | Entity count < 50 | Warning | — |

The floors are not arbitrary. Below ~16 timesteps a large share of the tsfresh catalogue is
undefined or degenerate — autocorrelation and partial-autocorrelation lags run to 9, and
`agg_linear_trend` chunks at 5/10/50. Below ~10 entities, density-based clustering with a default
`min_cluster_size` of 5 cannot produce a meaningful partition. The warning thresholds mark where
results become unreliable rather than impossible.

## 4. Optional target — supervised feature selection

A separate argument, never a column of the wide frame.

| Element | Requirement |
|---|---|
| Container | `pandas.Series` |
| Index | Identical to the input entity index — same values, any order |
| Values | Numeric (real target) or binary |
| Length | One scalar per entity |

> **The target is not a cluster label.** It is a downstream quantity of interest — next-period
> value, an outcome, a class — used only to score which tsfresh features carry signal. Passing
> known cluster memberships here leaks the answer into feature selection and invalidates every
> evaluation metric in [`05-evaluation.md`](05-evaluation.md). If an agent is tempted to construct
> a target from clustering output, that is always a bug.

Rules:

| ID | Rule | Severity |
|---|---|---|
| `E040` | Target supplied when `selection.method = "supervised"` | Error |
| `E041` | Target index matches the entity index exactly (as a set) | Error |
| `E042` | Target contains no nulls | Error |
| `W043` | Target is ignored — with a warning — when `selection.method != "supervised"` | Warning |

`W043` is a warning rather than a silent ignore because passing a target that has no effect is
almost always a misunderstanding of what selection is doing.

## 5. Internal representation — the melt

tsfresh consumes long format, so validated wide input is melted immediately. The melt is part of
the contract because its details are load-bearing.

| Long column | Name | Content |
|---|---|---|
| id | `entity_id` | Entity index value |
| sort | `timestep` | **Integer position** of the column, 0-based |
| value | `value` | `float64` |

Column names are module constants (`ENTITY_COLUMN`, `TIME_COLUMN`, `VALUE_COLUMN`), never string
literals at call sites.

**The sort column is integer position, not the original column label.** tsfresh uses `column_sort`
only to order observations, and positional integers make ordering exact and dtype-independent —
avoiding datetime-vs-numeric comparison edge cases entirely. Original column labels are preserved
in the run manifest, not in the long frame.

Guarantees after melting: sorted by `(entity_id, timestep)`; row count exactly
`n_entities × n_timesteps`; no nulls.

## 6. Output contract

A run returns a `ClusterResult`:

| Attribute | Type | Content |
|---|---|---|
| `labels` | `pd.Series[int]` | Cluster assignment per entity, indexed by entity id. `-1` is noise — a real answer, never a failure |
| `probabilities` | `pd.Series[float]` | HDBSCAN per-entity cluster-membership strength |
| `feature_matrix` | `pd.DataFrame` | Entities × selected features, post-selection, pre-scaling |
| `embedding` | `pd.DataFrame` \| `None` | Reduction output; `None` when `reduction.method = "none"` |
| `metrics` | `dict` | Per [`05-evaluation.md`](05-evaluation.md) |
| `validation` | `ValidationReport` | Warnings raised, entities dropped |
| `config` | `Config` | Fully resolved config, defaults materialised |
| `run_dir` | `Path` \| `None` | Where artifacts were written; `None` when `output.persist = false` |
| `log_path` | `Path` | Where this run's log was written. Never `None` — the log is written even when `persist = false`, and a log the caller cannot locate is a log it does not have |

Every entity-indexed output carries the **input entity index**, including entities dropped by
`drop_entity` policies — dropped entities appear with label `pd.NA`, distinguishable from noise
(`-1`). Conflating "excluded from the run" with "clustered as noise" is a silent error that would
propagate straight into downstream analysis.

## Related specs

- [`00-product.md`](00-product.md) · [`02-pipeline.md`](02-pipeline.md) · [`03-config.md`](03-config.md)
- [`06-artifacts.md`](06-artifacts.md) — where warnings and dropped-entity records are persisted
- [`07-testing.md`](07-testing.md) — every `E0xx`/`W0xx` id above has a named test
