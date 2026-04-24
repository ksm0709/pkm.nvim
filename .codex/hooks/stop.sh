#!/usr/bin/env bash

exec 1>&2

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 2

if git diff --quiet HEAD && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  exit 0
fi

export PATH="$ROOT/.rocks/bin:$HOME/.cargo/bin:$PATH"

for cmd in stylua luacheck busted luacov; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed or not on PATH."
    exit 2
  fi
done

echo "Running quality gates..."

FMT_OUT=$(stylua --check lua plugin spec 2>&1) || {
  echo "Formatting check failed."
  echo "$FMT_OUT"
  exit 2
}
echo "Format check passed."

LINT_OUT=$(./.rocks/bin/luacheck lua plugin spec 2>&1) || {
  echo "Lint check failed."
  echo "$LINT_OUT"
  exit 2
}
echo "Lint check passed."

rm -f luacov.report.out luacov.stats.out
TEST_OUT=$(./.rocks/bin/busted --helper spec/spec_helper.lua --coverage spec 2>&1) || {
  echo "Tests failed."
  echo "$TEST_OUT"
  exit 2
}
echo "$TEST_OUT"

./.rocks/bin/luacov >/dev/null 2>&1 || {
  echo "Coverage report generation failed."
  exit 2
}

if [ ! -f luacov.report.out ]; then
  echo "Coverage report not found."
  exit 2
fi

COVERAGE=$(grep '^Total' luacov.report.out | awk '{print $NF}' | tr -d '%')
if [ -z "$COVERAGE" ]; then
  echo "Could not parse coverage."
  exit 2
fi

if awk "BEGIN {exit !($COVERAGE < 90.0)}"; then
  echo "Coverage is ${COVERAGE}%, below the 90% threshold."
  exit 2
fi
echo "Coverage threshold passed (${COVERAGE}%)."

CHANGED_FILES=$( (git diff HEAD --name-only; git ls-files --others --exclude-standard) | sort -u )
LUA_CHANGED=$(printf '%s\n' "$CHANGED_FILES" | grep -E '^(lua/|plugin/|spec/)' || true)
DOC_CHANGED=$(printf '%s\n' "$CHANGED_FILES" | grep -E '^(README\.md|doc/)' || true)
if [ -n "$LUA_CHANGED" ] && [ -z "$DOC_CHANGED" ]; then
  echo "Documentation missing. Lua/plugin changes require README.md or doc/ updates."
  exit 2
fi
echo "Documentation check passed."

echo "All quality gates passed."
exit 0
