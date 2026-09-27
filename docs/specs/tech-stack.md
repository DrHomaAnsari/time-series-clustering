---
name: tech-stack
status: draft
phase: 1
last-reviewed: 2026-09-27
---

# Tech stack

> Condensed from the detailed specs and [`CLAUDE.md`](../../CLAUDE.md). If this file and a
> detailed spec disagree, one of them is wrong — fix it in the same commit. No dependency is added
> until a spec records why (Rule 3).

## Platform

Python **3.11+**, never the system 3.9 · environments and packaging with **uv** · `src/ts_cluster/`
layout ([02](02-pipeline.md) § Module layout).

## Runtime libraries

| Library | Role, and why this one | Spec |
|---|---|---|
| pandas | Wide input, long melt, every tabular hand-off | [01](01-data-contract.md) |
| numpy | Numerics; `SeedSequence.spawn` gives position-stable seeds that survive spec edits | [04 §3](04-simulation.md) |
| pydantic v2 | The config model, `extra="forbid"` at every level so a misnamed field fails loudly | [03](03-config.md) |
| tsfresh | Feature extraction, behind an `Extractor` protocol that is the Phase 4 seam | [02 §3](02-pipeline.md) |
| scikit-learn | Scaling and PCA | [03](03-config.md) |
| umap-learn | Non-linear reduction. Brings numba, and runs single-threaded when seeded — the price of reproducibility | [03](03-config.md) § Determinism |
| hdbscan | Clustering, behind a one-module adapter. Chosen over `sklearn.cluster.HDBSCAN` for `relative_validity_` and Phase 2's `approximate_predict` | [02 §8](02-pipeline.md) |
| pyarrow | Parquet engine. Its pandas metadata restores datetime and numeric column labels and `Int64` with `pd.NA`, which fastparquet does not reliably do; CSV, JSON and pickle, the dependency-free alternatives, lose dtypes or are unsafe to load | [04 §5](04-simulation.md), [06 §6](06-artifacts.md) |
| PyYAML | Config files, via `safe_load`/`safe_dump` only. YAML 1.1 reads `no`/`off` as booleans, but every config field is strictly typed, so a mistyped value fails validation instead of passing through. ruamel.yaml's comment-preserving round-trip buys nothing, since we never edit a user's file | [03](03-config.md) |

## Formats

| What | Format | Why |
|---|---|---|
| Tables, simulated datasets | Parquet | Lossless dtypes and column labels; CSV rereads a time axis as strings |
| Config | YAML | One file format for people and agents; a Phase 7 tool call passes a dict instead of a file |
| Run summary | JSON, schema-validated at runtime | Against [`schemas/run_summary.schema.json`](schemas/run_summary.schema.json) |
| Config hash, data fingerprint | sha256 | The config hash is taken over canonical JSON of the resolved config |

## Development

pytest, with a `slow` marker for anything running tsfresh or UMAP · ruff for lint and format ·
mypy, clean on `src/ts_cluster`.

## Open — decided at stage 0's gate

Required by the specs, justified by none, so Rule 3 blocks each until a spec records why:

- **JSON Schema validator** — for runtime summary validation ([schemas](schemas/README.md))
- **CI** — [schemas](schemas/README.md) assumes CI regenerates `config.schema.json`; no spec defines it
- **Notebook tooling** — the example notebook is a Phase 1 deliverable

## Deliberately absent

Deep-learning frameworks (a Phase 1 non-goal) · an HTTP framework (deferred indefinitely) ·
distributed execution (Phase 8).
