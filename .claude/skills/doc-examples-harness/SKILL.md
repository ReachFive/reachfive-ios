---
name: doc-examples-harness
description: Maintain and evolve the ReachFive documentation code-example verification harness in docs/verification/ — the check-doc-examples CI job / check.sh that compiles the snippets in docs/modules/ROOT/examples against the Reach5 API. Use this whenever that check fails or a doc example stops compiling against the API, when adding or changing an example means keeping that check green, when adding a fixture to Fixtures.swift, regenerating the examples baseline.txt, or deciding whether a failure is a genuine doc bug or a harness gap. Trigger even when the harness isn't named — e.g. "the doc example check is red", "registerCustomProvider won't compile", "add a stub for MyNativeSDK so the examples build", "regenerate the examples baseline", "my SDK rename broke the doc example check". Not for: rewriting the prose of a doc page, building or debugging the Sandbox app, XCTest/unit-test fixtures or UI snapshot baselines, or the pod-lint CI job.
---

# Maintaining the doc-examples verification harness

This harness compiles the Swift snippets in `docs/modules/ROOT/examples/*.swift`
against the real `Reach5` API so a wrong call in the docs breaks the build. Your
job when this skill triggers is to keep that signal **trustworthy**: every
reported failure should be a real doc bug, and no real doc bug should be hidden.

Read `docs/verification/README.md` once for the mechanism (generator, fixtures,
Mac Catalyst, whole-module, baseline). This skill is the maintenance procedure —
what to do when the check moves.

## The one distinction that matters

Every failure is either a **real doc bug** or a **harness gap**. Getting this
call right is the whole task, because the two have opposite fixes and confusing
them corrupts the signal:

- Fix a harness gap by **baselining it** → you hide a real bug from everyone.
- "Fix" a real bug by **adding a permissive fixture** → same thing, you mask it.

So decide deliberately, using the compiler message, before you touch anything.

## Step 1 — Run it and read the report

```bash
docs/verification/check.sh          # writes + prints docs/verification/report.md
```

Exit 0 means the failing set ⊆ `baseline.txt` (no new problem); exit 1 means a
new failure. The report (also printed in the CI log) splits failures into
**new** and **known** — work the new ones.

## Step 2 — Classify each new failure

### Real doc bug — the snippet misuses the API
Tell-tale messages: `argument '…' must precede`, `extraneous / incorrect /
missing argument label`, `cannot convert value of type … to expected argument
type …`, `has no member`, `missing argument for parameter`.
→ Correct the example in `docs/modules/ROOT/examples/…` (confirm the right call
against `Sources/Core/`). If the fix is deferred to another task, add the stem to
`baseline.txt` so CI stays green — never baseline something that isn't a real bug.

### Harness gap — the snippet is fine, the harness lacks context
The compiler message points straight to the remedy:

| Message | Remedy |
|---|---|
| `cannot find 'x' in scope` — a value the snippet assumes from prose or an earlier snippet (`profileAuthToken`, `window`, `verificationCode`, …) | add `let x: <API type> = __placeholder()` to the ambient section of `Fixtures.swift` |
| `cannot find 'MyX'` / an unknown placeholder constant (`DOMAIN`, a native SDK the reader supplies, a type defined on another doc page) | add a stub to the *Scaffolding* section of `Fixtures.swift` |
| `… .Type` does not conform / is not a `UIViewController` — snippet uses `self` as a presentation context | it must be wrapped as a `DocExampleContext` subclass; imperative snippets already are, so check `generate.py` |
| `only available in iOS N` | raise the wrapper's `@available` in `generate.py` |
| `unavailable in Mac Catalyst` | add the stem to `SKIP` in `generate.py`; note it would need an iOS Simulator run to be covered |
| a placeholder in an unusual position isn't resolved | extend the placeholder regexes in `generate.py` |

## Step 3 — Type every fixture exactly

This is the rule that keeps the harness honest. A stub **must carry the type the
API actually expects**. Give it too permissive a type (`Any`, an optional where
the API is non-optional) and you either invent a false positive or, worse, mask a
real bug in that very call. So always confirm the signature first:

```bash
grep -rn "func <method>" Sources/Core/Classes/      # method signature
grep -rn "case <Case>\|enum <Enum>" Sources/Core/   # enum case + associated types
```

Then declare the fixture with that exact type (e.g. `let window:
ASPresentationAnchor`, `let profile: ProfilePasskeySignupRequest`). Keep new
fixtures compilable on `master` too — only reference SDK types that exist there.

## Worked example (a real case)

A new example, `customProviderWrappingNativeSDK.swift`, was added on a feature
branch. The check reported three errors on it:

```
L32: cannot find 'MyNativeSDK' in scope
L36: 'nil' is not compatible with expected argument type 'Pkce'
L40: cannot find 'MyNativeSDK' in scope
```

Triage:
- `MyNativeSDK` (L32/L40) — the example says "drive *your* native SDK here", so
  it's reader-supplied scaffolding → **harness gap**. Added a `MyNativeSDK` stub
  to `Fixtures.swift`, shaped so its call site type-checks (`func login(presenting:
  UIViewController) async throws -> String`, matching `Presentation.presentingViewController()`).
- `pkce: nil` (L36) — checked the signature: `authWithCode(code: String, pkce:
  Pkce, …)`. `pkce` is **non-optional**, so passing `nil` is a **real doc bug**.

After adding the stub, the two scaffolding errors vanished and the harness kept
reporting only the genuine `pkce: nil` bug — which is exactly the outcome you
want: gap removed, real bug still visible.

The lesson: new example files routinely introduce new ambient/scaffolding
symbols. Growing `Fixtures.swift` to absorb them is the normal, expected
maintenance cost — not a workaround — as long as each stub is typed against the
real API.

## Step 4 — Close the loop

- Re-run `check.sh` until only genuine doc bugs remain.
- If the set of real bugs changed on purpose (one fixed, or one newly deferred),
  run `docs/verification/check.sh --update-baseline` and **review the diff** of
  `baseline.txt` — it should change by exactly the examples you intended.
- Commit the harness change and the baseline together, and say in the message
  which failures were real bugs vs. harness gaps, so the history stays legible.

## Scope reminders

- The check runs on **Mac Catalyst** (UIKit, no simulator) in **whole-module**
  mode. Don't switch to batch mode — it under-reports failures non-deterministically.
- Two example categories can't be fully checked here and live in `SKIP`:
  provider-pod examples (Google/Facebook/WeChat aren't in the SPM module) and
  Catalyst-unavailable APIs. Extending coverage to those means adding an iOS
  Simulator destination, which trades speed for completeness.
