# ts_cluster

Config-driven Python pipeline that clusters collections of time series:
wide DataFrame → tsfresh features → scaling → PCA|UMAP → HDBSCAN → labels + reproducible run record.

Its opinion is that the silent-failure traps in this stack (poisoned feature columns, unscaled
geometry, high-dimensional density clustering, non-reproducibility) must be **validated,
defaulted, or refused** — never left for the caller to discover. The primary caller is often a
coding agent that cannot see a plot and will not notice a suspicious result, which is why the
validation here is stricter than a typical library's.

## Status

**Specs only — no implementation exists yet.** `docs/specs/` is the source of truth. Read the
relevant spec before writing code; do not infer intent from the absence of code.

**Current phase: 1.** See [ROADMAP.md](ROADMAP.md). Work in the current phase only.

## Where things are

| Path | What |
|---|---|
| [`docs/specs/00-product.md`](docs/specs/00-product.md) | Purpose, non-goals, definition of done, **glossary** |
| [`docs/specs/01-data-contract.md`](docs/specs/01-data-contract.md) | Input/output schemas, validation rules |
| [`docs/specs/02-pipeline.md`](docs/specs/02-pipeline.md) | Stage-by-stage contract |
| [`docs/specs/03-config.md`](docs/specs/03-config.md) | The config schema — **this is the public API** |
| [`docs/specs/04-simulation.md`](docs/specs/04-simulation.md) | Synthetic data generator |
| [`docs/specs/05-evaluation.md`](docs/specs/05-evaluation.md) | Metrics, numerical acceptance thresholds |
| [`docs/specs/06-artifacts.md`](docs/specs/06-artifacts.md) | Run directory, JSON summary |
| [`docs/specs/07-testing.md`](docs/specs/07-testing.md) | Test strategy |
| [`ROADMAP.md`](ROADMAP.md) | Phase ledger and boundaries |
| [`docs/decisions.md`](docs/decisions.md) | Implementation decisions the specs leave open — append-only |
| [`BACKLOG.md`](BACKLOG.md) | Build order and progress for the current phase — the next step is its first unchecked box |

## Commands

> Not yet functional — the package is unscaffolded. These are the intended commands; keep this
> table true as soon as it exists.

```bash
uv sync                      # install, including dev extras
uv run pytest                # full test suite
uv run pytest -m "not slow"  # fast subset
uv run ruff check --fix .    # lint
uv run ruff format .         # format
uv run mypy src/ts_cluster   # type check

uv run python -m ts_cluster.config --emit-schema \
  > docs/specs/schemas/config.schema.json   # regenerate; never hand-edit
```

Python 3.11+, managed by `uv`. Do not use the system Python (3.9, EOL).

## Conventions

- **Typing** — type hints on every public function; `mypy` clean.
- **Docstrings** — numpydoc style on public API. Document what a parameter *does to the result*,
  not just its type.
- **Naming** — use the glossary in `00-product.md` exactly, in identifiers, prose, and error
  messages. Not "sample"/"item" for an entity; not `X` for the feature matrix.
- **Errors** — every validation failure states what was expected, what was received, and what to
  do about it. An agent reading the message should be able to fix the input without reading source.
- **Tests** — new behaviour needs a test in the layer `07-testing.md` assigns it to.

## How we work

The process is as load-bearing as the code. Homa drives; I write. Run `/step` to take the next one.

**Step = one function plus its test.** Budget: ≤50 new lines (implementation and test combined),
≤1 new file. Over budget means the step was too big: split it. If it genuinely cannot be split,
say the line count and the reason and wait for a yes before writing — never exceed it silently.
Scaffolding steps (`pyproject.toml`, package skeleton) have no test and are exempt.

**Decisions batch per stage, never per function.** Before the first line of a stage's code, list
every real choice it contains — options, one-line tradeoff, a recommendation — and wait. Then
implement function by function without further gating. A *new* decision appearing mid-stage is a
stop, not a judgement call.

**No speculative code.** Every function traces to a spec line, named in its docstring. No
abstraction with one caller, no base class with one subclass, no config field absent from
`03-config.md`, no `try`/`except` the spec does not require. The third caller earns the helper.

**Non-obvious lines carry a `# why not X:` note** — one line: what the obvious alternative was and
why it loses. That is where the real knowledge in this stack lives.

**Log the decision.** Append one entry to [`docs/decisions.md`](docs/decisions.md) per resolved
decision. If a decision contradicts a spec, the spec changes instead (Rule 2) — the log is only for
what the specs leave open.

**Backlog.** [`BACKLOG.md`](BACKLOG.md) holds build order and progress. I tick one box per step,
in the same commit as the code; expand a stage into steps only when its gate is approved; and park
anything out of scope in one line rather than act on it. Reordering, deleting and re-scoping are
Homa's.

**Response format.** Per step: a `Step:` line, decisions if any, the diff, then at most 4 lines —
what landed, the why-not, the next step. Never restate the diff in prose; it is on screen. No
preamble, no recap of what is already settled, no summary-of-changes section. Recommend one next
step, not a menu.

## Rules

These are the ones most easily violated. They exist because each protects against a failure that
is silent rather than loud.

1. **Never silently impute, coerce, drop, or repair input.** If data violates the contract, raise
   with a specific message. Phase 1 validates; it does not clean. A quietly imputed `NaN` becomes
   a wrong cluster with no trace.

2. **Never change a spec'd default without updating the spec in the same commit.** Defaults are
   load-bearing here — they *are* the product's opinion. A drifted default silently changes every
   user's results.

3. **Never add a dependency without recording the justification** in the relevant spec. This stack
   already carries heavy transitive weight (numba via UMAP); each addition is a real cost.

4. **Never let a run be irreproducible.** Same config + same seed must give identical labels. If a
   component cannot honour that, it must be configured until it can or rejected. UMAP in
   particular is non-deterministic in parallel mode even when seeded.

5. **`-1` is a real answer, not a failure.** HDBSCAN noise labels are reported honestly and never
   force-assigned to a cluster. A high noise fraction is information about the data.

6. **Do not pull later-phase work forward.** If a current-phase task appears to require a
   later-phase capability, that is a spec bug — stop and report it.

## Working with the specs

The specs are versioned alongside the code deliberately. When a requirement seems wrong or
ambiguous, check `git log -p` on the spec file — the reason for a constraint is often in its
history. Propose a spec change in the same PR as the code change; never let them diverge.
