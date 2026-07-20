#!/usr/bin/env python3
"""Turn a DocExamples build log into a human-readable report.

Reads the xcodebuild log, groups the compiler errors by documentation example,
compares the failing set against a committed baseline of already-known-broken
examples, and writes a Markdown report.

Exit code: 0 if there are no *new* failures (failing set ⊆ baseline), 1 otherwise.
Use --update-baseline to rewrite the baseline from the current failing set.
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASELINE = HERE / "baseline.txt"
REPORT = HERE / "report.md"
ERROR_RE = re.compile(r'E_([A-Za-z0-9_]+)\.swift:(\d+):\d+: error: (.*)')


def parse(log_text):
    """example stem -> list of (line, message), de-duplicated and ordered."""
    failures = {}
    seen = set()
    for m in ERROR_RE.finditer(log_text):
        stem, line, msg = m.group(1), int(m.group(2)), m.group(3).strip()
        key = (stem, line, msg)
        if key in seen:
            continue
        seen.add(key)
        failures.setdefault(stem, []).append((line, msg))
    return failures


def read_baseline():
    if not BASELINE.exists():
        return set()
    return {l.strip() for l in BASELINE.read_text().splitlines() if l.strip() and not l.startswith("#")}


def write_report(failures, baseline, checked):
    new = sorted(set(failures) - baseline)
    fixed = sorted(baseline - set(failures))
    lines = []
    lines.append("# Documentation examples — API check report\n")
    lines.append(f"- Examples checked: **{checked}**")
    lines.append(f"- Compiling cleanly: **{checked - len(failures)}**")
    lines.append(f"- Failing (known, in baseline): **{len(set(failures) & baseline)}**")
    lines.append(f"- Failing (NEW, not in baseline): **{len(new)}**")
    lines.append(f"- Baseline entries now fixed: **{len(fixed)}**\n")

    if new:
        lines.append("## 🔴 New failures (regressions — must be addressed)\n")
        for stem in new:
            lines.append(f"### `examples/{stem}.swift`")
            for ln, msg in failures[stem]:
                lines.append(f"- L{ln}: {msg}")
            lines.append("")

    if fixed:
        lines.append("## 🟢 Baseline entries now passing (remove from baseline)\n")
        for stem in fixed:
            lines.append(f"- `examples/{stem}.swift`")
        lines.append("")

    known = sorted(set(failures) & baseline)
    if known:
        lines.append("## 🟡 Known failures (baseline — to fix in the docs)\n")
        for stem in known:
            lines.append(f"### `examples/{stem}.swift`")
            for ln, msg in failures[stem]:
                lines.append(f"- L{ln}: {msg}")
            lines.append("")

    text = "\n".join(lines) + "\n"
    REPORT.write_text(text)
    return text


def main():
    update = "--update-baseline" in sys.argv
    log_text = sys.stdin.read()
    try:
        checked = int([a for a in sys.argv if a.startswith("--checked=")][0].split("=")[1])
    except IndexError:
        checked = 0

    failures = parse(log_text)

    if update:
        BASELINE.write_text(
            "# Documentation examples that currently fail the API check because of\n"
            "# genuine bugs in the doc snippets (wrong argument label/order/type,\n"
            "# renamed API…). To be fixed in a dedicated task. One example stem per line.\n"
            + "".join(f"{s}\n" for s in sorted(failures))
        )
        print(f"Baseline updated: {len(failures)} known-failing examples.")
        return 0

    baseline = read_baseline()
    text = write_report(failures, baseline, checked)
    new = sorted(set(failures) - baseline)

    # Print the full report to stdout so it is visible directly in the CI log
    # (not only in the stored report.md artifact).
    print(text)
    if new:
        print("❌ New failures (not in baseline): " + ", ".join(new))
        return 1
    print("✅ No new failures (all failures are known/baselined).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
