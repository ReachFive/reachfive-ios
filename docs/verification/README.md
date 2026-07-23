# Documentation example verification

Type-checks the Swift code examples embedded in the docs against the real
`Reach5` public API, so that a renamed/removed method, a wrong argument label or
order, or a wrong argument type breaks the build instead of silently shipping in
the documentation.

## How it works

The `.adoc` pages `include::` the snippets in
`docs/modules/ROOT/examples/*.swift`. Those snippets are *fragments*: they assume
an ambient app context (`AppDelegate.reachfive()`, a few helpers) and sometimes
contain `= // paste here` placeholders, so they can't be compiled directly.

1. **`generate.py`** wraps each fragment into a compilable Swift file under
   `Sources/`:
   - each snippet gets its own `enum` namespace (so top-level statements become
     legal and snippets defining the same type — e.g. `AppDelegate` — don't
     collide);
   - `let x: T = // paste…` placeholders become `let x: T = __placeholder()`
     (a generic stub, type inferred from the annotation);
   - empty `switch` cases (`// Handle error` only) get a `break`.
2. **`Fixtures.swift`** provides the ambient context as compile-only stubs
   (`AppDelegate.reachfive()`, `__placeholder<T>()`, …). Nothing is executed.
3. The **`DocExamples`** target (in the root `Package.swift`, gated behind the
   `DOC_EXAMPLES` env var so it never ships) compiles everything against `Reach5`.

## Running

```bash
docs/verification/check.sh                    # check; writes report.md
```
```bash
docs/verification/check.sh --update-baseline  # record current failures as baseline
```

Requires Xcode. Uses a **Mac Catalyst** destination — it gives UIKit on macOS
without a simulator runtime — and **whole-module** compilation (batch mode only
reports a non-deterministic subset of failures). Generated `Sources/E_*.swift`
files are removed at the end of every run.

`check.sh` exits 0 when the failing set is a subset of `baseline.txt` (no new
regression) and 1 otherwise. It runs in CI as the `check-doc-examples` job, which
prints the full report to the build log and also stores `report.md` as an
artifact.

## Baseline

`baseline.txt` lists the examples that currently fail because of **genuine bugs
in the doc snippets** (wrong argument label/order/type, renamed API). They are
tracked there so CI stays green while catching *new* regressions; fixing them is
a separate documentation task. Regenerate the baseline with `--update-baseline`
once the snippets are corrected.

## Maintenance

Whenever a doc example is added or changed, run `docs/verification/check.sh` and
read the report. Every new failure is either a **real doc bug** (fix the snippet,
or add its stem to `baseline.txt` if the fix is deferred) or a **harness gap**
(fix the harness — a `Fixtures.swift` stub, a `generate.py` tweak — never the
baseline).

The full triage procedure — how to tell the two apart from the compiler message,
which remedy each message calls for, and the rule that every fixture must carry
the exact type the API expects — lives in the **`doc-examples-harness` skill**
([`.claude/skills/doc-examples-harness/SKILL.md`](../../.claude/skills/doc-examples-harness/SKILL.md)),
the single source of truth for maintaining this harness. If you use Claude Code,
invoke that skill and point it at a failing `check-doc-examples` run: it
classifies each new failure (real doc bug vs. harness gap), applies the right fix,
and re-runs the check until only genuine doc bugs remain.

## Known limitations

- **2 snippets are excluded** (`SKIP` in `generate.py`): `providerCreator`
  (top-level fragment referencing the Google/Facebook/WeChat provider pods,
  absent from the `Reach5` module) and `beginAutoFillAssistedPasskeyLogin`
  (`@available(macCatalyst, unavailable)`). Placeholders in argument position or
  in untyped `let`s are handled by the generator, so snippets like `logout` are
  checked.
- **Mac Catalyst coverage gap**: APIs marked unavailable on Catalyst can't be
  checked here. Adding an iOS Simulator destination would close the gap at the
  cost of a simulator runtime.
- **Ambient values** the snippets assume (`profileAuthToken`, `window`, …) are
  provided as typed stubs in `Fixtures.swift`; a new such identifier in a future
  snippet must be added there.
