---
name: artifacts
status: draft
phase: 1
last-reviewed: 2026-09-26
---

# Run Artifacts

What a run leaves on disk. This spec carries unusual weight because the primary caller is an
agent that **reads results after the process has exited** — it never saw stdout, holds no
in-memory objects, and cannot ask a follow-up question by re-running a twenty-minute extraction.
Anything not written here is effectively lost.

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

Every path is resolved under the single `output.root`, which is relative to the working directory
by default and so lands inside the repo. The default root is gitignored: generated output is
reproducible from a config and a seed, and committing it would put binaries in git that
[`07-testing.md` §4](07-testing.md) exists to keep out. A caller wanting results outside the repo
sets an absolute `output.root` and changes nothing else.

`run_name` defaults to `{timestamp}-{config_hash[:8]}`, e.g. `20260919T143022Z-a1b2c3d4`. UTC,
ISO-8601 basic format: sorts chronologically as text, and the hash suffix makes two runs of the
same config in the same second distinguishable.

## 2. Atomic writes

Write to a sibling temporary directory, then `rename` into place. A directory at its final path is
**always complete**.

Without this, a run interrupted mid-write leaves a directory that looks finished, and an agent
reading it gets a truncated `labels.parquet` with no indication anything is wrong.

**The log is the one thing that cannot obey this rule.** A log is only useful while the run is
still going, and a file inside a not-yet-renamed staging directory is not visible to anyone
watching. So the live log is written to `<output.log_dir>/<run_name>.log`, outside the run
directory, and a finished copy is placed inside the run directory as `run.log` at persist time.
The cost is one duplicated file; the alternatives are a log nobody can tail, or a run directory
that appears complete before it is.

## 3. `summary.json` — the agent surface

The most important artifact. Designed to be read **in full** to answer follow-up questions
without loading a single parquet file or re-running anything. Small by construction: a few KB
regardless of dataset size, so nothing in it scales with entity or feature count.

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

Digests are elided with `...` above for readability; real summaries carry full 64-character
hex, as `schemas/run_summary.schema.json` enforces.

Design rules, each protecting against a specific failure:

- **`status`** is `"completed"` or `"failed"`. A failed run still writes a summary, with `error`
  populated and stages that never ran set to `null`. A failed run that writes nothing is
  undiagnosable without re-running the thing that failed.
- **Absent is explicit.** `"external": null` means not applicable. A missing key would be
  ambiguous between "not computed" and "computed as nothing".
- **`schema_version`** is present from v1. Consumers that must tolerate evolution need a version
  to branch on, and retrofitting one means every existing artifact is unversioned forever.
- **`resolved_params`** inlines the full config so the summary is self-contained. `config.yaml` is
  the human-editable copy; `summary.json` is the record of what actually ran.
- **`fingerprint`** is `sha256` over index, column labels, and values. Answers "is this the same
  data as last run?" without loading the input.
- **Cluster sizes are keyed by label as a string**, since JSON object keys are strings. `-1` is not
  included here — it is `noise_fraction`, reported once and unambiguously.

Contract: `schemas/run_summary.schema.json`. Every emitted summary is validated against it before
being written, in production code and not only in tests — an artifact that violates its own schema
is worse than no artifact.

## 4. `manifest.json` — full provenance

Everything needed to explain or reproduce a run. Unbounded in size; not the agent's first read.

| Section | Contents |
|---|---|
| `environment` | Python version, platform, and versions of `ts_cluster`, tsfresh, scikit-learn, hdbscan, umap-learn, numpy, pandas |
| `config` | Fully resolved config and its hash |
| `seed` | The seed, and per-stage `random_state` values as actually applied |
| `input` | Entity count, timestep count, fingerprint, **original column labels** (dropped during the melt, per [`01-data-contract.md` §5](01-data-contract.md)) |
| `validation` | Every warning raised; ids of entities dropped and the rule that dropped them |
| `stages` | Per stage: duration, input shape, output shape, decisions taken |
| `decisions` | Dropped feature names and their non-finite fractions; features retained after selection; PCA explained variance; user assertions such as `assume_regular` |
| `status` | `completed` / `failed`, plus traceback on failure |

Library versions are recorded because this stack's numerics move between releases. A result that
cannot be reproduced six months later is not reproducible, and without versions there is no way to
tell a real regression from a dependency bump.

The manifest **accumulates during the run** and is written even when a stage raises, so a failed
run remains diagnosable from disk.

## 5. `run.log` — the human trace

One file per run, named for the run: `<output.log_dir>/<run_name>.log`. Opened **before stage 1**
and appended as the run proceeds, so it can be tailed while a twenty-minute extraction works. The
same lines go to the stream at `output.log_level`.

Contents are a narrative of execution: stage entry and exit, durations, input and output shapes,
the config hash, and any warning as it is raised.

> **Nothing may live only in the log.** Every warning, decision, and result recorded in the log is
> *also* in `manifest.json` or `summary.json`. The log is a convenience for a human watching; the
> manifest is the record. See [`02-pipeline.md` § Logging vs. recording](02-pipeline.md).

This is the rule that makes a persisted log safe to add. Without it, the log becomes the easiest
place to put a finding, and the primary caller — an agent reading `summary.json` after the process
exited — never sees it. A durable log file makes that mistake *more* tempting than an ephemeral
stream does, not less.

| Situation | Behaviour |
|---|---|
| Normal run | Live log at `<output.log_dir>/<run_name>.log`; copied into the run directory as `run.log` at persist time |
| `persist = false` | Live log still written. Nothing is copied, because there is no run directory |
| Run fails | Log is closed and retained, and still copied in if the run directory was written. A failed run's log is the most valuable one |
| Colliding `<run_name>.log` | Raises, like a colliding run directory. Nothing is ever appended to a previous run's log |

## 6. Writing rules

- Parquet for tabular artifacts — lossless dtypes and column labels, unlike CSV.
- `labels.parquet` carries the **full input entity index**, including dropped entities with label
  `pd.NA`. Distinguishing "excluded from the run" from "clustered as noise" (`-1`) is the point;
  collapsing them corrupts downstream analysis silently.
- `output.persist = false` writes **no run directory** — not a partial one, not an empty one. The
  per-run log file is the sole exception and is still written; see §5.
- **`output.root`, `output.log_dir` and `output.run_dir` are all checked for writability before
  stage 1**, and the log file is opened there and then. Discovering an unwritable directory after a
  twenty-minute extraction is a spec failure, not an unlucky run — and that applies to the log
  path too, which is now on the critical path.
- Nothing is ever overwritten. A colliding `run_name` raises, and so does a colliding log file.

## 7. Retention

No automatic cleanup in Phase 1. Run directories accumulate and deleting them is the user's
decision — a library that quietly removes prior results is a library that loses someone's work.

> Phase 7 — the plugin surface will need run discovery and listing; `summary.json` is shaped to be
> the index for it.

## Related specs

- [`03-config.md`](03-config.md) — `output.*` fields
- [`01-data-contract.md`](01-data-contract.md) — entity index and `pd.NA` convention
- [`05-evaluation.md`](05-evaluation.md) — metric contents
- `schemas/run_summary.schema.json` — hand-authored contract for §3
