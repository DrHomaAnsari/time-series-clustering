---
name: step
description: Take the next implementation step in ts_cluster - one function plus its test, inside the line budget, with decisions surfaced before any code. Use when Homa types /step, or asks to take the next step, continue the build, implement the next piece, or start a stage.
---

# `/step` — take exactly one step

Homa drives; I write. The rules in `CLAUDE.md` §"How we work" always apply; this is the choreography
for a single step. Take **one** step per invocation and stop.

## 1. Name the step

The next step is the **first unchecked box** in [`BACKLOG.md`](../../../BACKLOG.md). Name it in one
line: the function, and the spec line it implements.

If that box is a stage's `Expands at gate` placeholder, this is a stage start — go to §2.

Build order lives in the backlog, not the specs. Steps within a stage come from the spec — do not
invent granularity:

- **Validation stage** → the rule→test table in [`docs/specs/07-testing.md`](../../../docs/specs/07-testing.md) §1,
  top to bottom. One row is one step.
- **Other stages** → the numbered sections of that stage's spec, in order.
- **Scaffolding** (`pyproject.toml`, package skeleton) → no test, budget exempt, still one box per step.

If a stage's spec cannot be broken into steps — silent, ambiguous, or contradicting another spec —
that is a spec bug (Rule 6). Stop and say so rather than choosing for Homa.

## 2. Decision gate — first step of a stage only

Before the first line of a new stage's code, list every real choice the **whole stage** contains:
the options, one line of tradeoff each, and a recommendation — and the stage's steps, one line
each, derived from its spec. Then **wait**. Do not write code in the same turn.

On approval, replace the stage's placeholder in `BACKLOG.md` with one box per approved step and log
the resolved decisions (§5). Then take the stage's first step.

A choice is real if a competent engineer could decide differently *and the result would differ*.
Field ordering, variable names and file placement are not decisions — do not pad the gate with
them. If the stage contains no real choices, say so in one line — an honest empty gate is fine, a
fabricated one is not. The step list still needs Homa's approval before the backlog expands.

Mid-stage, a newly surfaced decision is a hard stop, not a judgement call.

## 3. Write it

Test and implementation together, in one diff. The test is the readable contract, so it gets no
separate approval gate.

- ≤50 new lines total, ≤1 new file. Over budget → split it. If it genuinely cannot be split, state
  the line count and the reason and wait for a yes.
- Each function names its spec line in the docstring.
- `# why not X:` on non-obvious lines — one line, the alternative and why it loses.
- Nothing the spec did not ask for. No helper with one caller.

## 4. Tick, then read back — at most 4 lines

Tick the step's box in `BACKLOG.md` first, so the tick lands in the same commit as the code.

- what landed, as `path:line`
- the why-not for the one real choice inside it
- the next step, singular — a recommendation, not a menu

Then propose the commit message — spec ref plus the why-not line — covering the code **and** the
tick. This repo treats `git log -p` as the reasoning record. **Do not commit unless Homa says so.**

Never restate the diff in prose. It is on screen.

## 5. Log and park

- A decision resolved during this step → one entry in
  [`docs/decisions.md`](../../../docs/decisions.md), in the existing format.
- Anything noticed that is out of scope → one line under *Parked* in `BACKLOG.md`, and **not acted
  on now**. Tag later-phase items `→ Phase N`; Homa moves them to `ROADMAP.md`.

## Not this skill's job

- **Leanness audits** — `/simplify` already does that. Run it at stage boundaries, not per step.
- **Bug hunting** — `/code-review` at stage boundaries.
- **Pulling later-phase work forward** — Rule 6. Stop and report instead.
- **Reordering, deleting or re-scoping backlog items** — Homa's. The only backlog writes are ticking
  a box, expanding a stage at its approved gate, and appending to *Parked*.
