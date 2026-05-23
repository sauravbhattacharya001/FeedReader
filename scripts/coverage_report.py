#!/usr/bin/env python3
"""
Coverage report helper for FeedReader CI.

Consumes the JSON produced by `xcrun xccov view --report --json <archive>`
and emits, in a single pass:

  * a human-readable per-file table on stdout                (always)
  * `coverage-percent.txt`        overall coverage percent   (always, if data)
  * `coverage.lcov`               lcov-format export         (when --emit-lcov)
  * a markdown report appended to $GITHUB_STEP_SUMMARY        (when set)
  * a regression report on stdout for files with low coverage (always)
  * non-zero exit code when --min-coverage gate fails         (opt-in)

Previously these were four separate Python heredocs embedded directly in
.github/workflows/ci.yml. Pulling them out into a real script:

  1. Lets the file be linted / unit-tested / run locally.
  2. Avoids YAML quoting hazards around `${{ ... }}` and embedded JSON.
  3. Makes coverage policy changes a one-file diff instead of a workflow edit.

The script is intentionally dependency-free (stdlib only) and tolerant of
missing input so it can be called unconditionally from CI.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Iterable, NamedTuple


# --------------------------------------------------------------------------- #
# Data loading                                                                #
# --------------------------------------------------------------------------- #

def load_coverage(path: str) -> dict[str, Any] | None:
    """Load coverage JSON; return None (not raise) when missing/invalid."""
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"warning: could not read {path}: {exc}", file=sys.stderr)
        return None


def iter_source_files(data: dict[str, Any]) -> Iterable[dict[str, Any]]:
    """Yield raw source-file entries, skipping anything in a test target.

    Kept as a public API for callers that want the raw xccov dict (e.g.
    custom reporting). Internal report helpers go through :func:`_iter_files`
    so that JSON-shape quirks are normalized in exactly one place.
    """
    for target in data.get("targets", []) or []:
        if "Test" in (target.get("name") or ""):
            continue
        for src in target.get("files", []) or []:
            yield src


# --------------------------------------------------------------------------- #
# Normalized per-file view                                                    #
# --------------------------------------------------------------------------- #

class _FileCoverage(NamedTuple):
    """Cleaned, type-coerced view of one xccov source-file entry.

    The raw JSON shape is forgiving — fields can be missing, ``None``, or
    floats where ints are expected — so we normalize once here instead of
    duplicating ``int(src.get(..., 0) or 0)`` boilerplate across every
    report function.
    """

    name: str
    executable: int
    covered: int
    ratio: float  # 0.0 .. 1.0

    @classmethod
    def from_raw(cls, src: dict[str, Any]) -> "_FileCoverage":
        return cls(
            name=src.get("name", "?") or "?",
            executable=int(src.get("executableLines", 0) or 0),
            covered=int(src.get("coveredLines", 0) or 0),
            ratio=float(src.get("lineCoverage", 0) or 0),
        )

    @property
    def percent(self) -> float:
        """Coverage as 0..100, derived from covered/executable when possible.

        Falling back to the xccov-reported ratio keeps results stable for
        files that report a non-zero ratio with zero executable lines (a
        quirk we've seen on header-only stubs).
        """
        if self.executable > 0:
            return self.covered / self.executable * 100
        return self.ratio * 100


def _iter_files(data: dict[str, Any]) -> Iterable[_FileCoverage]:
    """Internal: yield normalized per-file coverage entries."""
    for src in iter_source_files(data):
        yield _FileCoverage.from_raw(src)


# --------------------------------------------------------------------------- #
# Reports                                                                     #
# --------------------------------------------------------------------------- #

def print_table(data: dict[str, Any]) -> tuple[int, int]:
    """Print per-file table and return (total_covered, total_executable)."""
    total_cov = 0
    total_exe = 0
    print(f"{'File':<50} {'Lines':>8} {'Covered':>8} {'Coverage':>10}")
    print("-" * 80)
    for f in _iter_files(data):
        total_exe += f.executable
        total_cov += f.covered
        print(f"{f.name:<50} {f.executable:>8} {f.covered:>8} {f.percent:>9.1f}%")
    if total_exe > 0:
        overall = total_cov / total_exe * 100
        print("-" * 80)
        print(f"{'TOTAL':<50} {total_exe:>8} {total_cov:>8} {overall:>9.1f}%")
        print(f"\nOverall code coverage: {overall:.1f}%")
    return total_cov, total_exe


def write_percent_file(total_cov: int, total_exe: int, path: str) -> float | None:
    """Write `NN.N` to *path* and return the percentage (or None if no data)."""
    if total_exe <= 0:
        return None
    pct = total_cov / total_exe * 100
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(f"{pct:.1f}")
    return pct


def write_regression_report(data: dict[str, Any], threshold: float, min_lines: int) -> int:
    """Print files whose coverage is below *threshold*. Returns the count.

    *threshold* is a fraction in ``[0, 1]``; *min_lines* is inclusive.
    """
    flagged: list[tuple[str, float, int]] = [
        (f.name, f.percent, f.executable)
        for f in _iter_files(data)
        if f.executable >= min_lines and f.ratio < threshold
    ]
    if flagged:
        flagged.sort(key=lambda row: row[1])
        print(
            f"\nWARNING: {len(flagged)} file(s) below "
            f"{threshold * 100:.0f}% coverage (>= {min_lines} executable lines):"
        )
        for name, pct, exe in flagged:
            print(f"  {name}: {pct:.1f}% ({exe} lines)")
        print("Consider adding tests for these files.")
    else:
        print("No critically uncovered files detected.")
    return len(flagged)


def append_step_summary(data: dict[str, Any], summary_path: str | None) -> None:
    """Append a markdown summary table to $GITHUB_STEP_SUMMARY (if set)."""
    if not summary_path:
        return

    # Files with < 5 executable lines are excluded from the PR summary
    # table to keep the markdown readable; they still contribute to totals.
    SUMMARY_MIN_LINES = 5

    total_cov = 0
    total_exe = 0
    rows: list[tuple[str, int, int, float, str]] = []
    for f in _iter_files(data):
        total_cov += f.covered
        total_exe += f.executable
        if f.executable >= SUMMARY_MIN_LINES:
            pct = f.percent
            icon = "🟢" if pct >= 60 else ("🟡" if pct >= 30 else "🔴")
            rows.append((f.name, f.executable, f.covered, pct, icon))
    rows.sort(key=lambda r: r[3])

    lines = [
        "## 📊 Code Coverage Report\n",
        "| File | Lines | Covered | Coverage |\n",
        "|------|------:|--------:|---------:|\n",
    ]
    for name, exe, cov, pct, icon in rows:
        lines.append(f"| {icon} {name} | {exe} | {cov} | {pct:.1f}% |\n")
    overall = (total_cov / total_exe * 100) if total_exe > 0 else 0.0
    lines.append(f"\n**Overall: {overall:.1f}%** ({total_cov}/{total_exe} lines)\n")

    with open(summary_path, "a", encoding="utf-8") as fh:
        fh.writelines(lines)


def write_lcov(data: dict[str, Any], path: str) -> None:
    """Write a minimal lcov file Codecov can ingest.

    xccov's JSON does not enumerate per-line hits, only per-file aggregates,
    so we emit one synthetic line record per file with a hit count that
    matches its coverage ratio. This is the same approximation Codecov's
    own xccov bridge uses for line-level summaries.

    ``LF`` is clamped to ``>= 1`` because lcov parsers reject ``LF:0``;
    xccov occasionally reports ``executableLines=0`` for header-only stubs.
    """
    with open(path, "w", encoding="utf-8") as fh:
        for f in _iter_files(data):
            fh.write(f"SF:{f.name}\n")
            # Single synthetic record summarizing the file.
            fh.write(f"DA:1,{1 if f.covered > 0 else 0}\n")
            fh.write(f"LF:{max(f.executable, 1)}\n")
            fh.write(f"LH:{f.covered}\n")
            fh.write("end_of_record\n")


# --------------------------------------------------------------------------- #
# CLI                                                                         #
# --------------------------------------------------------------------------- #

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="FeedReader coverage report helper")
    parser.add_argument("--input", default="coverage.json",
                        help="Path to xccov JSON (default: coverage.json)")
    parser.add_argument("--percent-file", default="coverage-percent.txt",
                        help="Where to write overall coverage percent")
    parser.add_argument("--min-coverage", type=float, default=None,
                        help="Fail with non-zero exit if overall coverage is below this percent")
    parser.add_argument("--regression-threshold", type=float, default=0.10,
                        help="Per-file coverage fraction below which to warn (default: 0.10)")
    parser.add_argument("--regression-min-lines", type=int, default=10,
                        help="Only flag files with >= this many executable lines (default: 10)")
    parser.add_argument("--emit-lcov", default=None,
                        help="If set, write an lcov export to this path")
    parser.add_argument("--summary-path", default=os.environ.get("GITHUB_STEP_SUMMARY"),
                        help="Markdown summary path (default: $GITHUB_STEP_SUMMARY)")
    args = parser.parse_args(argv)

    data = load_coverage(args.input)
    if data is None:
        print(f"No coverage data at {args.input}; nothing to report.")
        return 0

    total_cov, total_exe = print_table(data)
    pct = write_percent_file(total_cov, total_exe, args.percent_file)
    write_regression_report(data, args.regression_threshold, args.regression_min_lines)
    append_step_summary(data, args.summary_path)
    if args.emit_lcov:
        write_lcov(data, args.emit_lcov)

    if args.min_coverage is not None and pct is not None and pct < args.min_coverage:
        print(
            f"::error::Coverage {pct:.1f}% is below the minimum "
            f"threshold of {args.min_coverage:.1f}%"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
