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
from typing import Any, Iterable


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
    """Yield source-file entries, skipping anything in a test target."""
    for target in data.get("targets", []) or []:
        if "Test" in (target.get("name") or ""):
            continue
        for src in target.get("files", []) or []:
            yield src


# --------------------------------------------------------------------------- #
# Reports                                                                     #
# --------------------------------------------------------------------------- #

def print_table(data: dict[str, Any]) -> tuple[int, int]:
    """Print per-file table and return (total_covered, total_executable)."""
    total_cov = 0
    total_exe = 0
    print(f"{'File':<50} {'Lines':>8} {'Covered':>8} {'Coverage':>10}")
    print("-" * 80)
    for src in iter_source_files(data):
        name = src.get("name", "?")
        exe = int(src.get("executableLines", 0) or 0)
        cov = int(src.get("coveredLines", 0) or 0)
        pct = float(src.get("lineCoverage", 0) or 0) * 100
        total_exe += exe
        total_cov += cov
        print(f"{name:<50} {exe:>8} {cov:>8} {pct:>9.1f}%")
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
    """Print files whose coverage is below *threshold*. Returns the count."""
    flagged: list[tuple[str, float, int]] = []
    for src in iter_source_files(data):
        exe = int(src.get("executableLines", 0) or 0)
        cov = float(src.get("lineCoverage", 0) or 0)
        if exe >= min_lines and cov < threshold:
            flagged.append((src.get("name", "?"), cov * 100, exe))
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
    rows: list[tuple[str, int, int, float, str]] = []
    total_cov = 0
    total_exe = 0
    for src in iter_source_files(data):
        name = src.get("name", "?")
        exe = int(src.get("executableLines", 0) or 0)
        cov = int(src.get("coveredLines", 0) or 0)
        pct = (cov / exe * 100) if exe > 0 else 0.0
        total_cov += cov
        total_exe += exe
        if exe >= 5:
            icon = "🟢" if pct >= 60 else ("🟡" if pct >= 30 else "🔴")
            rows.append((name, exe, cov, pct, icon))
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
    """
    with open(path, "w", encoding="utf-8") as fh:
        for src in iter_source_files(data):
            name = src.get("name", "?")
            exe = int(src.get("executableLines", 0) or 0)
            cov = int(src.get("coveredLines", 0) or 0)
            fh.write(f"SF:{name}\n")
            # Single synthetic record summarizing the file.
            fh.write(f"DA:1,{1 if cov > 0 else 0}\n")
            fh.write(f"LF:{max(exe, 1)}\n")
            fh.write(f"LH:{cov}\n")
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
