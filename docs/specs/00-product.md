---
name: product
status: draft
phase: 1
last-reviewed: 2026-09-27
---

# `ts_cluster` — Product

What we are building, why, and what we deliberately are not. Implementation detail lives in 01–07.

## 1. Problem

Grouping time series by shape and behaviour — which sensors drift together, which assets fail
alike, which accounts behave as one type — is routine, and the components are mature. What is
missing is a correct default path through them. Hand-assembling tsfresh, a scaler, a
dimensionality reducer and a density clusterer means a dozen consequential choices with no
feedback when one is wrong:

- Feature matrices arrive with `NaN`/`inf` columns that silently poison distances.
- tsfresh features span many orders of magnitude, so an unscaled or naively scaled matrix lets a
  handful of features dominate the geometry.
- HDBSCAN degrades sharply in high dimensions, so reduction is not optional — and its choice
  changes the answer.
- Nothing is reproducible by default, so a result cannot be re-derived next week.

Each fails silently: the pipeline runs, labels come out, and they are wrong in ways no error
reports.

## 2. What `ts_cluster` is

A config-driven Python pipeline that takes a wide DataFrame of time series and returns cluster
labels, diagnostics, and a reproducible record of how they were produced. Its opinion: the traps
above are validated, defaulted, or refused — never left for the caller to discover. Its bet: the
most valuable form of that opinion is one a coding agent can execute faithfully.

## 3. Primary users

Data scientists, working through a coding agent (Claude Code, Codex) at least as often as by hand.
That caller cannot see a plot, will not notice a suspicious cluster count, and proceeds confidently
past results a human would question. Every unusually strict choice in these specs — mandatory
validation, no silent imputation, a machine-readable run summary — follows from that.

Humans in notebooks remain first-class; nothing may make interactive use worse.

## 4. The job the clusters do

| Phase | Job | Consequence for design |
|---|---|---|
| 1 | **Exploratory discovery** — surface groupings a human then interprets | Success is hard to assert directly, so we test against simulated ground truth ([05](05-evaluation.md)) |
| 2 | **Entity segmentation** — persistent labels that downstream systems consume | Label stability across refits becomes a hard requirement, as does applying a fitted pipeline to unseen entities |
| 5 | Anomaly / novelty detection | Deferred ([ROADMAP](../../ROADMAP.md)) |
| 6 | Method benchmarking | Deferred |

Phase 1 optimises for the first job only. Where a Phase 1 decision would foreclose Phase 2, the
spec marks the seam with `> Phase N`.

## 5. Positioning

tslearn, sktime, aeon, tsfresh and Darts exist and are good. `ts_cluster` depends on tsfresh and
scikit-learn and does not compete on method breadth — it loses any feature-count comparison by
design.

It differentiates on delivery: an opinionated, validated, reproducible path from raw wide DataFrame
to trustworthy labels, driven by a declarative config an agent can construct, serialise and reason
about without knowing the internals. Those libraries offer components; `ts_cluster` offers a path,
plus the guardrails that make it safe to walk automatically. The Phase 7 Claude Code and Codex
plugins are the point of the config-first API, not an afterthought.

## 6. Non-goals

Refusals, not backlog items: an agent asked for one declines and points here.

- **Forecasting.** No prediction of future values. The optional target
  ([01 §4](01-data-contract.md)) is a feature-selection signal only.
- **A general time-series toolkit.** No decomposition, changepoint detection, anomaly scoring or
  similarity search as standalone public API.
- **Deep learning in Phase 1.** No learned representations, autoencoders, or embeddings beyond the
  classical reduction step.
- **Visualisation.** Diagnostics are emitted as data; plotting belongs in the example notebook, not
  the library core.
- **Data cleaning.** Phase 1 assumes clean, regularly sampled input and validates that assumption
  instead of repairing violations. Resampling arrives in Phase 3 as an explicit, user-invoked step.
- **An HTTP API.** Deferred indefinitely.
- **Multivariate series in Phase 1.** Univariate only.

## 7. Definition of done — Phase 1

All of:

1. A single config runs end to end: wide DataFrame → validation → features → selection → scaling →
   reduction → clustering → evaluation → persisted run directory, JSON summary and run log, all
   under the single configurable `output.root`.
2. The simulation module generates labelled synthetic datasets and writes them to disk, and the
   pipeline recovers those known groups at or above the thresholds in [05](05-evaluation.md).
3. Both reduction methods (PCA and UMAP) are selectable by config and both run green.
4. The same config and seed produce identical labels across runs.
5. The test suite passes: synthetic ground-truth tests and contract/shape tests.
6. A README walkthrough and one example notebook exist, both runnable from a clean checkout.

Not required: validation on real-world data, publication to PyPI, performance beyond laptop scale,
a stable public API guarantee.

## 8. Scale envelope — Phase 1

| Dimension | Target | Beyond it |
|---|---|---|
| Entities | < 1,000 | Documented limit; no out-of-core path |
| Series length | Short (order 10²–10³ points) | Not optimised |
| Execution | Single machine, in-memory | No distributed execution |

Beyond the envelope, runtime may degrade but correctness must not, and the limits are documented
where a user will actually hit them.

> Phase 8 — scale-out to 1k–100k, then >100k entities.

## 9. Glossary

These terms mean exactly this in prose, identifiers and error messages — inconsistent naming is the
most common way an agent silently diverges from intent.

| Term | Meaning |
|---|---|
| **Entity** | One subject being clustered — one row of the wide input. Never "sample", "item", or "object" |
| **Series** | The ordered observations belonging to one entity |
| **Timestep** | One column of the wide input |
| **Feature matrix** | The entity × feature table produced by extraction. Never "X" in public API |
| **Embedding** | The output of the reduction stage |
| **Label** | A cluster assignment. `-1` means noise and is a real answer, never a failure |
| **Noise fraction** | Share of entities labelled `-1`. A headline diagnostic, not an error |
| **Run** | One end-to-end execution of a config, producing exactly one run directory and exactly one log file |
| **Config** | The declarative object that fully determines a run. The public API |
