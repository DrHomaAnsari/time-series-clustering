# Schemas

Machine-checkable contracts. A requirement expressed only in prose cannot be validated, so the
parts of the spec that must be exact live here.

| File | Origin | Editable |
|---|---|---|
| `run_summary.schema.json` | **Hand-authored** | Yes — it *is* the contract |
| `config.schema.json` | **Generated** from the pydantic model | No — regenerate |

## `run_summary.schema.json`

The contract for `summary.json` ([06 §3](../06-artifacts.md)). Hand-authored because nothing
generates it: the summary is a deliberately shaped, size-bounded view for an agent to read in full,
not a serialisation of an internal object.

Emitted summaries are validated against it in production code, not only in tests. A downstream
consumer trusts the artifact, so one that violates its own schema is worse than none.

## `config.schema.json`

Not present yet: it is generated from the pydantic model in [03](../03-config.md), which does not
exist. Once the model lands, generate it with `model_json_schema()`:

```bash
uv run python -m ts_cluster.config --emit-schema > docs/specs/schemas/config.schema.json
```

Never hand-edit it. A hand-edited copy drifts from the model it describes, and a schema that lies
is worse than one that is absent, because it will be trusted. CI regenerates it and fails if the
committed copy differs.

It is committed deliberately, so an agent can read the exact config contract without installing
the package or executing anything.
