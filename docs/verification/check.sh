#!/bin/bash
# Type-checks the documentation code examples against the real Reach5 public API.
#
# Mechanism:
#   1. generate.py wraps each docs/modules/ROOT/examples/*.swift fragment into a
#      compilable Swift file under Sources/ (namespaced, placeholders stubbed).
#   2. The DOC_EXAMPLES-gated `DocExamples` SPM target compiles them against Reach5.
#   3. Whole-module mode is REQUIRED: Swift's default batch mode reports only a
#      non-deterministic subset of errors when several files fail.
#
# A broken example (renamed/removed API, wrong argument label or order, wrong
# type) fails the build.
set -euo pipefail
cd "$(dirname "$0")/../.."

python3 docs/verification/generate.py

export DOC_EXAMPLES=1
xcodebuild \
  -scheme DocExamples \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  SWIFT_COMPILATION_MODE=wholemodule \
  clean build \
  2>&1 | tee /tmp/docexamples_build.log | grep " error:" | sed -E 's|.*/Sources/||' | sort -u || true

if grep -q " error:" /tmp/docexamples_build.log; then
  echo "❌ Some documentation examples no longer compile (see above)."
  exit 1
fi
echo "✅ All checked documentation examples compile against the current API."
