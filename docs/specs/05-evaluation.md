---
name: evaluation
status: draft
phase: 1
last-reviewed: 2026-09-27
---

# Evaluation

What "the clustering is good" means, in terms a test can assert. Every run produces labels whether
or not they mean anything, so without this file an agent cannot tell a refactor from a regression.

## 1. Two kinds of metric

| Kind | Computed from | Available | Answers |
|---|---|---|---|
| **Internal** | The data and labels alone | Every run, including real user data | Is this partition structurally sound? |
| **External** | Known ground truth | Simulated data only | Did we recover the right groups? |

Only external metrics can validate correctness — internal metrics alone will certify a confidently
wrong partition. That is why simulation is product code: without ground truth there is nothing to
be correct *about*. Correctness assertions therefore go through external metrics only.

## 2. Internal metrics

| Metric | Source | Meaning |
|---|---|---|
| `relative_validity` | `hdbscan`'s `relative_validity_` | DBCV-style density-based validity. **Primary** |
| `n_clusters` | Label count, excluding `-1` | Number of clusters found |
| `noise_fraction` | Share of entities labelled `-1` | Headline diagnostic |
| `cluster_sizes` | Entity count per label, excluding `-1` | Detects one-giant-cluster degeneracy |

**Why not silhouette.** It assumes convex, roughly equal-sized clusters and scores compactness
against separation with centroid-style geometry — but HDBSCAN is chosen precisely to find clusters
that are neither. Silhouette systematically penalises correct answers, and an agent tuning
parameters to maximise it tunes the pipeline away from working. `relative_validity_` is the
density-based analogue and comes from the MST the clusterer already built, which is why
`clustering.gen_min_span_tree` must remain `true` ([03](03-config.md)).

**Caveat: relative, not absolute.** `relative_validity_` is an MST-based approximation of DBCV,
and the `hdbscan` documentation states it is for comparing parameter settings on the same dataset.
It is not an absolute quality score, and values are not comparable across datasets of different
size or dimensionality. Binding on implementation and on any agent tuning the pipeline:

- Never assert an absolute `relative_validity` threshold in a test.
- Never present it to a user as a standalone "quality score".
- Use it to rank configs on one dataset — the job it is valid for.

## 3. External metrics

Computed when ground truth ([01 §4.2](01-data-contract.md)) is supplied.

| Metric | Range | Meaning |
|---|---|---|
| `ari` | [-0.5, 1] | Adjusted Rand index. **Primary correctness metric.** Chance-corrected, so 0 means no better than random |
| `ami` | ≤ 1 | Adjusted mutual information. Chance-corrected too, so it can be negative. Reported alongside; behaves differently when cluster sizes are very unbalanced |
| `noise_recall` | [0, 1] | Share of true-noise entities (truth `-1`) that were labelled `-1` |
| `n_clusters_error` | ℤ | `n_clusters` minus the number of true structured groups. Signed, so over- and under-clustering are distinguishable |

**Noise handling in ARI.** ARI is computed over all entities, with `-1` as its own class in both
truth and prediction. Excluding noise before scoring would reward a pipeline that dumps difficult
entities into `-1` to raise its score on the rest. `noise_recall` is reported separately because
ARI alone cannot tell "correctly identified the structureless entities" from "got lucky on the
structured ones".

## 4. Acceptance criteria

Per preset from [04 §6](04-simulation.md), at its canonical seed, under the default config.

> **Provisional — calibrate before trusting.** No implementation exists yet, so nobody has observed
> what this pipeline achieves on these presets: the values are plausibility targets, not
> measurements. Committing them as measured would be fabrication, and a suite calibrated against
> invented numbers either passes vacuously or blocks correct work. Each is marked `CALIBRATE`;
> follow §5 before Phase 1 can be called done.

| Preset | Metric | Provisional | Status |
|---|---|---|---|
| `easy_separable` | `ari` | ≥ 0.90 | `CALIBRATE` |
| `moderate` | `ari` | ≥ 0.70 | `CALIBRATE` |
| `hard_overlapping` | `ari` | ≥ 0.40 | `CALIBRATE` |
| `with_noise` | `ari` | ≥ 0.65 | `CALIBRATE` |
| `with_noise` | `noise_recall` | ≥ 0.70 | `CALIBRATE` |
| `single_cluster` | `n_clusters` | ≤ 1 | **Fixed** |
| `no_structure` | `n_clusters` | 0, or `noise_fraction` ≥ 0.80 | **Fixed** |

The **Fixed** rows are correctness properties, not performance thresholds, so they are not
calibrated: a pipeline that splits homogeneous data, or finds structure in pure noise, is wrong at
any tolerance. They are the most important assertions in the suite.

Both reduction methods (`pca` and `umap`) must satisfy every row. Thresholds are calibrated per
method where they differ — UMAP typically separates better, so one shared threshold would be too
loose for one method or too tight for the other.

## 5. Calibration protocol

Once the pipeline runs end to end:

1. Run each preset at its canonical seed under the default config, for both reduction methods.
2. Run each at five additional seeds to observe spread; a threshold set from one seed encodes that
   seed's luck.
3. Set the threshold at `min(observed) − margin`, margin = 0.05 for ARI-style metrics.
4. Commit the observed values, the margin and the date in this file, beside the threshold, replacing
   the `CALIBRATE` marker.
5. If an observed value falls far below its provisional target, that is a finding about the
   pipeline: investigate before lowering the number. Ratcheting thresholds down to make tests pass
   turns the suite into decoration.

Recalibrate whenever a default in [03](03-config.md) changes — defaults are what these numbers
measure.

## 6. Reporting

Every run emits its metrics into `summary.json` ([06 §3](06-artifacts.md)). Placement is fixed by
`schemas/run_summary.schema.json`, not a free choice:

| Value | Location in `summary.json` |
|---|---|
| `n_clusters`, `noise_fraction`, `cluster_sizes` | `clustering` — facts about the partition |
| `relative_validity` | `metrics.internal` — a score |
| `ari`, `ami`, `noise_recall`, `n_clusters_error` | `metrics.external` |

The split is *what the partition is* versus *how good it is*. Each value appears exactly once, since
two copies of a number invite disagreement. External metrics appear only when ground truth was
supplied; their absence is explicit (`null`), never an omitted key, so an agent can tell "not
applicable" from "missing".

`noise_fraction` above `evaluation.noise_fraction_warn_above` records warning `W102`
([02 § Runtime warnings](02-pipeline.md)), never an error. A high noise fraction is a true statement about the data; suppressing it would be the very
failure this library exists to prevent.
