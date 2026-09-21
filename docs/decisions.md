---
name: decisions
status: living
last-reviewed: 2026-09-21
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
