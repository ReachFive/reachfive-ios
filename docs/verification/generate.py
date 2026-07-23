#!/usr/bin/env python3
"""Generate compilable Swift files from the doc example fragments.

Each fragment in docs/modules/ROOT/examples/**/*.swift is wrapped into its own
namespace so that (a) top-level statements become legal and (b) snippets that
define the same type (e.g. AppDelegate) don't collide in a single module.

Output goes to docs/verification/Sources/ next to Fixtures.swift and is compiled
as the SPM `DocExamples` target against the real `Reach5` module.
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXAMPLES = HERE.parent / "modules" / "ROOT" / "examples"
OUT = HERE / "Sources"

# Snippets that are intentionally incomplete pseudo-code and cannot be
# type-checked against the Reach5 module alone. Each needs a doc-side cleanup
# before it can be verified (see docs/verification/README.md).
SKIP = {
    "providerCreator",  # top-level fragment; references provider pods (Google/Facebook/WeChat)
    # `beginAutoFillAssistedPasskeyLogin` is @available(macCatalyst, unavailable),
    # so it cannot be type-checked on the Catalyst target. It would be covered by
    # an iOS Simulator run.
    "beginAutoFillAssistedPasskeyLogin",
}

DECL_RE = re.compile(r'^\s*(public\s+|final\s+|open\s+)*(class|struct|enum|protocol|extension)\b')
# A line that is *only* an attribute (`@main`, `@available(iOS 16, *)`), and the
# leading attribute(s) of an inline decl (`@MainActor class Foo`). Used so that
# an attribute-led declaration is still classified as a declaration.
ATTR_ONLY_RE = re.compile(r'@\w+(\([^)]*\))?$')
ATTR_PREFIX_RE = re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)+')
# Placeholders come in three shapes. Each is replaced by a value whose type the
# compiler can infer from context, so the *API call* still gets type-checked:
#   let x: T = // paste…          ->  let x: T = __placeholder()   (typed let)
#   foo(label: // provide…)       ->  foo(label: __placeholder())  (argument position)
#   let x = // obtain…            ->  (line dropped; x resolves to an ambient global)
UNTYPED_PLACEHOLDER_RE = re.compile(r'^[ \t]*let\s+\w+\s*=\s*//.*$')
# `label: // …` in argument position — but never a switch `default:` label, whose
# colon looks the same yet must keep its `break` (see fix_empty_cases).
ARG_PLACEHOLDER_RE = re.compile(r'^([ \t]*(?!default\b)[A-Za-z_]\w*:[ \t]*)//.*$')
PLACEHOLDER_RE = re.compile(r'=\s*//.*$')
APPDELEGATE_CLASS_RE = re.compile(r'(class\s+AppDelegate\b[^{]*\{)')
CASE_START_RE = re.compile(r'^\s*(case|default)\b')


def rel_stem(path: Path) -> str:
    """Path relative to EXAMPLES, without extension, e.g. 'application/applicationOpenUrl'."""
    return str(path.relative_to(EXAMPLES).with_suffix(""))


def sanitize(stem: str) -> str:
    return "E_" + re.sub(r'[^0-9A-Za-z_]', '_', stem)


def first_significant_line(lines):
    for l in lines:
        s = l.strip()
        if not s or s.startswith("//"):
            continue
        if ATTR_ONLY_RE.match(s):  # a line bearing only an attribute
            continue
        return s
    return ""


def resolve_placeholders(body: str) -> str:
    """Replace the `= // paste…` / `label: // provide…` placeholder shapes with a
    typed stub, working line by line so a `= //` inside a string literal is left
    untouched (it is not a placeholder)."""
    out = []
    for line in body.splitlines():
        # `let x = // obtain…` → drop; x resolves to an ambient global in Fixtures.
        if UNTYPED_PLACEHOLDER_RE.match(line):
            continue
        # `foo(label: // provide…)` → argument-position placeholder.
        m = ARG_PLACEHOLDER_RE.match(line)
        if m:
            out.append(m.group(1) + "__placeholder()")
            continue
        # `let x: T = // paste…` (or any assignment) → typed placeholder, unless the
        # `= //` lives inside a string literal (a quote precedes it on the line).
        m = PLACEHOLDER_RE.search(line)
        if m and '"' not in line[:m.start()]:
            line = line[:m.start()] + "= __placeholder()"
        out.append(line)
    return "\n".join(out)


def _case_label_span(lines, i):
    """If lines[i] begins a `case`/`default` label, return (end_index, has_inline_body)
    where end_index carries the terminating ':' (a label may span several lines,
    each ending in ','). Return None if lines[i] does not start a label."""
    if not CASE_START_RE.match(lines[i]):
        return None
    j = i
    while j < len(lines):
        code = lines[j].split("//", 1)[0].rstrip()
        pos = code.rfind(":")
        if pos != -1:
            return j, bool(code[pos + 1:].strip())
        if not code.endswith(","):
            # No ':' and no comma-continuation → not a simple label we can reason
            # about; treat as already having a body (inject nothing).
            return j, True
        j += 1
    return len(lines) - 1, True


def fix_empty_cases(body: str) -> str:
    """A `switch` case whose body is only a comment is illegal Swift.
    These appear in illustrative snippets (`// Handle error`). Inject a `break`
    so the *API call* driving the switch can still be type-checked. Handles
    single-line, inline-comment, inline-body and multi-line case labels."""
    lines = body.splitlines()
    out = []
    i = 0
    n = len(lines)
    while i < n:
        span = _case_label_span(lines, i)
        if span is None:
            out.append(lines[i])
            i += 1
            continue
        end, has_inline_body = span
        indent = lines[i][: len(lines[i]) - len(lines[i].lstrip())]
        out.extend(lines[i:end + 1])
        if not has_inline_body:
            body_is_empty = True
            for nxt in lines[end + 1:]:
                s = nxt.strip()
                if s == "" or s.startswith("//"):
                    continue
                body_is_empty = CASE_START_RE.match(nxt) is not None or s.startswith("}")
                break
            if body_is_empty:
                out.append(indent + "    break")
        i = end + 1
    return "\n".join(out)


def transform(path: Path) -> str:
    raw = path.read_text()
    lines = [l for l in raw.splitlines() if not l.strip().startswith("import ")]
    body = "\n".join(lines).replace("@UIApplicationMain", "")

    body = resolve_placeholders(body)
    body = fix_empty_cases(body)

    ns = sanitize(rel_stem(path))
    sig = ATTR_PREFIX_RE.sub("", first_significant_line(body.splitlines()))
    is_decl = bool(DECL_RE.match(sig))

    # Imports are per-file in Swift, so every generated file re-imports the
    # modules the snippets assume (Fixtures.swift can't provide them).
    rel = path.relative_to(EXAMPLES)
    header = f"// Generated from examples/{rel}\nimport Foundation\nimport UIKit\nimport Reach5\n\n"

    # Several examples call iOS 16+ passkey APIs without an availability guard
    # (the docs assume the reader wraps them in `if #available`). Raise the
    # wrapper's availability instead of flagging that as an error.
    avail = "@available(iOS 16.0, macCatalyst 16.0, *)\n"

    if is_decl:
        # A snippet that defines its own AppDelegate calls AppDelegate.reachfive()
        # on that nested type; inject a stub so the SDK calls type-check — unless
        # the snippet already defines reachfive() itself (avoid a redeclaration).
        if "func reachfive" not in body:
            body = APPDELEGATE_CLASS_RE.sub(
                r"\1\n        static func reachfive() -> ReachFive { __placeholder() }",
                body,
            )
        inner = "\n".join("    " + l if l else l for l in body.splitlines())
        return f"{header}{avail}enum {ns} {{\n{inner}\n}}\n"
    else:
        # Wrap in a UIViewController subclass (not an enum) so that snippets
        # using `self` as a presentation context type-check. See DocExampleContext.
        inner = "\n".join("        " + l if l else l for l in body.splitlines())
        return (
            f"{header}{avail}class {ns}: DocExampleContext {{\n    func run() async throws {{\n{inner}\n    }}\n}}\n"
        )


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Clean previously generated files (keep Fixtures.swift).
    for f in OUT.glob("E_*.swift"):
        f.unlink()

    count = skipped = 0
    written = {}
    # rglob so examples in subdirectories (e.g. application/) are also checked.
    for path in sorted(EXAMPLES.rglob("*.swift")):
        if path.stem in SKIP:
            skipped += 1
            continue
        name = sanitize(rel_stem(path))
        if name in written:
            raise SystemExit(
                f"error: examples '{written[name]}' and '{path.relative_to(EXAMPLES)}' "
                f"both map to {name}.swift — rename one so they don't collide."
            )
        written[name] = path.relative_to(EXAMPLES)
        (OUT / f"{name}.swift").write_text(transform(path))
        count += 1
    print(f"Generated {count} files into {OUT} ({skipped} skipped: {', '.join(sorted(SKIP))})")


if __name__ == "__main__":
    main()
