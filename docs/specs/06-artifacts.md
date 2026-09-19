---
name: artifacts
status: draft
phase: 1
last-reviewed: 2026-09-19
---

# Run Artifacts

What a run leaves on disk. This spec carries unusual weight because the primary caller is an
agent that **reads results after the process has exited** — it never saw stdout, holds no
in-memory objects, and cannot ask a follow-up question by re-running a twenty-minute extraction.
Anything not written here is effectively lost.

## 1. Layout

```
<output.run_dir>/
  <run_name>/
    config.yaml          # fully resolved config — defaults materialised
    manifest.json        # complete provenance and per-stage record
    summary.json         # compact, agent-readable  ← read this first
    labels.parquet       # entity_id → label, probability
    features.parquet     # selected feature matrix      (optional)
    embedding.parquet    # reduction output             (optional)
```

`run_name` defaults to `{timestamp}-{config_hash[:8]}`, e.g. `20260919T143022Z-a1b2c3d4`. UTC,
ISO-8601 basic format: sorts chronologically as text, and the hash suffix makes two runs of the
same config in the same second distinguishable.

## 2. Atomic writes

Write to a sibling temporary directory, then `rename` into place. A directory at its final path is
**always complete**.

Without this, a run interrupted mid-write leaves a directory that looks finished, and an agent
reading it gets a truncated `labels.parquet` with no indication anything is wrong.

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

## 5. Writing rules

- Parquet for tabular artifacts — lossless dtypes and column labels, unlike CSV.
- `labels.parquet` carries the **full input entity index**, including dropped entities with label
  `pd.NA`. Distinguishing "excluded from the run" from "clustered as noise" (`-1`) is the point;
  collapsing them corrupts downstream analysis silently.
- `output.persist = false` writes nothing at all — no partial directory.
- Path writability is checked **before stage 1**. Discovering an unwritable directory after a
  twenty-minute extraction is a spec failure, not an unlucky run.
- Nothing is ever overwritten. A colliding `run_name` raises.

## 6. Retention

No automatic cleanup in Phase 1. Run directories accumulate and deleting them is the user's
decision — a library that quietly removes prior results is a library that loses someone's work.

> Phase 7 — the plugin surface will need run discovery and listing; `summary.json` is shaped to be
> the index for it.

## Related specs

- [`03-config.md`](03-config.md) — `output.*` fields
- [`01-data-contract.md`](01-data-contract.md) — entity index and `pd.NA` convention
- [`05-evaluation.md`](05-evaluation.md) — metric contents
- `schemas/run_summary.schema.json` — hand-authored contract for §3
