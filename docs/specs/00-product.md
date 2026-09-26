---
name: product
status: draft
phase: 1
last-reviewed: 2026-09-26
---

# `ts_cluster` — Product Specification

> This file defines **what** we are building and **why**, and what we are deliberately not
> building. It contains no implementation detail. For that, see the sibling specs listed in
> [Related specs](#related-specs).

## 1. Problem

Grouping a collection of time series by shape and behaviour is a routine analytical need —
which sensors drift together, which assets fail alike, which accounts behave as one type. The
components to do it well already exist and are mature. What does not exist is a **correct
default path through them**.

In practice a data scientist reaching for this assembles tsfresh, a scaler, a dimensionality
reducer and a density clusterer by hand, and in doing so makes a dozen consequential choices
with no obvious right answer and no feedback when they get one wrong:

- Feature matrices arrive with `NaN`/`inf` columns that silently poison distances.
- tsfresh features span many orders of magnitude, so an unscaled or naively-scaled matrix lets
  a handful of features dominate the geometry entirely.
- HDBSCAN degrades sharply in high-dimensional space, so the reduction step is not optional —
  but its choice changes the answer.
- Nothing in the stack is reproducible by default, so a result cannot be re-derived next week.

Each of these fails **silently**. The pipeline runs, labels come out, and the labels are wrong
in ways no error message reports.

## 2. What `ts_cluster` is

A config-driven Python pipeline that takes a wide DataFrame of time series and returns cluster
labels, supporting diagnostics, and a reproducible record of how they were produced.

Its opinion is that the correctness traps above should be **validated, defaulted, or refused** —
never left to the caller to discover. Its bet is that the most valuable form of that opinion is
one a coding agent can execute faithfully.

## 3. Primary users

Data scientists, working through a coding agent (Claude Code, Codex) at least as often as by
hand.

That audience has a specific consequence: the caller is frequently a system that cannot see a
plot, will not notice a suspicious cluster count, and will confidently proceed past a result a
human would have squinted at. Every design decision in the sibling specs that looks unusually
strict — mandatory validation, refusal to impute silently, a machine-readable run summary — is
downstream of that single fact.

Humans reading notebooks remain a first-class audience. Nothing here should make interactive use
worse.

## 4. The job the clusters do

| Phase | Job | Consequence for design |
|---|---|---|
| **1** | **Exploratory discovery** — surface groupings a human then interprets | Success is hard to assert directly, so we test against simulated data with known ground truth (see [`05-evaluation.md`](05-evaluation.md)) |
| **2** | **Entity segmentation** — persistent labels that downstream systems consume | Makes label stability across refits a hard requirement, and requires applying a fitted pipeline to unseen entities |
| **5** | Anomaly / novelty detection | Deferred; see [`ROADMAP.md`](../../ROADMAP.md) |
| **6** | Method benchmarking | Deferred |

Phase 1 optimises for the first job only. Where a Phase 1 decision would foreclose Phase 2, the
sibling specs say so at the seam with a `> Phase N` marker.

## 5. Positioning

tslearn, sktime, aeon, tsfresh and Darts all exist and are good. `ts_cluster` does not compete
with them on method breadth — it **depends on** tsfresh and scikit-learn and will lose any
feature-count comparison by design.

The differentiation is delivery: an opinionated, validated, reproducible path from raw wide
DataFrame to trustworthy labels, exposed as a declarative config that an agent can construct,
serialise, and reason about without knowing the internals. The eventual Claude Code and Codex
plugins (Phase 7) are the point of the config-first API, not an afterthought bolted onto it.

Where those libraries offer components, we offer a **path** — and the guardrails that make the
path safe to walk automatically.

## 6. Non-goals

These are refusals, not backlog items. An agent encountering a request in this list should
decline and point here rather than implement.

- **Not a forecasting library.** No prediction of future values. The optional target column used
  for supervised feature selection is a selection signal only — see
  [`01-data-contract.md`](01-data-contract.md).
- **Not a general time-series toolkit.** No decomposition, changepoint detection, anomaly
  scoring, or similarity search as standalone public API.
- **No deep learning in Phase 1.** No learned representations, autoencoders, or embeddings
  beyond the classical reduction step.
- **Not a visualisation product.** Diagnostics are emitted as data. Plotting belongs in the
  example notebook, not the library core.
- **Not a data-cleaning tool.** Phase 1 assumes clean, regularly-sampled input and validates
  that assumption rather than repairing violations. Resampling arrives in Phase 3 as an
  explicit, user-invoked step.
- **No HTTP API.** Deferred indefinitely.
- **No multivariate series in Phase 1.** Univariate only.

## 7. Definition of done — Phase 1

Phase 1 is complete when **all** of the following hold:

1. A single config runs end-to-end: wide DataFrame → validation → features → selection →
   scaling → reduction → clustering → evaluation → persisted run directory, JSON summary, and run
   log, all under the single configurable `output.root`.
2. The simulation module generates labelled synthetic datasets and writes them to disk, and the
   pipeline recovers those known groups at or above the thresholds in
   [`05-evaluation.md`](05-evaluation.md).
3. Both reduction methods (PCA and UMAP) are selectable by config and both run green.
4. The same config and seed produce **identical** labels across runs.
5. Test suite passes: synthetic ground-truth tests and contract/shape tests.
6. A README walkthrough and one example notebook exist, both runnable from a clean checkout.

Explicitly **not** required for Phase 1: validation on real-world data, publication to PyPI,
performance beyond laptop scale, or a stable public API guarantee.

## 8. Scale envelope — Phase 1

| Dimension | Phase 1 target | Behaviour beyond it |
|---|---|---|
| Entities | < 1,000 | Documented limit; no out-of-core path |
| Series length | Short (order 10²–10³ points) | Not optimised |
| Execution | Single machine, in-memory | No distributed execution |

Exceeding these should degrade in runtime, not in correctness, and the documented limits should
be stated where a user will actually encounter them.

> Phase 8 — scale-out to 1k–100k, then >100k entities.

## 9. Glossary

Vocabulary is pinned here because inconsistent naming between spec and code is the most common
way an agent silently diverges from intent. These terms mean exactly this throughout the repo,
in prose, identifiers, and error messages.

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

## Related specs

- [`ROADMAP.md`](../../ROADMAP.md) — phase ledger and sequencing
- [`01-data-contract.md`](01-data-contract.md) — input/output schemas and validation
- [`02-pipeline.md`](02-pipeline.md) — stage-by-stage contract
- [`03-config.md`](03-config.md) — the config schema, i.e. the public API
- [`04-simulation.md`](04-simulation.md) — synthetic data generator
- [`05-evaluation.md`](05-evaluation.md) — metrics and numerical acceptance criteria
- [`06-artifacts.md`](06-artifacts.md) — run directory and JSON summary
- [`07-testing.md`](07-testing.md) — test strategy
