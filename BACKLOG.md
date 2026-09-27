# Backlog

Build order and progress for the current phase. The specs say *what*; this says *in what order*
and *how far*. Each stage expands into steps when its decision gate is approved — until then it
carries a single placeholder box. One box is one `/step` is one commit.

Claude ticks a box in the same commit as the code it describes, expands a stage only at its
approved gate, and appends to Parked. Nothing else: reordering, deleting and re-scoping are Homa's.
`git log -p BACKLOG.md` is the history of progress.

## Phase 1

### 0 · Scaffolding — [`ROADMAP.md`](ROADMAP.md) Phase 1 scope; [`tech-stack.md`](docs/specs/tech-stack.md) § Open
- [ ] Expands at gate

### 1 · Validation — [`01-data-contract.md`](docs/specs/01-data-contract.md) §3–4, laddered by [`07-testing.md`](docs/specs/07-testing.md) §1
- [ ] Expands at gate

### 2 · Simulation — [`04-simulation.md`](docs/specs/04-simulation.md)
- [ ] Expands at gate

### 3 · Config core — [`03-config.md`](docs/specs/03-config.md): root model, hash, YAML round-trip
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

- **Stage 1** — the target's values (numeric, or binary, `01` §4.1) have no rule id, so nothing on
  stage 1's ladder checks them: a non-numeric target passes validation and fails late inside
  tsfresh. Nothing checks values against `selection.target_type` either.
- **Stage 8** — umap-learn's single-thread override warning has no id. If it is captured into the
  log, "nothing may live only in the log" needs it in the manifest too.
