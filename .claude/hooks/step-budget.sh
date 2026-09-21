#!/usr/bin/env bash
# Warn when a step exceeds the line budget in CLAUDE.md "How we work".
# Advisory only: never blocks a tool call, never fails one.
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

# The budget is read out of CLAUDE.md so there is one number to tune, not two.
budget=$(grep -oE 'Budget: ≤[0-9]+ new lines' CLAUDE.md 2>/dev/null | grep -oE '[0-9]+' | head -1)
[[ -n ${budget:-} ]] || budget=50

# Net added lines of implementation and test code. Scaffolding, docs and .claude/
# are outside src/ and tests/, so they are exempt without needing a special case.
added=$(git diff --numstat HEAD -- src tests 2>/dev/null | awk '{s+=$1} END {print s+0}')
while IFS= read -r f; do
  [[ -f $f ]] && added=$((added + $(wc -l <"$f")))
done < <(git ls-files --others --exclude-standard -- src tests 2>/dev/null)

((added > budget)) || exit 0

msg="Step budget: ${added} added lines under src/ and tests/ against a budget of ${budget}. Split the step, or state the count and the reason and wait for a yes."
# why not jq: the message is numbers plus fixed ASCII, so it needs no escaping.
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
  "$msg" "$msg"
