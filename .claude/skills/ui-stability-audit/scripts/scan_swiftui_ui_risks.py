#!/usr/bin/env python3
import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


SKIP_DIR_NAMES = {
    ".build",
    ".git",
    ".swiftpm",
    "Build",
    "Carthage",
    "DerivedData",
    "Pods",
    "SourcePackages",
    "xcuserdata",
}


@dataclass(frozen=True)
class Rule:
    code: str
    severity: str
    pattern: re.Pattern
    message: str


@dataclass(frozen=True)
class Finding:
    severity: str
    code: str
    path: str
    line: int
    message: str
    snippet: str


RULES = [
    Rule(
        code="contrast-hardcoded-foreground",
        severity="high",
        pattern=re.compile(
            r"\.(foregroundColor|foregroundStyle|tint)\(\s*(?:Color\.)?(?:white|black)(?:\b|\.opacity\()"
        ),
        message="Replace hardcoded foreground color with a semantic token resolved by surface and color scheme.",
    ),
    Rule(
        code="contrast-hardcoded-fill",
        severity="medium",
        pattern=re.compile(
            r"\.(fill|background)\(\s*(?:Color\.)?(?:white|black)(?:\b|\.opacity\()"
        ),
        message="Review neutral fill/background usage; verify that text on top still passes contrast in light and dark mode.",
    ),
    Rule(
        code="layout-screen-bounds-width",
        severity="high",
        pattern=re.compile(r"UIScreen\.main\.bounds(?:\.size)?\.width"),
        message="Avoid global screen-width math for centered layouts. Prefer shared metrics or a centered-width helper.",
    ),
    Rule(
        code="layout-geometry-width-basis",
        severity="high",
        pattern=re.compile(r"\b(?:proxy|geometry|geo)\.size\.width\b"),
        message="Raw GeometryReader width is a common source of centering drift. Verify the width basis is stable across safe-area asymmetry.",
    ),
    Rule(
        code="layout-safe-width-basis",
        severity="medium",
        pattern=re.compile(r"(?<!var )\bsafeWidth\b(?!\s*:)"),
        message="Using safeWidth directly for centered containers can drift when left and right safe areas are asymmetric.",
    ),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Scan SwiftUI source for high-risk UI stability patterns."
    )
    parser.add_argument("root", type=Path, help="Repository or source root to scan")
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format",
    )
    parser.add_argument(
        "--max-findings",
        type=int,
        default=200,
        help="Maximum findings to print in text mode",
    )
    parser.add_argument(
        "--include-tests",
        action="store_true",
        help="Include test targets in the scan",
    )
    return parser.parse_args()


def should_skip(path: Path, include_tests: bool) -> bool:
    parts = set(path.parts)
    if parts & SKIP_DIR_NAMES:
        return True
    if not include_tests and any(part.endswith("Tests") for part in path.parts):
        return True
    return False


def iter_swift_files(root: Path, include_tests: bool):
    for path in root.rglob("*.swift"):
        if should_skip(path, include_tests):
            continue
        yield path


def scan_file(path: Path, root: Path) -> list[Finding]:
    findings: list[Finding] = []
    ignored_rules_by_line: dict[int, set[str]] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        lines = path.read_text(errors="ignore").splitlines()

    for index, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("// ui-audit: ignore-next-line"):
            rule_list = stripped.split("ignore-next-line", 1)[1].strip()
            codes = {
                item.strip()
                for item in rule_list.split(",")
                if item.strip()
            } or {"*"}
            ignored_rules_by_line[index + 1] = codes
            continue
        if not stripped or stripped.startswith("//"):
            continue

        ignored_codes = ignored_rules_by_line.get(index, set())
        matched_codes: set[str] = set()
        for rule in RULES:
            if rule.code in matched_codes:
                continue
            if "*" in ignored_codes or rule.code in ignored_codes:
                continue
            if rule.pattern.search(line):
                findings.append(
                    Finding(
                        severity=rule.severity,
                        code=rule.code,
                        path=str(path.relative_to(root)),
                        line=index,
                        message=rule.message,
                        snippet=stripped[:200],
                    )
                )
                matched_codes.add(rule.code)
    return findings


def sort_findings(findings: list[Finding]) -> list[Finding]:
    severity_order = {"high": 0, "medium": 1, "low": 2}
    return sorted(
        findings,
        key=lambda item: (
            severity_order.get(item.severity, 9),
            item.path,
            item.line,
            item.code,
        ),
    )


def print_text(findings: list[Finding], max_findings: int) -> None:
    if not findings:
        print("No heuristic UI stability findings.")
        return

    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding.severity] = counts.get(finding.severity, 0) + 1

    summary = ", ".join(f"{severity}={count}" for severity, count in sorted(counts.items()))
    print(f"UI stability findings: total={len(findings)} ({summary})")

    for finding in findings[:max_findings]:
        print(f"[{finding.severity}] {finding.code} {finding.path}:{finding.line}")
        print(f"  {finding.message}")
        print(f"  {finding.snippet}")

    if len(findings) > max_findings:
        print(f"... omitted {len(findings) - max_findings} additional findings")


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    if not root.exists():
        print(f"Path does not exist: {root}", file=sys.stderr)
        return 2

    findings: list[Finding] = []
    for path in iter_swift_files(root, args.include_tests):
        findings.extend(scan_file(path, root))

    findings = sort_findings(findings)

    if args.format == "json":
        payload = {
            "root": str(root),
            "count": len(findings),
            "findings": [asdict(finding) for finding in findings],
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print_text(findings, args.max_findings)

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
