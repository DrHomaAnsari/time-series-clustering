---
name: pipeline
status: draft
phase: 1
last-reviewed: 2026-09-26
---

# Pipeline Contract

Stage-by-stage definition of a run. Each stage has a declared input type, output type, and set of
failure modes; stages communicate only through those types, never through shared mutable state.

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
independently testable, but the orchestrator is the only supported caller — it guarantees the
seed is applied, the manifest accumulates, and every stage's timing and row/column counts are
recorded.

No stage may read the config wholesale. Each receives only its own section, so a stage cannot
develop hidden dependencies on unrelated settings.

---

## 1. `validate`

| | |
|---|---|
| **In** | `pd.DataFrame` (wide), `pd.Series \| None` (target), `InputConfig` |
| **Out** | `ValidationReport` |
| **Fails** | Any `E0xx` in [`01-data-contract.md` §3](01-data-contract.md) |

All errors are collected and raised together. Entities removed by `drop_entity` policies are
recorded by id in the report and carried through to the manifest and the final result.

---

## 2. `melt`

| | |
|---|---|
| **In** | validated wide `pd.DataFrame` |
| **Out** | long `pd.DataFrame[entity_id, timestep, value]` |
| **Fails** | Should not — operates on validated input. A failure here is a validation gap, not a melt bug |

Per [`01-data-contract.md` §5](01-data-contract.md): `timestep` is integer position, values are
`float64`, sorted by `(entity_id, timestep)`. Original column labels go to the manifest.

---

## 3. `extract`

| | |
|---|---|
| **In** | long `pd.DataFrame`, `FeaturesConfig` |
| **Out** | raw feature matrix — entities × features, may contain `NaN`/`±inf` |
| **Fails** | tsfresh raising; empty feature matrix |

### The Phase 4 seam

Extraction sits behind an `Extractor` protocol from day one:

```python
class Extractor(Protocol):
    def extract(self, long_df: pd.DataFrame) -> pd.DataFrame: ...
    @property
    def name(self) -> str: ...
    @property
    def provenance(self) -> dict: ...   # goes into the manifest
```

`TsfreshExtractor` is the only Phase 1 implementation. The protocol exists now because retrofitting
one later means rewriting every downstream stage's assumptions about where features come from —
cheap to decide today, expensive to discover in Phase 4.

> Phase 4 — alternative extractors (catch22, shapelet, spectral, learned) implement this protocol.

The output index must equal the entity index exactly. Any entity tsfresh silently drops is a bug
to raise, not a shorter matrix to accept.

---

## 4. `clean`

| | |
|---|---|
| **In** | raw feature matrix, `FeaturesConfig` |
| **Out** | finite feature matrix |
| **Fails** | `on_nonfinite = "error"` with non-finite present; dropped fraction exceeds `max_nonfinite_feature_fraction` |

A separate stage from extraction on purpose. Non-finite handling is a **decision about
correctness**, not an implementation detail of tsfresh, and burying it inside extraction is how it
stops being visible or testable. Per [`03-config.md`](03-config.md) the default drops offending
feature columns rather than imputing, because imputation fabricates coordinates that then shape
the clustering.

Always records: dropped feature names, counts, and the non-finite fraction per dropped column.

---

## 5. `select`

| | |
|---|---|
| **In** | finite feature matrix, `SelectionConfig`, optional target |
| **Out** | selected feature matrix |
| **Fails** | `supervised` without target (`E040`); selection empties the matrix |

Unsupervised path: variance filter, then correlation pruning with tie-breaks by column order so
results are deterministic. Supervised path: tsfresh `select_features` at `fdr_level`.

If selection would return zero features, raise with the thresholds that caused it and the feature
count at each step. Silently proceeding with an empty matrix produces a confident, meaningless
clustering.

Records: feature count before and after, and the retained feature names.

---

## 6. `scale`

| | |
|---|---|
| **In** | selected feature matrix, `ScalingConfig` |
| **Out** | scaled matrix, fitted scaler |
| **Fails** | Should not |

The fitted scaler is retained on the result. > Phase 2 — transforming unseen entities needs it.

---

## 7. `reduce`

| | |
|---|---|
| **In** | scaled matrix, `ReductionConfig`, `seed` |
| **Out** | embedding `pd.DataFrame`, fitted reducer — or passthrough when `method = "none"` |
| **Fails** | `n_components` exceeding available features or entities |

`random_state` is always set from `seed`. For UMAP this forces single-threaded optimisation and
umap-learn emits a warning about the override — expected, and not suppressed: a suppressed
warning here is indistinguishable from a reproducibility bug.

Records: method, resolved `n_components`, and for PCA the explained-variance ratio.

---

## 8. `cluster`

| | |
|---|---|
| **In** | embedding, `ClusteringConfig`, `seed` |
| **Out** | labels, probabilities, fitted clusterer |
| **Fails** | Should not. **Zero clusters found is a valid result**, reported with a manifest warning |

### Implementation decision: standalone `hdbscan`, not `sklearn.cluster.HDBSCAN`

scikit-learn ships HDBSCAN and is already a dependency, so choosing the standalone package needs
justification:

1. **`relative_validity_`** — the DBCV-style internal metric that is the primary cluster-quality
   score in [`05-evaluation.md`](05-evaluation.md) exists only in the standalone package. Without
   it the only alternative is silhouette, which assumes convex, similarly-sized clusters and
   systematically penalises exactly the non-convex shapes density clustering exists to find.
2. **`approximate_predict`** — required by Phase 2 entity segmentation, and absent from
   scikit-learn's implementation.
3. **Soft membership vectors** — Phase 2.

Taking the dependency now avoids a migration mid-roadmap that would touch evaluation, persistence,
and every test threshold. It sits behind a thin adapter so the decision stays reversible, and the
adapter is the only module importing `hdbscan` directly.

`gen_min_span_tree=True` is required for `relative_validity_`; the adapter must reject a config
that disables it while requesting that metric, rather than returning an absent score.

---

## 9. `evaluate`

| | |
|---|---|
| **In** | embedding, labels, fitted clusterer, optional ground truth, `EvaluationConfig` |
| **Out** | `dict` of metrics |
| **Fails** | Requesting an external metric without ground truth |

Noise is **excluded** from internal metric computation but **always reported** as
`noise_fraction`. A high noise fraction emits a manifest warning and never an error.

---

## 10. `persist`

| | |
|---|---|
| **In** | everything accumulated, `OutputConfig` |
| **Out** | run directory path, or `None` when `persist = false` |
| **Fails** | Unwritable `output.root`, `output.run_dir` or `output.log_dir` — all checked **before** stage 1, not after the expensive work |

Skipped when `persist = false`, with one exception: the run's log file is opened before stage 1 and
retained either way ([`06-artifacts.md` §5](06-artifacts.md)). Layout in
[`06-artifacts.md`](06-artifacts.md).

---

## Cross-cutting

### Failure philosophy

Raise early, raise specifically, raise once. Errors name the stage, the config field responsible
where one exists, and the remedy. No stage may catch an exception from another stage to continue
with a fallback — a fallback here means shipping a result nobody chose.

### The manifest accumulates

Each stage appends to a manifest built up across the run: duration, input and output shapes, and
any decisions taken (features dropped, entities removed, components retained). It is written even
when a later stage fails, so a failed run is still diagnosable from disk.

### Logging vs. recording

Log lines are for humans watching a run; the manifest is the record. **Anything a caller might
need afterwards is written to the manifest**, because the primary caller reads results from disk
after the process has exited and never sees the stream at all.

The log is nonetheless **persisted**, to `<output.log_dir>/<run_name>.log` and copied into the run
directory as `run.log` ([`06-artifacts.md` §5](06-artifacts.md)). Persisting it does not promote it
to a record. The division above is unchanged, and the rule that enforces it is absolute:
**nothing may live only in the log.** Every warning and every decision that appears in the log
also appears in the manifest or the summary.

This revises the original position, which kept the log ephemeral because a stream the agent never
reads is worthless. That was right about the stream and wrong about the file: a durable log is what
makes a failed or exploratory run diagnosable afterwards, which is why it survives
`persist = false`. The risk it introduces is real — a durable file looks like a safe place to
record a finding — and the "never only in the log" rule is what holds that line.

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

## Related specs

- [`01-data-contract.md`](01-data-contract.md) · [`03-config.md`](03-config.md)
- [`04-simulation.md`](04-simulation.md) · [`05-evaluation.md`](05-evaluation.md)
- [`06-artifacts.md`](06-artifacts.md) · [`07-testing.md`](07-testing.md)
