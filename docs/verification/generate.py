#!/usr/bin/env python3
"""Generate compilable Swift files from the doc example fragments.

Each fragment in docs/modules/ROOT/examples/*.swift is wrapped into its own
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
    "logout",           # `presentationContextProvider: // …` placeholder in argument position
    "providerCreator",  # top-level fragment; references provider pods (Google/Facebook/WeChat)
    # `beginAutoFillAssistedPasskeyLogin` is @available(macCatalyst, unavailable),
    # so it cannot be type-checked on the Catalyst target. It would be covered by
    # an iOS Simulator run.
    "beginAutoFillAssistedPasskeyLogin",
}

DECL_RE = re.compile(r'^\s*(public\s+|final\s+|open\s+)*(class|struct|enum|protocol|extension)\b')
PLACEHOLDER_RE = re.compile(r'=\s*//.*$', re.M)    # `let x: T = // paste…`
APPDELEGATE_CLASS_RE = re.compile(r'(class\s+AppDelegate\b[^{]*\{)')


def sanitize(stem: str) -> str:
    return "E_" + re.sub(r'[^0-9A-Za-z_]', '_', stem)


def first_significant_line(lines):
    for l in lines:
        s = l.strip()
        if s and not s.startswith("//"):
            return s
    return ""


CASE_RE = re.compile(r'^\s*(case\b.*|default\s*):\s*$')


def fix_empty_cases(body: str) -> str:
    """A `switch` case whose body is only a comment is illegal Swift.
    These appear in illustrative snippets (`// Handle error`). Inject a `break`
    so the *API call* driving the switch can still be type-checked."""
    lines = body.splitlines()
    out = []
    for i, line in enumerate(lines):
        out.append(line)
        if CASE_RE.match(line):
            indent = line[: len(line) - len(line.lstrip())]
            # Look at following lines until the next case/label or block end.
            body_is_empty = True
            for nxt in lines[i + 1:]:
                s = nxt.strip()
                if s == "" or s.startswith("//"):
                    continue
                if CASE_RE.match(nxt) or s.startswith("}"):
                    break
                body_is_empty = False
                break
            if body_is_empty:
                out.append(indent + "    break")
    return "\n".join(out)


def transform(path: Path) -> str:
    raw = path.read_text()
    lines = [l for l in raw.splitlines() if not l.strip().startswith("import ")]
    body = "\n".join(lines).replace("@UIApplicationMain", "")

    # Replace `= // comment` placeholders with a typed stub value.
    body = PLACEHOLDER_RE.sub("= __placeholder()", body)
    body = fix_empty_cases(body)

    ns = sanitize(path.stem)
    is_decl = bool(DECL_RE.match(first_significant_line(body.splitlines())))

    # Imports are per-file in Swift, so every generated file re-imports the
    # modules the snippets assume (Fixtures.swift can't provide them).
    header = f"// Generated from examples/{path.name}\nimport Foundation\nimport UIKit\nimport Reach5\n\n"

    # Several examples call iOS 16+ passkey APIs without an availability guard
    # (the docs assume the reader wraps them in `if #available`). Raise the
    # wrapper's availability instead of flagging that as an error.
    avail = "@available(iOS 16.0, macCatalyst 16.0, *)\n"

    if is_decl:
        # A snippet that defines its own AppDelegate calls AppDelegate.reachfive()
        # on that nested type; inject a stub so the SDK calls type-check.
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
    for path in sorted(EXAMPLES.glob("*.swift")):
        if path.stem in SKIP:
            skipped += 1
            continue
        (OUT / f"{sanitize(path.stem)}.swift").write_text(transform(path))
        count += 1
    print(f"Generated {count} files into {OUT} ({skipped} skipped: {', '.join(sorted(SKIP))})")


if __name__ == "__main__":
    main()
