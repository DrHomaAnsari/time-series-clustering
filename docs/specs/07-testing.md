---
name: testing
status: draft
phase: 1
last-reviewed: 2026-09-27
---

# Test Strategy

Three layers. Each answers a different question; none substitutes for another.

| Layer | Question | Cost |
|---|---|---|
| **Contract / shape** | Does the API behave as specified? | Fast — runs on every save |
| **Synthetic ground truth** | Does the pipeline find the right answer? | Slow — the only correctness evidence |
| **Determinism** | Is the result reproducible? | Moderate |

A refactor that keeps contract tests green while ARI on `moderate` drops from 0.78 to 0.31 has
broken the product, and only layer 2 catches it.

## 1. Contract / shape tests

Fast: no clustering, no tsfresh. They protect the public API — the layer an agent is most likely to
break while changing something unrelated.

### Traceability — every rule has a test

Each id in [01 §3–4](01-data-contract.md) maps to at least one named test. This table is checked
mechanically: a rule without a test, or a test naming a rule that does not exist, fails the suite.

| Rule | Test |
|---|---|
| `E001` | `test_rejects_non_dataframe` |
| `E002` | `test_rejects_duplicate_entity_ids` |
| `E003` | `test_rejects_null_entity_ids` |
| `E004` | `test_rejects_invalid_index_dtype` |
| `E005` | `test_rejects_multiindex_columns` |
| `E006` | `test_rejects_non_numeric_values` |
| `E010` | `test_rejects_string_column_labels` |
| `E011` | `test_rejects_unordered_time_axis` |
| `E012` | `test_rejects_irregular_sampling` |
| `E012` | `test_assume_regular_skips_check_and_records_assertion` |
| `E020` | `test_rejects_nan_values` / `test_on_nan_drop_entity_records_ids` |
| `E021` | `test_rejects_infinite_values` |
| `E022` | `test_rejects_constant_series` / `test_on_constant_drop_entity_records_ids` |
| `E030` | `test_rejects_series_below_min_length` |
| `W031` | `test_warns_on_short_series` |
| `E032` | `test_rejects_too_few_entities` |
| `W033` | `test_warns_on_few_entities` |
| `E040` | `test_supervised_selection_requires_target` |
| `E041` | `test_rejects_target_index_mismatch` |
| `E042` | `test_rejects_null_target_values` |
| `W043` | `test_warns_when_target_ignored` |
| `E050` | `test_rejects_truth_index_mismatch` |
| `E051` | `test_rejects_null_truth_values` |
| `E052` | `test_rejects_invalid_truth_labels` |

### Beyond validation

| Area | Assertions |
|---|---|
| Errors | All errors collected and raised together, not one per round-trip; messages name expected, received and remedy; offending ids truncated at 10 with a total count |
| Config | `extra="forbid"` rejects unknown fields; out-of-range values rejected; YAML/JSON round-trip is lossless; hash is stable across runs and identical for explicit-vs-defaulted equivalents |
| Melt | Row count is `n_entities × n_timesteps`; sorted by `(entity_id, timestep)`; `timestep` is integer position, not the original label |
| Result | Entity-indexed outputs carry the full input index; dropped entities are `pd.NA`, never `-1`; `labels` has dtype `Int64` |
| Artifacts | `summary.json` validates against its schema; `status: failed` still writes a summary; colliding `run_name` raises; `persist=false` writes no run directory |
| Output paths | Relative `output.root` resolves against the working directory; absolute `root` is honoured; an absolute `run_dir`, `log_dir` or `dataset_dir` raises; `root`, `run_dir` and `log_dir` are checked for writability before stage 1, not after extraction |
| Logging | Log file appears at `<log_dir>/<run_name>.log`, opened before stage 1; copied into the run directory as `run.log` on persist; `persist=false` still writes it, copies nothing, and leaves `ClusterResult.log_path` pointing at it; a failed run retains it; a colliding log filename raises |
| Runtime warnings | `W101` when no clusters are found and `W102` when `noise_fraction` exceeds `evaluation.noise_fraction_warn_above` ([02 § Runtime warnings](02-pipeline.md)); each lands in `summary.json` `warnings`, and the run still completes |
| **Log is never the only record** | Every warning id that appears in the log also appears in `summary.json` `warnings` — the test that makes a persisted log safe to have ([02 § Logging vs. recording](02-pipeline.md)) |

## 2. Synthetic ground-truth tests

Run the full pipeline on [04](04-simulation.md) presets; assert against
[05 §4](05-evaluation.md). Each runs for both `pca` and `umap`.

| Test | Preset | Assertion |
|---|---|---|
| `test_recovers_easy_clusters` | `easy_separable` | `ari` ≥ threshold |
| `test_recovers_moderate_clusters` | `moderate` | `ari` ≥ threshold |
| `test_degrades_gracefully` | `hard_overlapping` | `ari` ≥ threshold; does not raise |
| `test_identifies_noise_entities` | `with_noise` | `ari` and `noise_recall` ≥ thresholds |
| `test_does_not_split_homogeneous_data` | `single_cluster` | `n_clusters` ≤ 1 |
| **`test_does_not_invent_structure`** | `no_structure` | `n_clusters == 0` or `noise_fraction` ≥ 0.80 |

The last two are the highest-value tests in the suite ([05 §4](05-evaluation.md)) and the two most
likely to be "fixed" by loosening. Treat a failure there as a finding, never as a threshold to
adjust.

`test_simulated_data_passes_validation` checks the simulator's own invariant: every preset
validates with zero errors and zero warnings ([04 §1](04-simulation.md)).

**Thresholds are provisional.** Until calibration ([05 §5](05-evaluation.md)) these tests are
marked `xfail(strict=False)` rather than asserting invented numbers; calibration removes the
marker. A suite that passes against fabricated thresholds is worse than one that is honestly
incomplete.

## 3. Determinism tests

| Test | Assertion |
|---|---|
| `test_same_seed_same_labels[pca]` | Two runs, one config — labels identical, not merely similar |
| `test_same_seed_same_labels[umap]` | Same, and the umap-learn single-thread override warning is observed rather than suppressed |
| `test_different_seed_may_differ` | Guards against a seed that is silently ignored |
| `test_config_hash_stable` | Equal configs hash equally across processes |
| `test_simulation_position_stable` | Entity *k*'s series is unchanged when another group is prepended to the spec — the `SeedSequence.spawn` guarantee from [04 §3](04-simulation.md) |

`test_simulation_position_stable` is subtle but essential: without it, editing a `DatasetSpec`
silently changes every previously calibrated dataset, and every threshold in
[05](05-evaluation.md) quietly stops meaning what it says.

## 4. Mechanics

- pytest, run with `uv run pytest`.
- Marker `slow` for anything running tsfresh or UMAP. `uv run pytest -m "not slow"` is the
  edit-loop suite and must stay genuinely fast.
- Tests never write to the default output root: every test sets `output.root` to pytest's
  `tmp_path`. A suite writing into the repo's own `./outputs` pollutes the tree it checks and leaves
  the gitignore as the only thing between a test run and a dirty diff.
- Fixtures are generated, not committed: presets are produced at fixed seeds in-test, with no
  parquet binaries in git. `spec.json` regenerates any dataset exactly.
- Contract tests build minimal frames inline — no tsfresh, no clustering.
- Every test's docstring names the rule or spec section it enforces; a test with an unclear purpose
  gets deleted in some future refactor.

## 5. Not in Phase 1

Named so their absence is a decision, not an oversight.

> Phase 2 — golden-file regression: snapshot labels and metrics for fixed inputs, fail on drift.
> Catches unintended numerical change from dependency bumps, which the ARI thresholds are too
> coarse to see. Deferred because blessing golden files against an uncalibrated pipeline locks in
> whatever it happens to do today.

> Phase 2 — property-based tests (Hypothesis): permuting entity order must not change assignments;
> scaling must be idempotent; label output must be invariant to entity id relabelling.

Not planned: performance benchmarks (Phase 8), real-dataset tests (no stable corpus), mutation
testing.
