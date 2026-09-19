# Schemas

Machine-checkable contracts. These exist because a requirement expressed only in prose cannot be
validated — the parts of the spec that must be exact live here instead.

| File | Origin | Editable |
|---|---|---|
| `run_summary.schema.json` | **Hand-authored** | Yes — it *is* the contract |
| `config.schema.json` | **Generated** from the pydantic model | No — regenerate |

## `run_summary.schema.json`

The contract for `summary.json` ([`../06-artifacts.md` §3](../06-artifacts.md)). Hand-authored
because nothing generates it: the summary is a deliberately shaped, size-bounded view designed
for an agent to read in full, not a serialisation of an internal object.

Emitted summaries are validated against it **in production code**, not only in tests. An artifact
that violates its own schema is worse than no artifact — a downstream consumer trusts it.

## `config.schema.json`

Not present yet: it is generated from the pydantic model described in
[`../03-config.md`](../03-config.md), and no implementation exists.

Generate with `model_json_schema()` once the model lands:

```bash
uv run python -m ts_cluster.config --emit-schema > docs/specs/schemas/config.schema.json
```

**Never hand-edit it.** A hand-edited copy drifts from the model it claims to describe, and a
schema that lies is worse than one that is absent — it will be trusted. CI regenerates it and
fails if the committed copy differs.

Committing it at all is deliberate: it lets an agent read the exact config contract without
installing the package or executing anything.
