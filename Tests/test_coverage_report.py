"""Unit tests for scripts/coverage_report.py.

This helper is invoked from CI to summarize xccov JSON output, so the
behavior we cover here is what CI relies on:

  * test target files are excluded
  * the overall percent file is written with the correct rounding
  * the --min-coverage gate fails with a non-zero exit only when the
    overall coverage is actually below the threshold
  * the lcov export is a structurally valid lcov stream
  * missing/invalid input is tolerated (CI calls the script
    unconditionally and should not blow up when there's no coverage
    archive, e.g. on a docs-only PR)
  * the regression report flags low-coverage files with enough lines

The tests are stdlib-only and do not require xcrun, matching the
script's own design constraints.
"""
from __future__ import annotations

import importlib.util
import io
import json
import os
import sys
from contextlib import redirect_stdout
from pathlib import Path

import pytest


# --------------------------------------------------------------------------- #
# Module loading                                                              #
# --------------------------------------------------------------------------- #
# coverage_report.py lives under scripts/ and isn't installed as a package,
# so we load it by absolute path. This keeps the test suite portable to
# both `pytest` invocations and the CI matrix where cwd may vary.

_REPO_ROOT = Path(__file__).resolve().parent.parent
_SCRIPT_PATH = _REPO_ROOT / "scripts" / "coverage_report.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("coverage_report", _SCRIPT_PATH)
    assert spec and spec.loader, f"could not load {_SCRIPT_PATH}"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # type: ignore[union-attr]
    return module


coverage_report = _load_module()


# --------------------------------------------------------------------------- #
# Fixtures                                                                    #
# --------------------------------------------------------------------------- #

def _sample_data() -> dict:
    """xccov-shaped JSON with both production and test targets."""
    return {
        "targets": [
            {
                "name": "FeedReaderCore",
                "files": [
                    {
                        "name": "FeedItem.swift",
                        "executableLines": 100,
                        "coveredLines": 80,
                        "lineCoverage": 0.80,
                    },
                    {
                        "name": "RSSParser.swift",
                        "executableLines": 200,
                        "coveredLines": 50,
                        "lineCoverage": 0.25,
                    },
                    {
                        "name": "TinyHelper.swift",
                        "executableLines": 3,
                        "coveredLines": 0,
                        "lineCoverage": 0.0,
                    },
                ],
            },
            {
                # MUST be skipped by iter_source_files
                "name": "FeedReaderCoreTests",
                "files": [
                    {
                        "name": "FakeShouldBeIgnored.swift",
                        "executableLines": 999,
                        "coveredLines": 0,
                        "lineCoverage": 0.0,
                    }
                ],
            },
        ]
    }


@pytest.fixture
def sample_json(tmp_path: Path) -> Path:
    """Write _sample_data() to a real JSON file and return its path."""
    path = tmp_path / "coverage.json"
    path.write_text(json.dumps(_sample_data()), encoding="utf-8")
    return path


# --------------------------------------------------------------------------- #
# load_coverage                                                               #
# --------------------------------------------------------------------------- #

class TestLoadCoverage:
    def test_returns_dict_for_valid_file(self, sample_json: Path) -> None:
        data = coverage_report.load_coverage(str(sample_json))
        assert isinstance(data, dict)
        assert "targets" in data

    def test_missing_file_returns_none(self, tmp_path: Path) -> None:
        # CI shouldn't crash when the xccov archive isn't produced
        # (e.g. docs-only PRs that don't run xcodebuild).
        assert coverage_report.load_coverage(str(tmp_path / "nope.json")) is None

    def test_invalid_json_returns_none(self, tmp_path: Path, capsys) -> None:
        bad = tmp_path / "bad.json"
        bad.write_text("{not valid json", encoding="utf-8")
        assert coverage_report.load_coverage(str(bad)) is None
        # User-visible warning is on stderr; CI logs surface this for
        # debugging without failing the build.
        assert "warning" in capsys.readouterr().err.lower()


# --------------------------------------------------------------------------- #
# iter_source_files                                                           #
# --------------------------------------------------------------------------- #

class TestIterSourceFiles:
    def test_skips_test_targets(self) -> None:
        files = list(coverage_report.iter_source_files(_sample_data()))
        names = {f["name"] for f in files}
        assert "FakeShouldBeIgnored.swift" not in names
        assert names == {"FeedItem.swift", "RSSParser.swift", "TinyHelper.swift"}

    def test_tolerates_missing_targets_key(self) -> None:
        assert list(coverage_report.iter_source_files({})) == []

    def test_tolerates_null_files_list(self) -> None:
        data = {"targets": [{"name": "Foo", "files": None}]}
        assert list(coverage_report.iter_source_files(data)) == []

    @pytest.mark.parametrize("target_name", [
        "FeedReaderCoreTests",
        "MyAppTests",
        "TestSupport",  # any name containing "Test" is excluded
    ])
    def test_target_name_substring_filter(self, target_name: str) -> None:
        data = {"targets": [
            {"name": target_name, "files": [{"name": "x.swift",
                                             "executableLines": 1,
                                             "coveredLines": 1,
                                             "lineCoverage": 1.0}]},
        ]}
        assert list(coverage_report.iter_source_files(data)) == []


# --------------------------------------------------------------------------- #
# print_table                                                                 #
# --------------------------------------------------------------------------- #

class TestPrintTable:
    def test_totals_exclude_test_target(self, capsys) -> None:
        cov, exe = coverage_report.print_table(_sample_data())
        # 80 + 50 + 0 covered, 100 + 200 + 3 executable
        assert cov == 130
        assert exe == 303
        out = capsys.readouterr().out
        assert "FeedItem.swift" in out
        assert "FakeShouldBeIgnored.swift" not in out
        assert "TOTAL" in out

    def test_empty_data_returns_zeros_no_total_line(self, capsys) -> None:
        cov, exe = coverage_report.print_table({"targets": []})
        assert (cov, exe) == (0, 0)
        # No totals row when there's nothing to total — avoids a confusing
        # "TOTAL 0 0 NaN%" in the CI log.
        assert "TOTAL" not in capsys.readouterr().out


# --------------------------------------------------------------------------- #
# write_percent_file                                                          #
# --------------------------------------------------------------------------- #

class TestWritePercentFile:
    def test_writes_one_decimal(self, tmp_path: Path) -> None:
        out = tmp_path / "pct.txt"
        pct = coverage_report.write_percent_file(130, 303, str(out))
        assert pct == pytest.approx(130 / 303 * 100)
        assert out.read_text(encoding="utf-8") == f"{130 / 303 * 100:.1f}"

    def test_zero_executable_returns_none_and_does_not_write(self, tmp_path: Path) -> None:
        out = tmp_path / "pct.txt"
        assert coverage_report.write_percent_file(0, 0, str(out)) is None
        assert not out.exists()


# --------------------------------------------------------------------------- #
# write_regression_report                                                     #
# --------------------------------------------------------------------------- #

class TestRegressionReport:
    def test_flags_low_coverage_files_above_min_lines(self, capsys) -> None:
        # RSSParser is at 25% with 200 lines -> flagged at 30% threshold
        # FeedItem is at 80% -> not flagged
        # TinyHelper has only 3 lines -> excluded by min_lines=10
        n = coverage_report.write_regression_report(_sample_data(),
                                                    threshold=0.30,
                                                    min_lines=10)
        assert n == 1
        out = capsys.readouterr().out
        assert "RSSParser.swift" in out
        assert "TinyHelper.swift" not in out
        assert "FeedItem.swift" not in out

    def test_no_flags_prints_friendly_message(self, capsys) -> None:
        n = coverage_report.write_regression_report(_sample_data(),
                                                    threshold=0.0,
                                                    min_lines=10)
        assert n == 0
        assert "No critically uncovered files" in capsys.readouterr().out

    def test_min_lines_gate_is_inclusive(self) -> None:
        # File with exactly min_lines should be eligible.
        data = {"targets": [{"name": "X", "files": [
            {"name": "edge.swift", "executableLines": 10,
             "coveredLines": 0, "lineCoverage": 0.0},
        ]}]}
        assert coverage_report.write_regression_report(
            data, threshold=0.5, min_lines=10) == 1


# --------------------------------------------------------------------------- #
# append_step_summary                                                         #
# --------------------------------------------------------------------------- #

class TestStepSummary:
    def test_noop_when_path_is_none(self) -> None:
        # Must not raise — most local runs have no GITHUB_STEP_SUMMARY.
        coverage_report.append_step_summary(_sample_data(), None)

    def test_writes_markdown_table_with_overall(self, tmp_path: Path) -> None:
        summary = tmp_path / "summary.md"
        coverage_report.append_step_summary(_sample_data(), str(summary))
        text = summary.read_text(encoding="utf-8")
        assert "## 📊 Code Coverage Report" in text
        assert "| File | Lines | Covered | Coverage |" in text
        assert "RSSParser.swift" in text
        # Overall = 130/303
        assert f"{130/303*100:.1f}%" in text
        # Files with < 5 executable lines are excluded from the markdown
        # table (cosmetic — keeps the PR summary readable).
        assert "TinyHelper.swift" not in text

    def test_appends_rather_than_overwrites(self, tmp_path: Path) -> None:
        summary = tmp_path / "summary.md"
        summary.write_text("previous content\n", encoding="utf-8")
        coverage_report.append_step_summary(_sample_data(), str(summary))
        text = summary.read_text(encoding="utf-8")
        assert text.startswith("previous content\n")
        assert "Code Coverage Report" in text


# --------------------------------------------------------------------------- #
# write_lcov                                                                  #
# --------------------------------------------------------------------------- #

class TestWriteLcov:
    def test_emits_one_record_per_source_file(self, tmp_path: Path) -> None:
        out = tmp_path / "out.lcov"
        coverage_report.write_lcov(_sample_data(), str(out))
        text = out.read_text(encoding="utf-8")
        # Three production files, zero test-target leakage
        assert text.count("end_of_record") == 3
        assert "SF:FeedItem.swift" in text
        assert "SF:RSSParser.swift" in text
        assert "FakeShouldBeIgnored.swift" not in text

    def test_lf_uses_max_one_even_for_zero_executable_files(self, tmp_path: Path) -> None:
        # Edge case: xccov occasionally reports executableLines=0 for stubs.
        # lcov parsers reject LF:0, so the script clamps to >= 1.
        data = {"targets": [{"name": "X", "files": [
            {"name": "empty.swift", "executableLines": 0,
             "coveredLines": 0, "lineCoverage": 0.0},
        ]}]}
        out = tmp_path / "out.lcov"
        coverage_report.write_lcov(data, str(out))
        text = out.read_text(encoding="utf-8")
        assert "LF:1" in text
        assert "LF:0" not in text


# --------------------------------------------------------------------------- #
# main / CLI                                                                  #
# --------------------------------------------------------------------------- #

class TestMain:
    def test_missing_input_exits_zero(self, tmp_path: Path, capsys) -> None:
        rc = coverage_report.main([
            "--input", str(tmp_path / "nope.json"),
            "--percent-file", str(tmp_path / "pct.txt"),
        ])
        assert rc == 0
        assert "nothing to report" in capsys.readouterr().out

    def test_full_run_writes_all_outputs(self, tmp_path: Path, sample_json: Path,
                                         monkeypatch: pytest.MonkeyPatch) -> None:
        pct_file = tmp_path / "pct.txt"
        lcov_file = tmp_path / "out.lcov"
        summary_file = tmp_path / "summary.md"
        # Exercise the GITHUB_STEP_SUMMARY env-var default path.
        monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary_file))

        rc = coverage_report.main([
            "--input", str(sample_json),
            "--percent-file", str(pct_file),
            "--emit-lcov", str(lcov_file),
        ])
        assert rc == 0
        assert pct_file.exists() and pct_file.read_text().strip()
        assert lcov_file.exists() and "end_of_record" in lcov_file.read_text()
        assert summary_file.exists() and "Code Coverage Report" in summary_file.read_text()

    def test_min_coverage_gate_fails_when_below(self, tmp_path: Path,
                                                sample_json: Path, capsys) -> None:
        rc = coverage_report.main([
            "--input", str(sample_json),
            "--percent-file", str(tmp_path / "pct.txt"),
            "--min-coverage", "90",
        ])
        assert rc == 1
        assert "::error::" in capsys.readouterr().out

    def test_min_coverage_gate_passes_when_above(self, tmp_path: Path,
                                                 sample_json: Path) -> None:
        rc = coverage_report.main([
            "--input", str(sample_json),
            "--percent-file", str(tmp_path / "pct.txt"),
            "--min-coverage", "10",  # actual is ~42.9%
        ])
        assert rc == 0

    def test_min_coverage_not_set_returns_zero_even_for_low_coverage(
            self, tmp_path: Path, sample_json: Path) -> None:
        # Without --min-coverage the script is purely informational.
        rc = coverage_report.main([
            "--input", str(sample_json),
            "--percent-file", str(tmp_path / "pct.txt"),
        ])
        assert rc == 0
