---
name: pipeline
status: draft
phase: 1
last-reviewed: 2026-09-27
---

# Pipeline Contract

A run, stage by stage. Each stage declares its input type, output type and failure modes; stages
communicate only through those types, never through shared mutable state.

```
wide DataFrame
   │
   ├─▶ 1. validate   ─▶ ValidationReport   (errors stop the run)
   ├─▶ 2. melt       ─▶ long DataFrame
   ├─▶ 3. extract    ─▶ raw feature matrix
   ├─▶ 4. clean      ─▶ finite feature matrix
   ├─▶ 5. select     ─▶ selected feature matrix
   ├─▶ 6. scale      ─▶ scaled matrix
   ├─▶ 7. reduce     ─▶ embedding
   ├─▶ 8. cluster    ─▶ labels + probabilities
   ├─▶ 9. evaluate   ─▶ metrics
   └─▶ 10. persist   ─▶ run directory + JSON summary
                          │
                          ▼
                     ClusterResult
```

## Orchestration

One config-driven entrypoint owns the sequence. Stage functions are individually importable and
testable, but the orchestrator is the only supported caller: it guarantees the seed is applied, the
manifest accumulates, and every stage's timing and row/column counts are recorded.

Each stage receives only its own config section, never the whole config, so it cannot develop
hidden dependencies on unrelated settings.

## 1. `validate`

| | |
|---|---|
| **In** | `pd.DataFrame` (wide), `pd.Series \| None` (target), `pd.Series \| None` (ground truth), `InputConfig`, `selection.method` |
| **Out** | `ValidationReport` |
| **Fails** | Any `E0xx` in [01 §3–4](01-data-contract.md) |

All errors are collected and raised together. Entities removed by `drop_entity` policies are
recorded by id in the report and carried through to the manifest and the final result.

`selection.method` is the one field validation needs from outside its own section: `E040` and
`W043` depend on it, and checking them here keeps every input error in the same up-front report.

## 2. `melt`

| | |
|---|---|
| **In** | validated wide `pd.DataFrame` |
| **Out** | long `pd.DataFrame[entity_id, timestep, value]` |
| **Fails** | Should not — input is validated. A failure here is a validation gap, not a melt bug |

Per [01 §5](01-data-contract.md): `timestep` is integer position, values are `float64`, sorted by
`(entity_id, timestep)`. Original column labels go to the manifest.

## 3. `extract`

| | |
|---|---|
| **In** | long `pd.DataFrame`, `FeaturesConfig` |
| **Out** | raw feature matrix — entities × features, may contain `NaN`/`±inf` |
| **Fails** | tsfresh raising; empty feature matrix |

Extraction sits behind an `Extractor` protocol from day one — the Phase 4 seam:

```python
class Extractor(Protocol):
    def extract(self, long_df: pd.DataFrame) -> pd.DataFrame: ...
    @property
    def name(self) -> str: ...
    @property
    def provenance(self) -> dict: ...   # goes into the manifest
```

`TsfreshExtractor` is the only Phase 1 implementation. The protocol exists now because retrofitting
it later would rewrite every downstream stage's assumptions about where features come from.

> Phase 4 — alternative extractors (catch22, shapelet, spectral, learned) implement this protocol.

The output index must equal the entity index exactly. An entity tsfresh silently drops is a bug to
raise, not a shorter matrix to accept.

## 4. `clean`

| | |
|---|---|
| **In** | raw feature matrix, `FeaturesConfig` |
| **Out** | finite feature matrix |
| **Fails** | `on_nonfinite = "error"` with non-finite present; dropped fraction exceeds `max_nonfinite_feature_fraction` |

A separate stage because non-finite handling is a correctness decision, not a tsfresh detail;
buried inside extraction it stops being visible or testable. The default drops offending feature
columns rather than imputing fabricated coordinates ([03 `features`](03-config.md)).

Always records: dropped feature names, counts, and the non-finite fraction per dropped column.

## 5. `select`

| | |
|---|---|
| **In** | finite feature matrix, `SelectionConfig`, optional target |
| **Out** | selected feature matrix |
| **Fails** | `supervised` without target (`E040`); selection empties the matrix |

Unsupervised path: variance filter, then correlation pruning with tie-breaks by column order, so
results are deterministic. Supervised path: tsfresh `select_features` at `fdr_level`.

If selection would return zero features, raise with the thresholds that caused it and the feature
count at each step — an empty matrix yields a confident, meaningless clustering.

Records: feature count before and after, and the retained feature names.

## 6. `scale`

| | |
|---|---|
| **In** | selected feature matrix, `ScalingConfig` |
| **Out** | scaled matrix, fitted scaler |
| **Fails** | Should not |

The stage returns the fitted scaler, but `ClusterResult` does not carry it: nothing in Phase 1
reads it.

> Phase 2 — transforming unseen entities needs the fitted scaler, reducer and clusterer;
> persisting fitted state is a Phase 2 item ([ROADMAP](../../ROADMAP.md)).

## 7. `reduce`

| | |
|---|---|
| **In** | scaled matrix, `ReductionConfig`, `seed` |
| **Out** | embedding `pd.DataFrame`, fitted reducer — or passthrough when `method = "none"` |
| **Fails** | `n_components` exceeding available features or entities |

`random_state` is always set from `seed`. For UMAP this forces single-threaded optimisation, and
umap-learn warns about the override; the warning is expected and not suppressed, because a
suppressed one is indistinguishable from a reproducibility bug.

Records: method, resolved `n_components`, and for PCA the explained-variance ratio.

## 8. `cluster`

| | |
|---|---|
| **In** | embedding, `ClusteringConfig` — no `seed`: HDBSCAN is deterministic ([03](03-config.md)) |
| **Out** | labels, probabilities, fitted clusterer |
| **Fails** | Should not. Zero clusters found is a valid result, reported as warning `W101` |

### Implementation decision: standalone `hdbscan`, not `sklearn.cluster.HDBSCAN`

scikit-learn's HDBSCAN would add no dependency, but only the standalone package has:

1. **`relative_validity_`** — the DBCV-style primary cluster-quality score in
   [05](05-evaluation.md). The alternative, silhouette, assumes convex, similarly sized clusters
   and so penalises exactly the non-convex shapes density clustering exists to find.
2. **`approximate_predict`** — required by Phase 2 entity segmentation.
3. **Soft membership vectors** — Phase 2.

Taking it now avoids a mid-roadmap migration touching evaluation, persistence and every test
threshold. A thin adapter — the only module that imports `hdbscan` — keeps the decision reversible.

`gen_min_span_tree=True` is required for `relative_validity_`: the adapter rejects a config that
disables it while requesting that metric, rather than returning an absent score.

## 9. `evaluate`

| | |
|---|---|
| **In** | embedding, labels, fitted clusterer, optional ground truth ([01 §4.2](01-data-contract.md)), `EvaluationConfig` |
| **Out** | `dict` of metrics |
| **Fails** | Requesting an external metric without ground truth |

The orchestrator requests external metrics only when ground truth is supplied
([03 `evaluation`](03-config.md)), so that failure guards direct calls to the stage.

Noise is excluded from internal metric computation but always reported as `noise_fraction`. A high
noise fraction records warning `W102`, never an error.

## 10. `persist`

| | |
|---|---|
| **In** | everything accumulated, `OutputConfig` |
| **Out** | run directory path, or `None` when `persist = false` |
| **Fails** | Unwritable `output.root`, `output.run_dir` or `output.log_dir` — all checked before stage 1, not after the expensive work |

Skipped when `persist = false`, except that the run's log file is opened before stage 1 and kept
either way ([06 §5](06-artifacts.md)). Layout: [06](06-artifacts.md).

## Cross-cutting

### Failure philosophy

Raise early, raise specifically, raise once. An error names the stage, the responsible config field
where one exists, and the remedy. No stage catches another stage's exception to continue with a
fallback — that would ship a result nobody chose.

### The manifest accumulates

Each stage appends to a manifest built up across the run: duration, input and output shapes, and
decisions taken (features dropped, entities removed, components retained). It is written even when
a later stage fails, so a failed run is still diagnosable from disk.

### Runtime warnings

Validation ids (`E0xx`/`W0xx`) are defined in [01 §3–4](01-data-contract.md). Warnings raised by
later stages are numbered from `W101`:

| ID | Stage | Raised when |
|---|---|---|
| `W101` | 8. `cluster` | Zero clusters found — a valid result, not an error |
| `W102` | 9. `evaluate` | `noise_fraction` exceeds `evaluation.noise_fraction_warn_above` |

Like validation warnings, they go to the manifest and to `summary.json` `warnings`, never raise, and
carry ids so the log-vs-summary test can match them ([07 §1](07-testing.md)). Each is tested with
its own stage, not on stage 1's rule→test ladder.

### Logging vs. recording

Log lines are for humans watching a run; the manifest is the record. The primary caller reads
results from disk after the process has exited and never sees the stream, so anything it might need
goes in the manifest.

The log is still persisted — `<output.log_dir>/<run_name>.log`, copied into the run directory as
`run.log` ([06 §5](06-artifacts.md)) — because a durable log makes failed and exploratory runs
diagnosable afterwards. That does not make it a record. **Nothing may live only in the log:** every
warning and every decision in it also appears in the manifest or the summary. A durable file
invites recording findings there; this rule is what forbids it.

### Module layout

```
src/ts_cluster/
  config.py          contracts.py       validation.py      reshape.py
  features/          __init__.py  (Extractor protocol)
                     tsfresh_extractor.py
  cleaning.py        selection.py       scaling.py         reduction.py
  clustering.py      (hdbscan adapter — sole importer of `hdbscan`)
  evaluation.py      artifacts.py       pipeline.py        (orchestrator)
  simulate/          processes.py       datasets.py
```
