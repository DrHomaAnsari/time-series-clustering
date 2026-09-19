---
name: evaluation
status: draft
phase: 1
last-reviewed: 2026-09-19
---

# Evaluation

Defines what "the clustering is good" means in terms a test can assert. Without this file, an
agent cannot distinguish a refactor from a regression, because every clustering run produces
labels regardless of whether they mean anything.

## 1. Two kinds of metric

**Internal** — computed from the data and labels alone. Available on every run, including real
user data. Answers "is this partition structurally sound?"

**External** — computed against known ground truth. Available only on simulated data. Answers
"did we recover the right groups?"

Only external metrics can validate correctness. This is precisely why the simulation module is
product code: without ground truth there is nothing to be correct *about*, and internal metrics
alone will happily certify a confidently wrong partition.

## 2. Internal metrics

| Metric | Source | Meaning |
|---|---|---|
| `relative_validity` | `hdbscan`'s `relative_validity_` | DBCV-style density-based validity. **Primary** |
| `n_clusters` | Label count, excluding `-1` | Number of clusters found |
| `noise_fraction` | Share of entities labelled `-1` | Headline diagnostic |
| `cluster_size_distribution` | min / median / max / counts | Detects one-giant-cluster degeneracy |

### Why not silhouette

Silhouette assumes convex, roughly equal-sized clusters and measures compactness against
separation using centroid-style geometry. Density-based clustering exists to find clusters that
are **neither convex nor equally sized** — that is the entire reason to choose HDBSCAN. Scoring
those with silhouette systematically penalises correct answers, and an agent tuning parameters to
maximise it will tune the pipeline away from working.

`relative_validity_` is the density-based analogue and comes from the same MST the clusterer
already built, which is why `clustering.gen_min_span_tree` must remain `true`
([`03-config.md`](03-config.md)).

### The caveat that must not be lost

`relative_validity_` is an MST-based **approximation** of DBCV, and the `hdbscan` documentation is
explicit that it is intended for *relative* comparison — between parameter settings on the same
dataset. It is **not** an absolute quality score, and values are not comparable across datasets of
different size or dimensionality.

Consequences, binding on implementation and on any agent tuning the pipeline:

- Never assert an absolute `relative_validity` threshold in a test.
- Never present it to a user as a standalone "quality score".
- Use it to rank configs on one dataset, which is the job it is valid for.

Correctness assertions go through external metrics only.

## 3. External metrics

Computed when ground truth is supplied.

| Metric | Range | Meaning |
|---|---|---|
| `ari` | [-0.5, 1] | Adjusted Rand index. **Primary correctness metric.** Chance-corrected, so 0 means no better than random |
| `ami` | [0, 1] | Adjusted mutual information. Reported alongside; behaves differently when cluster sizes are very unbalanced |
| `noise_recall` | [0, 1] | Share of true-noise entities (truth `-1`) that were labelled `-1` |
| `n_clusters_error` | ℤ | `n_clusters` minus the number of true structured groups. Signed, so over- and under-clustering are distinguishable |

### Noise handling in ARI

ARI is computed over **all** entities with `-1` treated as its own class in both truth and
prediction. This is a deliberate choice: excluding noise entities before scoring would reward a
pipeline that dumps difficult entities into `-1` to raise its score on the remainder.

`noise_recall` is reported separately because ARI alone cannot distinguish "correctly identified
the structureless entities" from "got lucky on the structured ones".

## 4. Acceptance criteria

Per preset from [`04-simulation.md` §6](04-simulation.md), at its canonical seed, under the
default config.

> ### ⚠ These thresholds are PROVISIONAL and must be calibrated
>
> No implementation exists yet, so no one has observed what this pipeline actually achieves on
> these presets. The values below are **targets derived from plausibility, not measurements.**
> Committing them as if they were measured would be fabrication, and a test suite calibrated
> against invented numbers either passes vacuously or blocks correct work.
>
> Each is marked `CALIBRATE`. Follow §5 before Phase 1 can be called done.

| Preset | Metric | Provisional | Status |
|---|---|---|---|
| `easy_separable` | `ari` | ≥ 0.90 | `CALIBRATE` |
| `moderate` | `ari` | ≥ 0.70 | `CALIBRATE` |
| `hard_overlapping` | `ari` | ≥ 0.40 | `CALIBRATE` |
| `with_noise` | `ari` | ≥ 0.65 | `CALIBRATE` |
| `with_noise` | `noise_recall` | ≥ 0.70 | `CALIBRATE` |
| `single_cluster` | `n_clusters` | ≤ 1 | **Fixed** |
| `no_structure` | `n_clusters` | 0, or `noise_fraction` ≥ 0.80 | **Fixed** |

The two **Fixed** rows are not calibrated because they are not performance thresholds — they are
correctness properties. A pipeline that splits homogeneous data, or finds structure in pure noise,
is wrong at any tolerance. These are the most important assertions in the suite.

Both reduction methods (`pca` and `umap`) must satisfy every row. Thresholds are calibrated per
method where they differ, since UMAP typically separates better and a single shared threshold
would be either too loose for one or too tight for the other.

## 5. Calibration protocol

Once the pipeline runs end to end:

1. Run each preset at its canonical seed under the default config, for both reduction methods.
2. Run each at **five** additional seeds to observe spread. A threshold set from a single seed
   encodes that seed's luck.
3. Set the threshold at `min(observed) − margin`, margin = 0.05 for ARI-style metrics.
4. Commit the observed values, the margin, and the date **in this file** alongside the threshold,
   replacing the `CALIBRATE` marker.
5. If an observed value falls far below its provisional target, that is a finding about the
   pipeline — investigate before lowering the number. Ratcheting thresholds down to make tests
   pass converts the suite into decoration.

Recalibrate whenever a default in [`03-config.md`](03-config.md) changes, since defaults are what
these numbers measure.

## 6. Reporting

Every run emits its metrics into `summary.json` ([`06-artifacts.md`](06-artifacts.md)). Placement
is fixed by `schemas/run_summary.schema.json` and is **not** a free choice:

| Value | Location in `summary.json` |
|---|---|
| `n_clusters`, `noise_fraction`, `cluster_sizes` | `clustering` — facts about the partition |
| `relative_validity` | `metrics.internal` — a score |
| `ari`, `ami`, `noise_recall`, `n_clusters_error` | `metrics.external` |

The split is between *what the partition is* and *how good it is*. Each value appears exactly
once; duplicating a number across blocks invites the two copies to disagree.

External metrics appear only when ground truth was supplied, and their absence is explicit
(`null`), never an omitted key — an agent must be able to tell "not applicable" from "missing".

`noise_fraction` above `evaluation.noise_fraction_warn_above` records a manifest warning. It is
**never** an error: a high noise fraction is a true statement about the data, and suppressing it
would be the one failure mode this library exists to prevent.

## Related specs

- [`03-config.md`](03-config.md) · [`04-simulation.md`](04-simulation.md)
- [`06-artifacts.md`](06-artifacts.md) · [`07-testing.md`](07-testing.md)
