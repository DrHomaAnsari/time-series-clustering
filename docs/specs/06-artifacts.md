---
name: artifacts
status: draft
phase: 1
last-reviewed: 2026-09-27
---

# Run Artifacts

What a run leaves on disk. The primary caller reads results after the process has exited: it never
saw stdout, holds no in-memory objects, and cannot ask a follow-up by re-running a twenty-minute
extraction. Anything not written here is effectively lost.

## 1. Layout

```
<output.root>/                  # default ./outputs — inside the repo, gitignored
  <output.run_dir>/             # default runs
    <run_name>/
      config.yaml        # fully resolved config — defaults materialised
      manifest.json      # complete provenance and per-stage record
      summary.json       # compact, agent-readable  ← read this first
      labels.parquet     # entity_id → label, probability
      features.parquet   # selected feature matrix      (optional)
      embedding.parquet  # reduction output             (optional)
      run.log            # copy of this run's log, written last
  <output.log_dir>/             # default logs
    <run_name>.log       # the live log — appended while the run works
  <output.dataset_dir>/         # default datasets — see 04-simulation.md
```

Every path resolves under the single `output.root` ([03 `output`](03-config.md)). The default root
is gitignored because output is reproducible from a config and a seed, and committing it would put
binaries in git that [07 §4](07-testing.md) exists to keep out.

`run_name` defaults to `{timestamp}-{config_hash[:8]}`, e.g. `20260919T143022Z-a1b2c3d4`. UTC in
ISO-8601 basic format sorts chronologically as text, and the hash suffix makes two runs of the same
config in the same second distinguishable.

## 2. Atomic writes

Write to a sibling temporary directory, then `rename` it into place, so a directory at its final
path is always complete. Otherwise an interrupted run leaves a directory that looks finished, and
an agent reads a truncated `labels.parquet` with no sign anything is wrong.

The log is the one exception: it is useful only while the run is still going, and a file in a
not-yet-renamed staging directory is invisible to anyone watching. So the live log goes to
`<output.log_dir>/<run_name>.log`, outside the run directory, and a finished copy lands in the run
directory as `run.log` at persist time — one duplicated file, instead of a log nobody can tail or a
run directory that appears complete before it is.

## 3. `summary.json` — the agent surface

The most important artifact, designed to be read in full: it answers follow-up questions without
loading a parquet file or re-running anything. A few KB regardless of dataset size — nothing in it
scales with entity or feature count.

```json
{
  "schema_version": "1.0",
  "run_name": "20260919T143022Z-a1b2c3d4",
  "status": "completed",
  "created_at": "2026-09-19T14:30:22Z",
  "duration_seconds": 42.7,
  "config_hash": "a1b2c3d4...",
  "input": {
    "n_entities": 300,
    "n_timesteps": 128,
    "fingerprint": "sha256:9f86d0..."
  },
  "pipeline": {
    "features_extracted": 783,
    "features_after_cleaning": 771,
    "features_after_selection": 94,
    "reduction_method": "pca",
    "n_components": 12
  },
  "clustering": {
    "n_clusters": 4,
    "noise_fraction": 0.07,
    "cluster_sizes": {"0": 84, "1": 79, "2": 68, "3": 48},
    "n_entities_dropped": 0
  },
  "metrics": {
    "internal": {"relative_validity": 0.41},
    "external": null
  },
  "warnings": [
    {"id": "W031", "message": "...", "entity_count": 3}
  ],
  "resolved_params": {"...": "the config, inlined"}
}
```

Digests are elided with `...` for readability; real summaries carry full 64-character hex, as
`schemas/run_summary.schema.json` enforces.

Design rules, each guarding against a specific failure:

- **`status`** is `"completed"` or `"failed"`. A failed run still writes a summary, with `error`
  populated and stages that never ran set to `null`; otherwise it is undiagnosable without
  re-running the thing that failed.
- **Absent is explicit.** `"external": null` means not applicable; a missing key would be ambiguous
  between "not computed" and "computed as nothing".
- **`schema_version`** is present from v1, so consumers have a version to branch on as the schema
  evolves. Retrofitting one leaves every existing artifact unversioned forever.
- **`resolved_params`** inlines the full config so the summary is self-contained. `config.yaml` is
  the human-editable copy; `summary.json` records what actually ran.
- **`fingerprint`** is `sha256` over index, column labels and values: "is this the same data as
  last run?" without loading the input.
- **Cluster sizes are keyed by label as a string**, since JSON object keys are strings. `-1` is
  excluded — it is `noise_fraction`, reported once and unambiguously.

Contract: `schemas/run_summary.schema.json`. Every summary is validated against it before being
written, in production code and not only in tests — an artifact that violates its own schema is
worse than none.

## 4. `manifest.json` — full provenance

Everything needed to explain or reproduce a run. Unbounded in size; not the agent's first read.

| Section | Contents |
|---|---|
| `environment` | Python version, platform, and versions of `ts_cluster`, tsfresh, scikit-learn, hdbscan, umap-learn, numpy, pandas |
| `config` | Fully resolved config and its hash |
| `seed` | The seed, and per-stage `random_state` values as actually applied |
| `input` | Entity count, timestep count, fingerprint, original column labels (dropped during the melt, per [01 §5](01-data-contract.md)) |
| `validation` | Every warning raised; ids of entities dropped and the rule that dropped them |
| `stages` | Per stage: duration, input shape, output shape, decisions taken |
| `decisions` | Dropped feature names and their non-finite fractions; features retained after selection; PCA explained variance; user assertions such as `assume_regular` |
| `status` | `completed` / `failed`, plus traceback on failure |

Library versions are recorded because this stack's numerics move between releases: without them a
real regression is indistinguishable from a dependency bump, and a result not reproducible six
months later is not reproducible.

The manifest accumulates during the run and is written even when a stage raises
([02 § Cross-cutting](02-pipeline.md)).

## 5. `run.log` — the human trace

One file per run, `<output.log_dir>/<run_name>.log`, opened before stage 1 and appended as the run
proceeds, so it can be tailed while a twenty-minute extraction works. The same lines go to the
stream at `output.log_level`. It narrates execution: stage entry and exit, durations, input and
output shapes, the config hash, and each warning as it is raised.

**Nothing may live only in the log.** Every warning, decision and result in it is also in
`manifest.json` or `summary.json`; the rule and its reason are in
[02 § Logging vs. recording](02-pipeline.md).

| Situation | Behaviour |
|---|---|
| Normal run | Live log at `<output.log_dir>/<run_name>.log`; copied into the run directory as `run.log` at persist time |
| `persist = false` | Live log still written. Nothing is copied, because there is no run directory |
| Run fails | Log is closed and retained, and still copied in if the run directory was written. A failed run's log is the most valuable one |
| Colliding `<run_name>.log` | Raises, like a colliding run directory. Nothing is ever appended to a previous run's log |

**Why the log survives `persist = false`.** That setting is for exploratory runs nobody wants to
keep — exactly the runs that misbehave, when a diagnostic trace is the one thing worth having. The
log is small, bounded by the run's duration, and costs nothing to keep. The exception stays narrow
because the log carries no results: anything a caller needs is in the manifest and summary, which
`persist = false` genuinely does not write.

## 6. Writing rules

- Parquet for tabular artifacts — lossless dtypes and column labels, unlike CSV.
- `labels.parquet` carries the full input entity index, dropped entities labelled `pd.NA`
  ([01 §6](01-data-contract.md)), so "excluded from the run" never collapses into "clustered as
  noise" (`-1`).
- `output.persist = false` writes no run directory — not a partial one, not an empty one. The
  per-run log file is the sole exception (§5).
- `output.root`, `output.log_dir` and `output.run_dir` are all checked for writability before
  stage 1, and the log file is opened then. Discovering an unwritable directory after a
  twenty-minute extraction is a spec failure, not an unlucky run — and the log path is on that
  critical path too.
- Nothing is ever overwritten. A colliding `run_name` raises, and so does a colliding log file.

## 7. Retention

No automatic cleanup in Phase 1. Run directories accumulate; deleting them is the user's decision,
because a library that quietly removes prior results loses someone's work.

> Phase 7 — the plugin surface will need run discovery and listing; `summary.json` is shaped to be
> the index for it.
