#!/usr/bin/env bash
# Warn at the end of a turn when code changed but the decision log did not.
# Advisory only: never blocks the turn from ending.
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

[[ -n $(git status --porcelain -- src tests 2>/dev/null) ]] || exit 0
[[ -z $(git status --porcelain -- docs/decisions.md 2>/dev/null) ]] || exit 0

printf '{"systemMessage":"%s"}\n' \
  "Code under src/ or tests/ changed but docs/decisions.md did not. If a decision was resolved this step, log it."
