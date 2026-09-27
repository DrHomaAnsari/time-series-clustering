---
name: data-contract
status: draft
phase: 1
last-reviewed: 2026-09-27
---

# Data Contract

What a run accepts and returns. Everything downstream relies on these guarantees, so this stage
validates and refuses — it never repairs. Terms are as defined in the glossary,
[00 §9](00-product.md).

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

Wide format implies a shared time index — every entity is observed at the same timesteps — and that
is a real constraint (§3.2).

### 1.1 Integer widening

Integer values are widened to `float64` before processing: lossless for the magnitudes in scope,
and the only implicit conversion permitted anywhere in the pipeline. Record it in the manifest; do
not extend the exception to other dtypes.

## 2. Validation model

Validation produces a `ValidationReport` with two disjoint severities:

- **Error** — the run stops. Nothing downstream may assume anything about the offending data.
- **Warning** — the run proceeds, and the warning is written into the run manifest
  ([06](06-artifacts.md)). Warnings are artifacts, not log lines: one that exists only in a log
  stream is lost the moment an agent reads results from disk.

All errors are collected and reported together, so an agent never fixes input one error per
round-trip. Every error message states what was expected, what was received (offending entity ids,
truncated to the first 10 plus a count), and what to do about it.

## 3. Validation rules

Each rule has a stable id, shared by tests, error messages and the manifest.

### 3.1 Structural

| ID | Rule | Severity |
|---|---|---|
| `E001` | Input is a `pandas.DataFrame` | Error |
| `E002` | Index values are unique | Error |
| `E003` | Index contains no nulls | Error |
| `E004` | Index dtype is `int*` or `str`/`object`-of-`str` | Error |
| `E005` | Columns are **not** a `MultiIndex` — multivariate input is rejected, not flattened | Error |
| `E006` | All value dtypes are numeric; `bool` and `object` are rejected | Error |

`E005` makes multivariate input fail loudly instead of being silently reinterpreted as extra
timesteps. Phase 1 is univariate; multivariate is deferred indefinitely
([ROADMAP](../../ROADMAP.md)).

### 3.2 Time axis

| ID | Rule | Severity |
|---|---|---|
| `E010` | Column labels are numeric or datetime — **string column labels are rejected** | Error |
| `E011` | Column labels are strictly monotonically increasing | Error |
| `E012` | Sampling is regular: successive column deltas are constant | Error |

`E010` is deliberately strict: string labels make time order unverifiable, and an out-of-order time
axis silently corrupts every order-dependent feature tsfresh computes. Users with string labels
convert them before calling.

`E012` enforces the Phase 1 precondition that input is already regularly sampled. Two escapes:

- `input.assume_regular = true` skips the check and records the user's assertion in the manifest —
  for spacing that is semantically regular but not numerically constant (month-ends, trading days).
- `input.regularity_tolerance` permits bounded jitter in the deltas.

> Phase 3 — the resampling module attaches here, and will prompt for an explicit resampling policy
> rather than choose one. Until then `E012` is an error, never a silent resample.

### 3.3 Values

| ID | Rule | Severity |
|---|---|---|
| `E020` | No `NaN` in values, subject to `input.on_nan` | Error (configurable) |
| `E021` | No `±inf` in values | Error |
| `E022` | No constant (zero-variance) series, subject to `input.on_constant_series` | Error (configurable) |

`E020` — `NaN` in a wide frame usually means entities with unequal coverage padded to a common
index, and tsfresh features computed over that padding are not comparable across entities.
`input.on_nan = "drop_entity"` removes offending entities and records their ids in the manifest;
there is no impute option at the input stage.

`E022` — constant series make many tsfresh features undefined: `skewness`, `kurtosis` and every
ratio with a standard-deviation denominator return `NaN` or `±inf`. A stuck sensor is legitimate,
often interesting data, so the handling must be an explicit choice: error, or `"drop_entity"` with
the ids recorded.

### 3.4 Size

| ID | Rule | Severity | Default |
|---|---|---|---|
| `E030` | Series length ≥ `input.min_series_length` | Error | 16 |
| `W031` | Series length < 50 | Warning | — |
| `E032` | Entity count ≥ `input.min_entities` | Error | 10 |
| `W033` | Entity count < 50 | Warning | — |

Below ~16 timesteps much of the tsfresh catalogue is undefined or degenerate (autocorrelation and
partial-autocorrelation lags run to 9; `agg_linear_trend` chunks at 5/10/50). Below ~10 entities,
density clustering with the default `min_cluster_size` of 5 cannot produce a meaningful partition.
The warnings mark where results become unreliable rather than impossible.

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
> known cluster memberships leaks the answer into feature selection and invalidates every metric in
> [05](05-evaluation.md); a target built from clustering output is always a bug.

| ID | Rule | Severity |
|---|---|---|
| `E040` | Target supplied when `selection.method = "supervised"` | Error |
| `E041` | Target index matches the entity index exactly (as a set) | Error |
| `E042` | Target contains no nulls | Error |
| `W043` | Target is ignored — with a warning — when `selection.method != "supervised"` | Warning |

`W043` warns instead of ignoring silently, because a target that has no effect almost always means
the caller misunderstands what selection does.

## 5. Internal representation — the melt

tsfresh consumes long format, so validated wide input is melted immediately. The details are
load-bearing, hence part of the contract.

| Long column | Name | Content |
|---|---|---|
| id | `entity_id` | Entity index value |
| sort | `timestep` | **Integer position** of the column, 0-based |
| value | `value` | `float64` |

Column names are module constants (`ENTITY_COLUMN`, `TIME_COLUMN`, `VALUE_COLUMN`), never string
literals at call sites.

The sort column is integer position, not the original column label: tsfresh uses `column_sort`
only to order observations, and positional integers make that exact and dtype-independent, with no
datetime-vs-numeric comparison edge cases. Original column labels are kept in the run manifest, not
in the long frame.

Guarantees after melting: sorted by `(entity_id, timestep)`; row count exactly
`n_entities × n_timesteps`; no nulls.

## 6. Output contract

A run returns a `ClusterResult`:

| Attribute | Type | Content |
|---|---|---|
| `labels` | `pd.Series[int]` | Cluster assignment per entity, indexed by entity id. `-1` is noise |
| `probabilities` | `pd.Series[float]` | HDBSCAN per-entity cluster-membership strength |
| `feature_matrix` | `pd.DataFrame` | Entities × selected features, post-selection, pre-scaling |
| `embedding` | `pd.DataFrame` \| `None` | Reduction output; `None` when `reduction.method = "none"` |
| `metrics` | `dict` | Per [05](05-evaluation.md) |
| `validation` | `ValidationReport` | Warnings raised, entities dropped |
| `config` | `Config` | Fully resolved config, defaults materialised |
| `run_dir` | `Path` \| `None` | Where artifacts were written; `None` when `output.persist = false` |
| `log_path` | `Path` | Where this run's log was written. Never `None` — the log is written even when `persist = false`, and a log the caller cannot locate is a log it does not have |

Every entity-indexed output carries the full input entity index. Entities dropped by `drop_entity`
policies get label `pd.NA`, never `-1`: conflating "excluded from the run" with "clustered as noise"
is a silent error that propagates straight into downstream analysis.
