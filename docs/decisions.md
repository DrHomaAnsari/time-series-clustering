---
name: decisions
status: living
last-reviewed: 2026-09-27
---

# Decision log

Implementation decisions the specs leave open. Append-only, newest last, one short entry each.

This file is **not** a second source of truth. If a decision contradicts a spec, the spec changes
instead — see Rule 2 in [`CLAUDE.md`](../CLAUDE.md). What lands here is only what the specs are
genuinely silent about, plus the reasoning that would otherwise be lost between commits.

---

### 2026-09-21 · process · Who writes the implementation code
**Chose:** Claude writes all code, in steps small enough to read the whole diff.
**Over:** Claude writes tests and signatures while Homa fills the bodies; or Homa writes and Claude tutors.
**Because:** speed matters at this stage, and a 50-line cap makes full review cheap enough that authorship is not the thing protecting comprehension — diff size is.
**Spec:** open — specs are silent on process.

### 2026-09-21 · process · Step granularity and budget
**Chose:** one function plus its test, ≤50 new lines combined, ≤1 new file.
**Over:** one pipeline stage per step (~100–250 lines); or one spec section per step.
**Because:** 50 lines is the size that gets read rather than skimmed. [`07-testing.md`](specs/07-testing.md) §1 already enumerates 21 rule→test pairs, so the ladder exists and needs no invention.
**Spec:** open. Note the known cost — the config schema and run-summary writer will not fit in one step and must be split or explicitly over-budget.

### 2026-09-21 · process · Decisions batch per stage, not per function
**Chose:** resolve every real choice in a stage before its first line of code; ungated function-by-function after that; a new mid-stage decision is a hard stop.
**Over:** a decision gate on every step.
**Because:** per-function gating on a 50-line step would stall on boilerplate and train both of us to click through the gate, which destroys its value.
**Spec:** open.

### 2026-09-21 · process · Enforcement is advisory, not blocking
**Chose:** hooks that warn on budget overrun and on an un-updated decision log.
**Over:** hooks that reject the edit outright; or instructions with no enforcement.
**Because:** instructions in context drift over a long session and the model cannot notice its own drift; a blocking hook would also fire on legitimate over-budget steps that were agreed in advance.
**Spec:** open.

### 2026-09-26 · process · Build order
**Chose:** stage by stage in pipeline order, each fully built and tested before the next — validation first, simulation second, config core third.
**Over:** a thin end-to-end walking skeleton deepened later; simulation first, as `04-simulation.md` literally said.
**Because:** validation is pure pandas and already laddered as 21 rule→test rows, ideal for calibrating the 50-line budget, and its contract tests build frames inline so it needs no simulated data. The late-integration risk of depth-first is covered by a heavy-dependency smoke test at stage 0.
**Spec:** `04-simulation.md` amended to "built early — immediately after validation"; the rest of the order is open.

### 2026-09-26 · process · Backlog shape, and who writes it
**Chose:** one `BACKLOG.md` for order and progress; all stages listed now, each expanded into steps at its approved gate. Claude ticks one box per step in the same commit as the code, expands only at a gate, parks out-of-scope items, and never reorders or re-scopes. Gates stay in chat via `/step`.
**Over:** a separate `plan.md` beside a status list; every Phase 1 step enumerated up front; GitHub Issues; gates run in plan mode.
**Because:** a plan kept apart from its status drifts; steps enumerated past stage 2 would be guesses that churn; a tick in the same commit cannot disagree with the code; plan mode's workflow produces heavier gates than "options, tradeoff, recommendation".
**Spec:** open — specs are silent on process.

### 2026-09-27 · process · Spec style
**Chose:** one home per fact, linked from elsewhere; each rule keeps its reason in one sentence; plain "must"/"never" instead of stacked emphasis; no history, self-description or "Related specs" footers in spec text; section numbers, rule ids and test names never renumbered.
**Over:** self-contained specs that restate shared rules; bold, capitals and repetition to signal priority.
**Because:** restated rules drift apart — the specs' own "each value appears exactly once", applied to themselves. Reasons stay because they are what lets a model extend a rule to cases the spec did not foresee; emphasis goes because a model that follows instructions precisely over-applies whatever is shouted, and when everything is bold nothing is. Anchors stay fixed because `BACKLOG.md` and `/step` point at them.
**Spec:** open — specs are silent on their own style. Recorded as a rule in `CLAUDE.md` § Working with the specs.

### 2026-09-27 · stack · Parquet engine
**Chose:** Parquet written with pyarrow.
**Over:** fastparquet; Feather (Arrow IPC); pandas' dependency-free writers (CSV, JSON, pickle, SQLite); tables kept in memory only.
**Because:** only pyarrow reliably restores datetime column labels (else E010 fires on our own data) and `Int64` with `pd.NA` (else "dropped" collapses toward noise), and keeps the fingerprint stable across a reread. Pickle is lossless but pandas-version-bound and runs code on load; Feather is equally lossless but has less reach in other tools; in-memory only fails the Phase 1 exit.
**Spec:** `tech-stack.md` amended — pyarrow added to the libraries table and removed from Open; `07-testing.md` Artifacts row gains the round-trip assertion that pins the lossless claim.
