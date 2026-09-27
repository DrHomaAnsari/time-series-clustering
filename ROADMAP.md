---
name: roadmap
status: draft
last-reviewed: 2026-09-27
---

# `ts_cluster` — Roadmap

The phase ledger. Every deferred capability lives here, and each spec marks where a later phase
attaches with an inline `> Phase N` marker.

**Current phase: 1.** Work in the current phase only. A later-phase capability is a deliberate
boundary, not a missing feature: if current-phase work appears to require one, that is a spec bug —
stop and report it rather than pull the later work forward.

## Phase 1 — Python backend, exploratory discovery

**Entry:** specs complete and reviewed.

**Scope**

- Package `ts_cluster`, Python 3.11+, managed with `uv`.
- Input: wide DataFrame, univariate, clean, regularly sampled — validated, not repaired.
- Pipeline: validate → melt → tsfresh extraction → feature selection → scaling →
  PCA | UMAP | none → HDBSCAN → evaluation → persistence.
- Config-driven public API; the config fully determines a run.
- Simulation module producing labelled synthetic datasets, written to disk.
- Versioned run directory plus compact JSON summary.
- Tests: synthetic ground-truth + contract/shape + determinism.
- README walkthrough and one example notebook.

**Exit:** all six criteria in [`docs/specs/00-product.md` §7](docs/specs/00-product.md).

## Phase 2 — Entity segmentation

**Entry:** Phase 1 exit met.

Turns exploratory labels into persistent ones that downstream systems can depend on.

- Apply a fitted pipeline to unseen entities (`hdbscan.approximate_predict`).
- Persist and reload fitted pipeline state.
- Label stability across refits: clusters keep their identity when the model is retrained. HDBSCAN
  does not provide this natively; it needs an explicit matching strategy.
- Soft cluster membership probabilities.
- Golden-file regression tests and property-based tests added to the suite.

**Known tension:** stable labels are hard when reduction is UMAP, whose embedding is not a stable
coordinate system across refits. This phase may need to constrain the reduction choice or fix the
embedding. Decide during Phase 2 design; do not pre-solve it in Phase 1.

## Phase 3 — Resampling module

**Entry:** Phase 2 exit met, subject to the sequencing note below.

Removes the Phase 1 precondition that input is already regularly sampled.

- Detect irregular sampling and ragged entity coverage.
- Refuse to proceed silently. Prompt the user to declare a resampling policy explicitly: target
  frequency, interpolation/aggregation rule, gap tolerance, and behaviour on entities that cannot
  satisfy it.
- Apply the declared policy and record it in the run manifest, since it materially changes results.

> **Sequencing note.** Resampling changes the data contract, which sits upstream of everything
> Phase 2 builds, so doing it after segmentation means revisiting segmentation's assumptions about
> input regularity. Swapping Phases 2 and 3 would avoid that rework at the cost of delaying the
> first production-shaped capability. Open decision — see [Open questions](#open-questions).

## Phase 4 — Feature extraction beyond tsfresh

**Entry:** Phase 3 exit met.

- Alternative representations (shapelets, catch22, spectral, learned) behind the extraction
  interface established in Phase 1.
- This requires extraction to be a swappable interface from the start — a Phase 1 design
  constraint, recorded in [`02-pipeline.md`](docs/specs/02-pipeline.md) §3.

## Phase 5 — Anomaly / novelty detection

- Distance-from-cluster scoring; thresholds; false-positive budget; drift over time.
- Reframes the noise fraction from a diagnostic into a product surface.

## Phase 6 — Benchmarking harness

- Run many methods across many datasets reproducibly; comparative reporting.
- Consumes the Phase 1 simulation module as its corpus — which is why simulation is product code
  rather than test scaffolding.

## Phase 7 — Claude Code and Codex plugins

The delivery goal the whole architecture points at.

- Expose the pipeline as agent tooling for both hosts.
- The Phase 1 config schema and JSON run summary are designed to map near-directly onto a tool
  surface. If this phase has to reshape either, that is evidence the Phase 1 design missed.

## Phase 8 — Scale-out

- **8a:** 1k–100k entities — parallel/chunked extraction, restricted feature sets, feature-matrix
  memory management.
- **8b:** >100k entities — out-of-core or distributed execution, on-disk feature storage.

## Deferred indefinitely

Not scheduled. Revisit only on explicit decision.

- **HTTP API** — the plugin surface is the integration path.
- **Multivariate series** — would change the data contract, distance semantics, per-channel
  scaling and channel weighting: a substantial redesign, not an increment.

## Open questions

| # | Question | Blocks |
|---|---|---|
| 1 | Should resampling (Phase 3) precede entity segmentation (Phase 2)? See the sequencing note above | Phase 2 start |
