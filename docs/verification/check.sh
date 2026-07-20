#!/bin/bash
# Type-checks the documentation code examples against the real Reach5 public API.
#
# Mechanism:
#   1. generate.py wraps each docs/modules/ROOT/examples/*.swift fragment into a
#      compilable Swift file under Sources/ (namespaced, placeholders stubbed).
#   2. The DOC_EXAMPLES-gated `DocExamples` SPM target compiles them against Reach5.
#   3. Whole-module mode is REQUIRED: Swift's default batch mode reports only a
#      non-deterministic subset of errors when several files fail.
#   4. report.py writes report.md and compares the failing set against baseline.txt.
#
# Exit 0 when there are no *new* failures (all failures are baselined), 1 otherwise.
# Pass --update-baseline to record the current failing set as the new baseline.
#
# Requires Xcode. Uses a Mac Catalyst destination (UIKit on macOS, no simulator).
set -uo pipefail
cd "$(dirname "$0")/../.."

GEN="docs/verification/Sources"
LOG="$(mktemp)"

# Always remove the generated example files, even on failure.
cleanup() { rm -f "$GEN"/E_*.swift; }
trap cleanup EXIT

python3 docs/verification/generate.py
CHECKED=$(ls "$GEN"/E_*.swift 2>/dev/null | wc -l | tr -d ' ')

export DOC_EXAMPLES=1
xcodebuild \
  -scheme DocExamples \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  SWIFT_COMPILATION_MODE=wholemodule \
  clean build > "$LOG" 2>&1 || true

python3 docs/verification/report.py --checked="$CHECKED" "$@" < "$LOG"
