"""Console reporting for harness results."""

from __future__ import annotations

import sys
from dataclasses import dataclass

from cpc_validation.manifest import Manifest
from cpc_validation.verdict import VerdictOutcome


@dataclass
class TestResult:
    manifest: Manifest
    runner_error: str | None
    outcomes: list[VerdictOutcome]

    @property
    def passed(self) -> bool:
        return self.runner_error is None and all(o.passed for o in self.outcomes)


_RESET = "\x1b[0m"
_GREEN = "\x1b[32m"
_RED = "\x1b[31m"
_YELLOW = "\x1b[33m"
_BOLD = "\x1b[1m"


def emit(results: list[TestResult], stream=sys.stdout) -> bool:
    use_color = stream.isatty()
    n_pass = sum(1 for r in results if r.passed)
    n_fail = len(results) - n_pass

    for result in results:
        _print_one(result, stream, use_color)

    if use_color:
        ok = f"{_GREEN}{n_pass} pass{_RESET}"
        bad = f"{_RED}{n_fail} fail{_RESET}" if n_fail else f"{n_fail} fail"
    else:
        ok, bad = f"{n_pass} pass", f"{n_fail} fail"

    print(f"\n{_BOLD if use_color else ''}{ok}, {bad}{_RESET if use_color else ''}", file=stream)
    return n_fail == 0


def _print_one(result: TestResult, stream, use_color: bool) -> None:
    name = result.manifest.name
    if result.runner_error is not None:
        tag = "ERROR"
        color = _RED if use_color else ""
        print(f"{color}{tag:>5}{_RESET if use_color else ''}  {name}", file=stream)
        for line in result.runner_error.splitlines():
            print(f"         {line}", file=stream)
        return

    if result.passed:
        tag = "PASS"
        color = _GREEN if use_color else ""
    else:
        tag = "FAIL"
        color = _RED if use_color else ""
    print(f"{color}{tag:>5}{_RESET if use_color else ''}  {name}", file=stream)
    for outcome in result.outcomes:
        mark_color = (_GREEN if outcome.passed else _RED) if use_color else ""
        mark = "+" if outcome.passed else "-"
        print(
            f"         {mark_color}{mark}{_RESET if use_color else ''} "
            f"{outcome.verdict.kind}: {outcome.reason}",
            file=stream,
        )


def emit_junit(results: list[TestResult], path) -> None:
    """Write a minimal JUnit XML report."""
    import xml.etree.ElementTree as ET

    n_tests = len(results)
    n_failures = sum(1 for r in results if not r.passed and r.runner_error is None)
    n_errors = sum(1 for r in results if r.runner_error is not None)

    root = ET.Element(
        "testsuite",
        attrib={
            "name": "cpc-validation",
            "tests": str(n_tests),
            "failures": str(n_failures),
            "errors": str(n_errors),
        },
    )
    for r in results:
        case = ET.SubElement(
            root,
            "testcase",
            attrib={"name": r.manifest.name, "classname": "cpc-validation"},
        )
        if r.runner_error is not None:
            ET.SubElement(case, "error", attrib={"message": "runner failed"}).text = r.runner_error
            continue
        if not r.passed:
            details = "\n".join(f"{o.verdict.kind}: {o.reason}" for o in r.outcomes if not o.passed)
            ET.SubElement(case, "failure", attrib={"message": "verdict failed"}).text = details

    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
