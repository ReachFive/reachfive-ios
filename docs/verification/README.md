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
read the report. **Every new failure falls into exactly one of two kinds**, and
the whole maintenance effort is telling them apart:

- **Real doc bug** — the snippet genuinely misuses the API (wrong label, order,
  type, renamed/removed method). *Fix the `.adoc`/example snippet*, or, if it is
  deferred to a later task, add its stem to `baseline.txt` (or run
  `--update-baseline`) so CI stays green meanwhile.
- **Harness gap** — the snippet is fine but the harness lacks context. *Fix the
  harness*, never the baseline. Pick the remedy by the compiler message:

  | Compiler error | Cause | Fix |
  |---|---|---|
  | `cannot find 'x' in scope` | ambient value assumed from prose / a previous snippet (`profileAuthToken`, `window`, …) | add `let x: <API type> = __placeholder()` to `Fixtures.swift`, using the type the API expects (grep the SDK signature) |
  | `cannot find 'MyX' in scope`, unknown placeholder constant | reader-supplied scaffolding (a native SDK, `DOMAIN`, …) or a type defined on another doc page | add a stub to the *Scaffolding* section of `Fixtures.swift` |
  | `... .Type` does not conform / is not a `UIViewController` | snippet uses `self` as a presentation context | it must be wrapped as a `DocExampleContext` subclass (imperative snippets already are) |
  | `only available in iOS N` | snippet calls a newer API without a guard | raise the wrapper's `@available` in `generate.py` |
  | `unavailable in Mac Catalyst` | API can't exist on the Catalyst target | add the stem to `SKIP`; note it needs an iOS Simulator run |
  | placeholder in an unusual position not resolved | generator didn't recognise the placeholder shape | extend the placeholder rules in `generate.py` |

**Key rule:** a fixture stub must carry the type the API actually expects — a
wrong type turns a harness gap into a false positive. When in doubt, grep the
real signature in `Sources/Core/` first (this is exactly how the current
fixtures were typed). After any change, re-run `check.sh` until only real bugs
remain, then commit.

The `doc-examples-harness` skill (`.claude/skills/`) walks through this triage
step by step.

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
