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
docs/verification/check.sh
```

Requires Xcode. Uses a **Mac Catalyst** destination — it gives UIKit on macOS
without a simulator runtime — and **whole-module** compilation (batch mode only
reports a non-deterministic subset of failures).

## Known limitations (current prototype)

- **2 snippets are excluded** (`SKIP` in `generate.py`): `logout` (placeholder in
  argument position) and `providerCreator` (top-level fragment referencing the
  Google/Facebook/WeChat provider pods, which aren't in the `Reach5` module).
  These need a doc-side cleanup before they can be checked.
- **Undefined ambient identifiers** (`profileAuthToken`, `window`,
  `verificationCode`, …) that snippets assume from prose or a previous snippet
  currently surface as `cannot find 'x' in scope`. A typed fixtures layer would
  resolve these; it's also a signal that the snippet isn't self-contained.
- **`self`-in-wrapper artifacts**: snippets meant to run inside a
  `UIViewController` (using `self` as a presentation anchor) fail because the
  wrapper is an `enum`. Wrapping those in a `UIViewController` subclass instead
  would fix it.
