# Backlog

Build order and progress for the current phase. The specs say *what*; this says *in what order*
and *how far*. Each stage expands into steps when its decision gate is approved — until then it
carries a single placeholder box. One box is one `/step` is one commit.

Claude ticks a box in the same commit as the code it describes, expands a stage only at its
approved gate, and appends to Parked. Nothing else: reordering, deleting and re-scoping are Homa's.
`git log -p BACKLOG.md` is the history of progress.

## Phase 1

### 0 · Scaffolding — [`ROADMAP.md`](ROADMAP.md) Phase 1 scope
- [ ] Expands at gate

### 1 · Validation — [`01-data-contract.md`](docs/specs/01-data-contract.md) §3, laddered by [`07-testing.md`](docs/specs/07-testing.md) §1
- [ ] Expands at gate

### 2 · Simulation — [`04-simulation.md`](docs/specs/04-simulation.md)
- [ ] Expands at gate

### 3 · Config core — [`03-config.md`](docs/specs/03-config.md): root model, hash, YAML/JSON round-trip
- [ ] Expands at gate

### 4 · Reshape — [`02-pipeline.md`](docs/specs/02-pipeline.md) §2
- [ ] Expands at gate

### 5 · Features — [`02-pipeline.md`](docs/specs/02-pipeline.md) §3–4: extractor protocol, tsfresh, cleaning
- [ ] Expands at gate

### 6 · Selection — [`02-pipeline.md`](docs/specs/02-pipeline.md) §5
- [ ] Expands at gate

### 7 · Scaling — [`02-pipeline.md`](docs/specs/02-pipeline.md) §6
- [ ] Expands at gate

### 8 · Reduction — [`02-pipeline.md`](docs/specs/02-pipeline.md) §7: PCA, UMAP
- [ ] Expands at gate

### 9 · Clustering — [`02-pipeline.md`](docs/specs/02-pipeline.md) §8
- [ ] Expands at gate

### 10 · Evaluation — [`02-pipeline.md`](docs/specs/02-pipeline.md) §9, [`05-evaluation.md`](docs/specs/05-evaluation.md)
- [ ] Expands at gate

### 11 · Artifacts and logging — [`06-artifacts.md`](docs/specs/06-artifacts.md), [`02-pipeline.md`](docs/specs/02-pipeline.md) §10
- [ ] Expands at gate

### 12 · Orchestrator — [`02-pipeline.md`](docs/specs/02-pipeline.md) § Orchestration
- [ ] Expands at gate

### 13 · Ground truth, determinism, calibration — [`07-testing.md`](docs/specs/07-testing.md) §2–3, [`05-evaluation.md`](docs/specs/05-evaluation.md) §5
- [ ] Expands at gate

### 14 · README walkthrough and example notebook — [`00-product.md`](docs/specs/00-product.md) §7
- [ ] Expands at gate

## Parked

Found mid-step and deliberately not done now. Items that belong to a later phase are tagged
`→ Phase N`; Homa moves them to [`ROADMAP.md`](ROADMAP.md).

Spec inconsistencies found in the 2026-09-27 style pass, by the stage whose gate they block:

- **Stage 1** — `07` §1 says each rule maps to "exactly one" named test, but `E012`, `E020` and `E022` have two each.
- **Stage 9** — `02` §8 passes `seed` to `cluster`, but HDBSCAN is deterministic and takes no seed (`03` § Determinism): an unused input.
- **Stage 9** — runtime warnings have no ids: zero clusters (`02` §8) and high noise fraction (`05` §6) are manifest warnings, but the summary schema requires `id` matching `^W[0-9]{3}$` and only `W031`/`W033`/`W043` exist.
- **Stage 10** — `05` §3 gives `ami` the range [0, 1]; `run_summary.schema.json` allows [-1, 1]. AMI can be negative, so the spec is the one that is off.
- **Stage 10** — `cluster_size_distribution` (min/median/max/counts, `05` §2, a default in `03` `evaluation.internal_metrics`) has no slot in `summary.json`, which carries only `clustering.cluster_sizes`.
- **Stage 10** — ground truth has no input contract: `02` §9 and `03` `external_metrics` consume it, but `01` defines no argument or validation for it, unlike the target.
- **Stage 11** — `06` §1: the hash suffix cannot separate two runs of the *same* config in the same second — they share the hash and collide (§6). It separates different configs.
- **Stage 11** — `06` §3's example gives `W031` an `entity_count` of 3, but series length is shared by every entity in a wide frame, so `W031` is dataset-wide.
- **Stage 12** — `01` §6 types `labels` as `pd.Series[int]`, yet dropped entities carry `pd.NA`: that needs nullable `Int64`, or reindexing silently upcasts labels to float.
- **Stage 12** — `02` §6 retains the fitted scaler "on the result", but `ClusterResult` (`01` §6) has no field for it.
- **ROADMAP** — Phase 2's "Soft cluster membership probabilities" reads like Phase 1's `ClusterResult.probabilities`; `02` §8 calls the Phase 2 item "soft membership vectors". Under Rule 6 an agent could wrongly defer `probabilities`.
- **ROADMAP** — the Phase 1 pipeline line omits `clean` (`02` stage 4).
