---
name: doc-examples-harness
description: Maintain and evolve the ReachFive documentation code-example verification harness under docs/verification/. Use when a doc code example is added or changed, when the check-doc-examples CI job fails, or when triaging its report — it decides real doc bug vs. harness gap and applies the right fix (fixtures, generator, baseline). Triggers include "doc example check", "check-doc-examples failed", "add a fixture", "update the examples baseline".
---

# Maintaining the doc-examples verification harness

This harness type-checks the Swift snippets in `docs/modules/ROOT/examples/*.swift`
against the real `Reach5` API. Read `docs/verification/README.md` once for the
mechanism; this skill is the maintenance procedure.

## 1. Run it and read the report

```bash
docs/verification/check.sh          # writes + prints docs/verification/report.md
```

Exit 0 = no new failure (failing set ⊆ `baseline.txt`); exit 1 = at least one new
failure. The report groups failures as **new** (regressions) and **known**
(baselined). Work only the new ones.

## 2. Triage each new failure: real doc bug vs. harness gap

This is the whole job. Decide which kind it is before touching anything.

### Real doc bug — the snippet genuinely misuses the API
Signals: `argument '…' must precede`, `extraneous/incorrect/missing argument
label`, `cannot convert value of type … to expected argument type …`, `has no
member`, `missing argument for parameter`.
- **Fix the example** in `docs/modules/ROOT/examples/…` (verify the correct call
  against `Sources/Core/`), **or**
- if the fix is deferred, add the example stem to `baseline.txt` so CI stays
  green. Never baseline a *harness gap*.

### Harness gap — the snippet is fine, the harness lacks context
Fix the harness by the message. Never touch the baseline for these.

| Compiler error | Fix |
|---|---|
| `cannot find 'x' in scope` (a value assumed from prose / an earlier snippet, e.g. `profileAuthToken`, `window`) | add `let x: <API type> = __placeholder()` to the ambient section of `Fixtures.swift` |
| `cannot find 'MyX'` / unknown placeholder constant (`DOMAIN`, a native SDK, a type defined on another doc page) | add a stub to the *Scaffolding* section of `Fixtures.swift` |
| `… .Type` does not conform / is not a `UIViewController` (snippet uses `self`) | ensure it is wrapped as a `DocExampleContext` subclass; imperative snippets already are — check `generate.py` |
| `only available in iOS N` | raise the wrapper's `@available` in `generate.py` |
| `unavailable in Mac Catalyst` | add the stem to `SKIP` in `generate.py`; note it would need an iOS Simulator run |
| a placeholder in an unusual position isn't resolved | extend the placeholder regexes in `generate.py` |

## 3. Type fixtures correctly — the one rule that prevents false positives

A fixture stub **must carry the exact type the API expects**. A wrong type turns
a harness gap into a false positive (or masks a real bug). Always confirm the
signature first:

```bash
grep -rn "func <method>" Sources/Core/Classes/     # method signature
grep -rn "case <Case>\|enum <Enum>" Sources/Core/  # enum case / associated types
```

Then declare the fixture with that type (e.g. `let window: ASPresentationAnchor`,
`let profile: ProfilePasskeySignupRequest`). Keep new fixtures compilable on
`master` too (only reference SDK types that exist there).

## 4. Close the loop

- Re-run `check.sh` until only genuine doc bugs remain.
- If the set of real bugs changed intentionally (fixed or newly deferred), run
  `docs/verification/check.sh --update-baseline` and review the diff of
  `baseline.txt`.
- Commit the harness change and the baseline together, with a message describing
  what was a real bug vs. a harness gap.

## Scope notes

- The check runs on **Mac Catalyst** (UIKit, no simulator) in **whole-module**
  mode; don't switch to batch mode (it under-reports).
- New example files often bring new ambient/scaffolding symbols — expanding
  `Fixtures.swift` is the expected, normal maintenance cost, not a workaround.
