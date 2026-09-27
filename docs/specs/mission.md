---
name: mission
status: draft
phase: 1
last-reviewed: 2026-09-26
---

# Mission

> Condensed from [`00-product.md`](00-product.md), [`ROADMAP.md`](../../ROADMAP.md) and the rules
> in [`CLAUDE.md`](../../CLAUDE.md). If this file and a detailed spec disagree, one of them is
> wrong — fix it in the same commit.

## Problem

Grouping time series by shape and behaviour is routine, and every component already exists — but
there is no **correct default path** through them. Hand-assembled pipelines fail silently:
non-finite features poison distances, unscaled features dominate the geometry, density clustering
degrades in high dimensions, and nothing is reproducible by default.

## Product

`ts_cluster`: a config-driven Python pipeline — wide DataFrame → tsfresh features → scaling →
PCA | UMAP → HDBSCAN — returning labels, diagnostics, and a reproducible run record. It competes on
the path and its guardrails, not on method breadth.

**Users:** data scientists, often working through a coding agent that cannot see a plot and will
not question a suspicious result. That caller is why this library is stricter than most. Humans
in notebooks remain first-class.

## Principles

1. **Validate, default, or refuse** — never leave a trap for the caller to find.
2. **Never silently repair input.** Contract violations raise; nothing is quietly imputed or dropped.
3. **Reproducible by construction.** Same config and seed give identical labels.
4. **`-1` is an answer.** Noise is reported honestly, never forced into a cluster.
5. **Correctness is measured against ground truth.** Simulation is product code; internal scores
   alone can certify a wrong partition.
6. **Results live on disk.** Anything a caller needs is in the manifest or summary — never only in
   a log.
7. **The config is the API.** One declarative object fully determines a run.

## Out of scope

Forecasting · a general time-series toolkit · a visualisation library · data cleaning · an HTTP
API · and, in Phase 1, deep learning and multivariate series.

## Phase 1 is done when

One config runs end to end into a persisted run directory; simulated groups are recovered at or
above calibrated thresholds; PCA and UMAP both pass; reruns give identical labels; contract and
ground-truth tests pass; the README and one notebook run from a clean checkout.
Envelope: under 1,000 entities, short series, one machine.

## Beyond Phase 1

2 persistent segmentation · 3 resampling · 4 more extractors · 5 anomaly detection ·
6 benchmarking · 7 Claude Code and Codex plugins · 8 scale-out. Whether 3 should precede 2 is open.
