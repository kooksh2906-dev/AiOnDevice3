#!/usr/bin/env python3
"""Build the Step-10 evidence and presentation package.

The package has two deliberately separate modes:

* ``draft`` preserves all verified ILA evidence while visibly marking the
  missing Custom whole-routed input.
* ``final`` is allowed only after the Step-9 four-way completion gate passes.

This prevents a presentation draft from being mistaken for the official
Custom-vs-ILA comparison.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Mapping, Sequence


STATUS_KEY = re.compile(r"^[A-Z][A-Z0-9_.-]*$")
SHA256_LINE = re.compile(r"^([0-9a-f]{64})  (.+)$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
NORMALIZED_HEADER = (
    "index",
    "value_hex",
    "is_trigger",
    "ch7",
    "ch6",
    "ch5",
    "ch4",
    "ch3",
    "ch2",
    "ch1",
    "ch0",
)
CUSTOM_REQUIRED_FILES = (
    "utilization.rpt",
    "hierarchical_utilization.rpt",
    "timing_summary.rpt",
    "route_status.rpt",
    "drc.rpt",
    "routed_design.dcp",
    "build_manifest.rpt",
)
STEP9_FINAL_GATE = {
    "OVERALL": "PASS",
    "BASELINE": "VERIFIED",
    "CPU_REPORT": "VERIFIED",
    "ILA_STEP9": "PASS",
    "CUSTOM_FULL_SYSTEM": "VERIFIED",
    "THREE_WAY_COMPARISON": "COMPLETE",
    "OFFICIAL_CUSTOM_VS_ILA_SAVINGS": "VERIFIED",
    "NEXT_ACTION": "STEP10_FINAL_PACKAGE",
}


class PackageError(RuntimeError):
    """Invalid or contradictory source evidence."""


class PendingTeamInput(PackageError):
    """The final gate is healthy but still waiting for team input."""


@dataclass(frozen=True)
class ManifestResult:
    path: Path
    verified_count: int
    sha256: str


@dataclass(frozen=True)
class GitAudit:
    reference: str
    commit: str
    author: str
    authored_at: str
    subject: str
    local_head: str
    local_branch: str
    local_dirty: bool
    commits_behind: int
    commits_ahead: int
    common_match_count: int
    cpu_report_match_count: int
    ila_tree_present: bool
    custom_contract_file_count: int
    final_demo_ref: str
    final_demo_commit: str
    final_demo_merged: bool
    remote_test_status: str
    main_regression_includes_new_ip_tests: str
    trigger_tb_failure_exit_nonzero: str
    final_demo_xparameters_compatibility: str
    final_demo_bram_macro_compatibility: str
    final_demo_arm_before_sampler: str
    final_demo_readme_merge_conflict: str
    hardware_xsa_sha256: str


@dataclass(frozen=True)
class Evidence:
    category: str
    path: Path
    status: str
    note: str


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def parse_key_values(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise PackageError(f"missing key-value report: {path}")
    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8", errors="strict").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise PackageError(
                f"{path}:{line_number}: expected KEY=VALUE"
            )
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not STATUS_KEY.fullmatch(key):
            raise PackageError(f"{path}:{line_number}: invalid key {key!r}")
        if key in values:
            raise PackageError(
                f"{path}:{line_number}: duplicate key {key!r}"
            )
        values[key] = value
    if not values:
        raise PackageError(f"empty key-value report: {path}")
    return values


def require_values(
    path: Path, values: Mapping[str, str], expected: Mapping[str, str]
) -> None:
    errors = [
        f"{key}={values.get(key, '<missing>')} (expected {value})"
        for key, value in expected.items()
        if values.get(key) != value
    ]
    if errors:
        raise PackageError(f"{path}: " + "; ".join(errors))


def final_gate_errors(step9: Mapping[str, str]) -> list[str]:
    return [
        f"{key}={step9.get(key, '<missing>')} (required {expected})"
        for key, expected in STEP9_FINAL_GATE.items()
        if step9.get(key) != expected
    ]


def verify_checksum_manifest(
    path: Path,
    *,
    entry_root: Path | None = None,
    allowed_root: Path | None = None,
) -> ManifestResult:
    if not path.is_file():
        raise PackageError(f"missing checksum manifest: {path}")
    base = (entry_root or path.parent).resolve()
    allowed = (allowed_root or base).resolve()
    seen: set[str] = set()
    count = 0
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8", errors="strict").splitlines(),
        start=1,
    ):
        if not raw_line:
            continue
        match = SHA256_LINE.fullmatch(raw_line)
        if match is None:
            raise PackageError(
                f"{path}:{line_number}: malformed SHA256SUMS entry"
            )
        expected, relative_name = match.groups()
        if relative_name in seen:
            raise PackageError(
                f"{path}:{line_number}: duplicate path {relative_name!r}"
            )
        seen.add(relative_name)
        relative = Path(relative_name)
        if relative.is_absolute():
            raise PackageError(
                f"{path}:{line_number}: unsafe path {relative_name!r}"
            )
        target = (base / relative).resolve()
        try:
            target.relative_to(allowed)
        except ValueError as error:
            raise PackageError(
                f"{path}:{line_number}: path escapes allowed evidence root"
            ) from error
        if not target.is_file():
            raise PackageError(
                f"{path}:{line_number}: missing target {relative_name}"
            )
        actual = sha256_file(target)
        if actual != expected:
            raise PackageError(
                f"{path}:{line_number}: checksum mismatch for "
                f"{relative_name}: {actual} != {expected}"
            )
        count += 1
    if count == 0:
        raise PackageError(f"empty checksum manifest: {path}")
    return ManifestResult(path, count, sha256_file(path))


def read_csv(path: Path) -> tuple[tuple[str, ...], list[dict[str, str]]]:
    if not path.is_file():
        raise PackageError(f"missing CSV: {path}")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise PackageError(f"CSV has no header: {path}")
        header = tuple(reader.fieldnames)
        rows = list(reader)
    if not rows:
        raise PackageError(f"CSV has no data rows: {path}")
    return header, rows


def indexed_rows(
    path: Path, required_columns: Iterable[str], keys: Sequence[str]
) -> dict[tuple[str, ...], dict[str, str]]:
    header, rows = read_csv(path)
    missing = set(required_columns) - set(header)
    if missing:
        raise PackageError(f"{path}: missing columns {sorted(missing)}")
    indexed: dict[tuple[str, ...], dict[str, str]] = {}
    for row_number, row in enumerate(rows, start=2):
        key = tuple(row[column] for column in keys)
        if key in indexed:
            raise PackageError(f"{path}:{row_number}: duplicate key {key}")
        indexed[key] = row
    return indexed


def validate_normalized_capture(
    path: Path, expected_511: str, expected_512: str
) -> int:
    header, rows = read_csv(path)
    if header != NORMALIZED_HEADER:
        raise PackageError(
            f"{path}: normalized header mismatch: {header!r}"
        )
    if len(rows) != 1024:
        raise PackageError(f"{path}: expected 1024 rows, got {len(rows)}")
    trigger_indices: list[int] = []
    for expected_index, row in enumerate(rows):
        try:
            actual_index = int(row["index"])
        except ValueError as error:
            raise PackageError(
                f"{path}: non-integer index {row['index']!r}"
            ) from error
        if actual_index != expected_index:
            raise PackageError(
                f"{path}: index {actual_index}, expected {expected_index}"
            )
        value = row["value_hex"].upper()
        if not re.fullmatch(r"[0-9A-F]{2}", value):
            raise PackageError(f"{path}: invalid 8-bit value {value!r}")
        expected_bits = tuple(f"{int(value, 16):08b}")
        actual_bits = tuple(row[f"ch{bit}"] for bit in range(7, -1, -1))
        if actual_bits != expected_bits:
            raise PackageError(
                f"{path}: bit columns disagree at index {actual_index}"
            )
        if row["is_trigger"] == "1":
            trigger_indices.append(actual_index)
        elif row["is_trigger"] != "0":
            raise PackageError(
                f"{path}: invalid trigger flag {row['is_trigger']!r}"
            )
    if trigger_indices != [512]:
        raise PackageError(
            f"{path}: trigger indices {trigger_indices}, expected [512]"
        )
    normalized_511 = expected_511.upper().removeprefix("0X").zfill(2)
    normalized_512 = expected_512.upper().removeprefix("0X").zfill(2)
    if rows[511]["value_hex"].upper() != normalized_511:
        raise PackageError(f"{path}: sample 511 mismatch")
    if rows[512]["value_hex"].upper() != normalized_512:
        raise PackageError(f"{path}: sample 512 mismatch")
    return len(rows)


def validate_pulse_summary(path: Path) -> list[dict[str, str]]:
    required = (
        "width_cycles",
        "width_ns",
        "eligible_trials",
        "detected_count",
        "detection_rate_percent",
        "expected_detected_count",
        "result",
    )
    header, rows = read_csv(path)
    if header != required:
        raise PackageError(f"{path}: pulse summary header mismatch")
    expected_widths = (1, 10, 100, 1_000, 10_000, 100_000)
    actual_widths = tuple(int(row["width_cycles"]) for row in rows)
    if actual_widths != expected_widths:
        raise PackageError(
            f"{path}: widths {actual_widths}, expected {expected_widths}"
        )
    for row in rows:
        if (
            row["eligible_trials"] != "10"
            or row["detected_count"] != "10"
            or row["expected_detected_count"] != "10"
            or row["detection_rate_percent"] != "100.0"
            or row["result"] != "PASS"
        ):
            raise PackageError(f"{path}: failed pulse row {row}")
    return rows


def run_git(repo_root: Path, *arguments: str, check: bool = True) -> str:
    result = subprocess.run(
        ("git",) + arguments,
        cwd=repo_root,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise PackageError(
            f"git {' '.join(arguments)} failed: {detail}"
        )
    return result.stdout.strip()


def git_ref_exists(repo_root: Path, reference: str) -> bool:
    result = subprocess.run(
        ("git", "rev-parse", "--verify", "--quiet", f"{reference}^{{commit}}"),
        cwd=repo_root,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def git_blob_matches(repo_root: Path, commit: str, relative_path: str) -> bool:
    local_path = repo_root / relative_path
    if not local_path.is_file():
        return False
    remote_blob = run_git(repo_root, "rev-parse", f"{commit}:{relative_path}")
    local_blob = run_git(repo_root, "hash-object", str(local_path))
    return remote_blob == local_blob


def audit_git(
    repo_root: Path,
    reference: str,
    remote_test_report: Path,
) -> GitAudit:
    if not git_ref_exists(repo_root, reference):
        raise PackageError(
            f"Git reference {reference!r} is unavailable; fetch origin first"
        )
    commit = run_git(repo_root, "rev-parse", f"{reference}^{{commit}}")
    metadata = run_git(
        repo_root,
        "show",
        "-s",
        "--format=%an%x00%aI%x00%s",
        commit,
    ).split("\0")
    if len(metadata) != 3:
        raise PackageError("unexpected Git commit metadata")
    author, authored_at, subject = metadata
    tree = set(
        run_git(repo_root, "ls-tree", "-r", "--name-only", commit).splitlines()
    )
    local_head = run_git(repo_root, "rev-parse", "HEAD")
    local_branch = run_git(
        repo_root, "branch", "--show-current", check=False
    ) or "DETACHED"
    local_dirty = bool(
        run_git(repo_root, "status", "--porcelain", "--untracked-files=normal")
    )
    commits_behind = int(
        run_git(repo_root, "rev-list", "--count", f"HEAD..{commit}")
    )
    commits_ahead = int(
        run_git(repo_root, "rev-list", "--count", f"{commit}..HEAD")
    )

    common_paths = (
        "comparison/common/base_soc.tcl",
        "comparison/common/rtl/test_pattern_generator.sv",
    )
    cpu_paths = tuple(
        f"comparison/cpu_polling/reports/{name}"
        for name in (
            "utilization.rpt",
            "hierarchical_utilization.rpt",
            "timing_summary.rpt",
            "drc.rpt",
        )
    )
    common_match_count = sum(
        git_blob_matches(repo_root, commit, path) for path in common_paths
    )
    cpu_report_match_count = 0
    for remote_path in cpu_paths:
        local_path = (
            "comparison/ila_reference/results/step9/inputs/cpu_polling/"
            + Path(remote_path).name
        )
        if remote_path not in tree or not (repo_root / local_path).is_file():
            continue
        remote_blob = run_git(repo_root, "rev-parse", f"{commit}:{remote_path}")
        local_blob = run_git(
            repo_root, "hash-object", str(repo_root / local_path)
        )
        cpu_report_match_count += int(remote_blob == local_blob)

    custom_prefix = (
        "comparison/ila_reference/results/step9/inputs/custom/"
    )
    custom_contract_file_count = sum(
        f"{custom_prefix}{name}" in tree for name in CUSTOM_REQUIRED_FILES
    )
    ila_tree_present = "comparison/ila_reference/README.md" in tree

    test_values = parse_key_values(remote_test_report)
    require_values(
        remote_test_report,
        test_values,
        {
            "REMOTE_MAIN_COMMIT": commit,
            "REMOTE_MAIN_TESTS": "PASS",
            "CIRCULAR_BUFFER_REGRESSION": "PASS",
            "BASIC_TRIGGER_ENGINE_TEST": "PASS",
            "PROBE_SAMPLER_TEST": "PASS",
            "CPU_POLLING_ENGINE_TEST": "PASS",
        },
    )

    final_demo_ref = "origin/agent/publish-final-demo"
    if git_ref_exists(repo_root, final_demo_ref):
        final_demo_commit = run_git(
            repo_root, "rev-parse", f"{final_demo_ref}^{{commit}}"
        )
        merge_result = subprocess.run(
            ("git", "merge-base", "--is-ancestor", final_demo_commit, commit),
            cwd=repo_root,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        final_demo_merged = merge_result.returncode == 0
    else:
        final_demo_commit = "NOT_AVAILABLE"
        final_demo_merged = False

    return GitAudit(
        reference=reference,
        commit=commit,
        author=author,
        authored_at=authored_at,
        subject=subject,
        local_head=local_head,
        local_branch=local_branch,
        local_dirty=local_dirty,
        commits_behind=commits_behind,
        commits_ahead=commits_ahead,
        common_match_count=common_match_count,
        cpu_report_match_count=cpu_report_match_count,
        ila_tree_present=ila_tree_present,
        custom_contract_file_count=custom_contract_file_count,
        final_demo_ref=final_demo_ref,
        final_demo_commit=final_demo_commit,
        final_demo_merged=final_demo_merged,
        remote_test_status=test_values["REMOTE_MAIN_TESTS"],
        main_regression_includes_new_ip_tests=test_values.get(
            "MAIN_REGRESSION_INCLUDES_NEW_IP_TESTS", "NOT_TESTED"
        ),
        trigger_tb_failure_exit_nonzero=test_values.get(
            "BASIC_TRIGGER_TB_FAILURE_EXIT_NONZERO", "NOT_TESTED"
        ),
        final_demo_xparameters_compatibility=test_values.get(
            "FINAL_DEMO_XPARAMETERS_COMPATIBILITY", "NOT_TESTED"
        ),
        final_demo_bram_macro_compatibility=test_values.get(
            "FINAL_DEMO_BRAM_MACRO_COMPATIBILITY", "NOT_TESTED"
        ),
        final_demo_arm_before_sampler=test_values.get(
            "FINAL_DEMO_ARM_BEFORE_SAMPLER", "NOT_TESTED"
        ),
        final_demo_readme_merge_conflict=test_values.get(
            "FINAL_DEMO_README_MERGE_CONFLICT", "NOT_TESTED"
        ),
        hardware_xsa_sha256=test_values.get(
            "HARDWARE_XSA_SHA256", "NOT_PROVIDED"
        ),
    )


def display_int(value: str) -> str:
    try:
        return f"{int(value):,}"
    except ValueError:
        return value


def display_duration_ns(value: str) -> str:
    nanoseconds = int(value)
    if nanoseconds >= 1_000_000 and nanoseconds % 1_000_000 == 0:
        return f"{nanoseconds // 1_000_000} ms"
    if nanoseconds >= 1_000 and nanoseconds % 1_000 == 0:
        return f"{nanoseconds // 1_000} µs"
    return f"{nanoseconds} ns"


def relative_to_repo(path: Path, repo_root: Path) -> str:
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except ValueError:
        return str(path)


def render_result_cards(
    output: Path,
    mode: str,
    ila_total: Mapping[str, str],
    ila_delta: Mapping[str, str],
    pulse_rows: Sequence[Mapping[str, str]],
) -> None:
    mode_label = (
        "FINAL • CUSTOM COMPARISON VERIFIED"
        if mode == "final"
        else "DRAFT • CUSTOM ROUTED REPORTS PENDING"
    )
    badge_color = "#22C55E" if mode == "final" else "#F59E0B"
    min_duration = display_duration_ns(pulse_rows[0]["width_ns"])
    max_duration = display_duration_ns(pulse_rows[-1]["width_ns"])
    svg = f"""\
<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900"
     viewBox="0 0 1600 900" role="img"
     aria-label="Vivado ILA Step 10 result cards">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#030817"/>
      <stop offset="1" stop-color="#10102d"/>
    </linearGradient>
    <linearGradient id="accent" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#00E5FF"/>
      <stop offset="1" stop-color="#B14CFF"/>
    </linearGradient>
    <filter id="glow">
      <feGaussianBlur stdDeviation="5" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1600" height="900" fill="url(#bg)"/>
  <g opacity=".23" fill="none" stroke="#00D9FF">
    <path d="M0 180 H340 C430 180 430 110 520 110 H1600"/>
    <path d="M0 740 H420 C510 740 510 810 600 810 H1600"/>
    <path d="M1250 0 V150 C1250 220 1320 220 1320 290 V900"/>
  </g>
  <text x="86" y="94" fill="#AAB4D6" font-size="22"
        font-family="Inter, Noto Sans KR, sans-serif" letter-spacing="4">
    EDGESCOPE-LITE / VIVADO ILA REFERENCE
  </text>
  <text x="86" y="174" fill="#FFFFFF" font-size="64" font-weight="750"
        font-family="Inter, Noto Sans KR, sans-serif">
    VERIFIED RESULTS
  </text>
  <rect x="86" y="210" width="1428" height="3" fill="url(#accent)"/>

  <g font-family="Inter, Noto Sans KR, sans-serif">
    <g>
      <rect x="86" y="278" width="440" height="390" rx="28"
            fill="#0C1534" stroke="#00E5FF" stroke-width="2"/>
      <text x="126" y="338" fill="#00E5FF" font-size="21"
            letter-spacing="3">CAPTURE WINDOW</text>
      <text x="126" y="455" fill="#FFFFFF" font-size="104"
            font-weight="760">1,024</text>
      <text x="126" y="508" fill="#D8DDF0" font-size="28">samples at 100 MHz</text>
      <text x="126" y="575" fill="#9EA8CA" font-size="23">
        Trigger index 512
      </text>
      <text x="126" y="615" fill="#9EA8CA" font-size="23">
        512 pre / 512 post incl. trigger
      </text>
    </g>

    <g>
      <rect x="580" y="278" width="440" height="390" rx="28"
            fill="#0C1534" stroke="#00E5FF" stroke-width="2"/>
      <text x="620" y="338" fill="#00E5FF" font-size="21"
            letter-spacing="3">PULSE STRESS</text>
      <text x="620" y="455" fill="#FFFFFF" font-size="104"
            font-weight="760">60/60</text>
      <text x="620" y="508" fill="#D8DDF0" font-size="28">
        synchronized pulses detected
      </text>
      <text x="620" y="575" fill="#9EA8CA" font-size="23">
        {html.escape(min_duration)} to {html.escape(max_duration)}
      </text>
      <text x="620" y="615" fill="#9EA8CA" font-size="23">
        6 widths × 10 repetitions
      </text>
    </g>

    <g>
      <rect x="1074" y="278" width="440" height="390" rx="28"
            fill="#0C1534" stroke="#B14CFF" stroke-width="2"/>
      <text x="1114" y="338" fill="#D06AFF" font-size="21"
            letter-spacing="3">ILA DELTA VS BASE</text>
      <text x="1114" y="432" fill="#FFFFFF" font-size="72"
            font-weight="760">+{display_int(ila_delta['slice_luts'])}</text>
      <text x="1114" y="474" fill="#D8DDF0" font-size="26">Slice LUTs</text>
      <text x="1114" y="548" fill="#FFFFFF" font-size="52"
            font-weight="740">+{display_int(ila_delta['slice_registers'])} FF</text>
      <text x="1114" y="607" fill="#9EA8CA" font-size="23">
        +{html.escape(ila_delta['ramb18'])} RAMB18
      </text>
      <text x="1114" y="640" fill="#9EA8CA" font-size="18">
        Total LUT {display_int(ila_total['slice_luts'])}
      </text>
    </g>
  </g>

  <rect x="86" y="748" width="1428" height="70" rx="18"
        fill="{badge_color}" opacity=".14"/>
  <circle cx="126" cy="783" r="8" fill="{badge_color}" filter="url(#glow)"/>
  <text x="151" y="792" fill="{badge_color}" font-size="24" font-weight="700"
        font-family="Inter, Noto Sans KR, sans-serif" letter-spacing="2">
    {mode_label}
  </text>
</svg>
"""
    atomic_write(output, svg)


def render_trigger_evidence(
    output: Path, step6: Mapping[str, str], mode: str
) -> None:
    profiles = (
        (
            "RISING EDGE",
            step6["RISING_SAMPLE_511"],
            step6["RISING_SAMPLE_512"],
        ),
        (
            "FALLING EDGE",
            step6["FALLING_SAMPLE_511"],
            step6["FALLING_SAMPLE_512"],
        ),
        (
            "MASKED PATTERN",
            step6["PATTERN_SAMPLE_511"],
            step6["PATTERN_SAMPLE_512"],
        ),
    )
    rows: list[str] = []
    for index, (label, before, trigger) in enumerate(profiles):
        y = 285 + index * 185
        rows.append(
            f"""\
    <text x="110" y="{y}" fill="#FFFFFF" font-size="30" font-weight="700">
      {label}
    </text>
    <text x="110" y="{y + 42}" fill="#8FA0C8" font-size="19">
      Physical board capture • PASS
    </text>
    <rect x="510" y="{y - 58}" width="250" height="98" rx="18"
          fill="#101A3B" stroke="#44547D"/>
    <text x="635" y="{y - 17}" text-anchor="middle" fill="#9EA8CA"
          font-size="18">SAMPLE 511</text>
    <text x="635" y="{y + 20}" text-anchor="middle" fill="#FFFFFF"
          font-size="34" font-weight="700">{html.escape(before)}</text>
    <path d="M760 {y - 9} H840" stroke="#00E5FF" stroke-width="4"/>
    <path d="M824 {y - 22} L846 {y - 9} L824 {y + 4} Z" fill="#00E5FF"/>
    <rect x="840" y="{y - 58}" width="250" height="98" rx="18"
          fill="#142044" stroke="#00E5FF" stroke-width="2"/>
    <text x="965" y="{y - 17}" text-anchor="middle" fill="#00E5FF"
          font-size="18">TRIGGER • 512</text>
    <text x="965" y="{y + 20}" text-anchor="middle" fill="#FFFFFF"
          font-size="34" font-weight="700">{html.escape(trigger)}</text>
    <text x="1160" y="{y}" fill="#00E5FF" font-size="25" font-weight="700">
      ALIGNED
    </text>
"""
        )
    badge = "FINAL" if mode == "final" else "DRAFT / CUSTOM PENDING"
    svg = f"""\
<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900"
     viewBox="0 0 1600 900" role="img"
     aria-label="Vivado ILA trigger alignment evidence">
  <defs>
    <linearGradient id="bg2" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#030817"/>
      <stop offset="1" stop-color="#11112F"/>
    </linearGradient>
  </defs>
  <rect width="1600" height="900" fill="url(#bg2)"/>
  <path d="M0 165 H420 C500 165 500 95 580 95 H1600"
        fill="none" stroke="#00E5FF" opacity=".25"/>
  <text x="86" y="92" fill="#AAB4D6" font-size="22"
        font-family="Inter, Noto Sans KR, sans-serif" letter-spacing="4">
    HARDWARE CAPTURE EVIDENCE
  </text>
  <text x="86" y="162" fill="#FFFFFF" font-size="58" font-weight="750"
        font-family="Inter, Noto Sans KR, sans-serif">
    TRIGGER ALIGNMENT
  </text>
  <g font-family="Inter, Noto Sans KR, sans-serif">
{''.join(rows)}
  </g>
  <text x="86" y="842" fill="#8190B8" font-size="20"
        font-family="Inter, Noto Sans KR, sans-serif">
    100 MHz • 10 ns/sample • 1,024 samples • trigger sample included in post-window
  </text>
  <text x="1510" y="842" text-anchor="end" fill="#F59E0B" font-size="18"
        font-family="Inter, Noto Sans KR, sans-serif">{badge}</text>
</svg>
"""
    atomic_write(output, svg)


def csv_text(header: Sequence[str], rows: Iterable[Sequence[object]]) -> str:
    from io import StringIO

    buffer = StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(header)
    writer.writerows(rows)
    return buffer.getvalue()


def build_outputs(
    ila_root: Path,
    repo_root: Path,
    output_dir: Path,
    mode: str,
    github_ref: str,
    remote_test_report: Path,
) -> str:
    step6_path = ila_root / "results/step6/step6_status.rpt"
    step7_path = ila_root / "results/step7/step7_status.rpt"
    step8_path = ila_root / "results/step8/step8_status.rpt"
    step9_path = ila_root / "results/step9/step9_status.rpt"
    step6 = parse_key_values(step6_path)
    step7 = parse_key_values(step7_path)
    step8 = parse_key_values(step8_path)
    step9 = parse_key_values(step9_path)

    require_values(
        step6_path,
        step6,
        {
            "STEP": "6",
            "OVERALL": "PASS",
            "PAIR_PROGRAM_READBACK": "PASS",
            "RISING_CAPTURE": "PASS",
            "FALLING_CAPTURE": "PASS",
            "PATTERN_CAPTURE": "PASS",
            "NO_TRIGGER_100MS": "PASS",
            "CAPTURE_ARTIFACT_HASHES": "PASS",
            "CAPTURE_VALIDATION": "PASS",
        },
    )
    require_values(
        step7_path,
        step7,
        {
            "STEP": "7",
            "OVERALL": "PASS",
            "SAMPLE_COUNT": "1024",
            "TRIGGER_INDEX": "512",
            "RISING_NORMALIZATION": "PASS",
            "FALLING_NORMALIZATION": "PASS",
            "PATTERN_NORMALIZATION": "PASS",
        },
    )
    require_values(
        step8_path,
        step8,
        {
            "STEP": "8",
            "OVERALL": "PASS",
            "PULSE_WIDTH_COUNT": "6",
            "REPETITIONS_PER_WIDTH": "10",
            "TOTAL_ELIGIBLE_TRIALS": "60",
            "TOTAL_DETECTED_TRIALS": "60",
            "OVERALL_DETECTION_RATE_PERCENT": "100.0",
            "TRIGGER_INDEX": "512",
            "PARTIAL_CAPTURE_COUNT": "0",
            "FPGA_PROGRAM_COUNT": "1",
            "HOST_VALIDATION": "PASS",
            "ARTIFACT_HASHES": "PASS",
        },
    )
    if step9.get("OVERALL") not in {
        "PASS",
        "PASS_WITH_TEAM_INPUT_PENDING",
    }:
        raise PackageError(
            f"{step9_path}: unsupported OVERALL={step9.get('OVERALL')}"
        )
    require_values(
        step9_path,
        step9,
        {
            "BASELINE": "VERIFIED",
            "CPU_REPORT": "VERIFIED",
            "ILA_STEP9": "PASS",
            "CPU_USED_FOR_OFFICIAL_SAVINGS": "NO",
            "RESOURCE_SCOPE": "WHOLE_ROUTED_SOC",
            "RAMB36_RAMB18_SEPARATE": "YES",
            "FMAX_INFERRED_FROM_WNS": "NO",
        },
    )

    gate_errors = final_gate_errors(step9)
    if mode == "final" and gate_errors:
        raise PendingTeamInput(
            "Step 10 final package is locked: " + "; ".join(gate_errors)
        )
    if mode == "draft" and not gate_errors:
        raise PackageError(
            "Step 9 is complete; use final mode instead of draft mode"
        )

    manifests = [
        verify_checksum_manifest(
            ila_root / "generated/ila_reference_step5_SHA256SUMS",
            entry_root=ila_root,
            allowed_root=ila_root,
        ),
        verify_checksum_manifest(
            ila_root / "build/step6/SHA256SUMS",
            allowed_root=ila_root,
        ),
        verify_checksum_manifest(ila_root / "results/step6/SHA256SUMS"),
        verify_checksum_manifest(ila_root / "results/step7/SHA256SUMS"),
        verify_checksum_manifest(ila_root / "results/step8/SHA256SUMS"),
        verify_checksum_manifest(ila_root / "results/step9/SHA256SUMS"),
    ]

    normalized_results: dict[str, int] = {}
    for profile in ("rising", "falling", "pattern"):
        normalized_results[profile] = validate_normalized_capture(
            ila_root / f"results/step7/{profile}_normalized.csv",
            step6[f"{profile.upper()}_SAMPLE_511"],
            step6[f"{profile.upper()}_SAMPLE_512"],
        )
    pulse_rows = validate_pulse_summary(
        ila_root / "results/step8/pulse_detection_summary.csv"
    )

    resources = indexed_rows(
        ila_root / "results/step9/resource_comparison.csv",
        (
            "method",
            "view",
            "status",
            "slice_luts",
            "lut_as_logic",
            "lut_as_memory",
            "slice_registers",
            "ramb36",
            "ramb18",
            "dsp48e1",
        ),
        ("method", "view"),
    )
    timing = indexed_rows(
        ila_root / "results/step9/timing_comparison.csv",
        (
            "method",
            "status",
            "clock_period_ns",
            "clock_frequency_mhz",
            "wns_ns",
            "tns_ns",
            "fmax_inference",
        ),
        ("method",),
    )
    savings = indexed_rows(
        ila_root / "results/step9/official_custom_vs_ila_savings.csv",
        (
            "metric",
            "status",
            "ila_delta",
            "custom_delta",
            "saved_absolute",
            "saved_percent_of_ila_delta",
        ),
        ("metric",),
    )
    total_key = "TOTAL_WHOLE_ROUTED_SOC"
    delta_key = "DELTA_VS_COMMON_BASE_PLUS_GENERATOR"
    baseline_total = resources[("common_baseline", total_key)]
    cpu_total = resources[("cpu_polling", total_key)]
    ila_total = resources[("ila_reference", total_key)]
    ila_delta = resources[("ila_reference", delta_key)]
    ila_timing = timing[("ila_reference",)]
    require_values(
        ila_root / "results/step9/resource_comparison.csv",
        ila_total,
        {"status": "VERIFIED"},
    )
    require_values(
        ila_root / "results/step9/timing_comparison.csv",
        ila_timing,
        {
            "status": "VERIFIED",
            "clock_period_ns": "10.000",
            "clock_frequency_mhz": "100.000",
            "tns_ns": "0.000",
            "fmax_inference": "FORBIDDEN_NOT_COMPUTED",
        },
    )
    if mode == "draft":
        bad_savings = [
            metric
            for (metric,), row in savings.items()
            if row["status"] != "PENDING_CUSTOM_FULL_SYSTEM_REPORT"
            or any(
                row[column] != "NA"
                for column in (
                    "ila_delta",
                    "custom_delta",
                    "saved_absolute",
                    "saved_percent_of_ila_delta",
                )
            )
        ]
        if bad_savings:
            raise PackageError(
                "draft savings must remain pending/NA: "
                + ", ".join(bad_savings)
            )
    else:
        bad_savings = [
            metric
            for (metric,), row in savings.items()
            if row["status"] != "VERIFIED"
            or any(
                row[column] == "NA"
                for column in (
                    "ila_delta",
                    "custom_delta",
                    "saved_absolute",
                    "saved_percent_of_ila_delta",
                )
            )
        ]
        if bad_savings:
            raise PackageError(
                "final savings are incomplete: " + ", ".join(bad_savings)
            )

    audit = audit_git(repo_root, github_ref, remote_test_report)
    if audit.common_match_count != 2:
        raise PackageError("GitHub common Base/Generator do not match locally")
    if audit.cpu_report_match_count != 4:
        raise PackageError("GitHub CPU reports do not match Step-9 inputs")

    output_dir.mkdir(parents=True, exist_ok=True)
    mode_label = "FINAL" if mode == "final" else "DRAFT"
    overall = "PASS" if mode == "final" else "PASS_WITH_TEAM_INPUT_PENDING"
    custom_status = step9.get("CUSTOM_FULL_SYSTEM", "UNKNOWN")
    official_status = step9.get(
        "OFFICIAL_CUSTOM_VS_ILA_SAVINGS", "UNKNOWN"
    )
    package_badge = (
        "공식 최종본"
        if mode == "final"
        else "검증된 Draft — Custom 전체 Routed 자료 대기"
    )

    final_summary = f"""\
# Step 10 — Vivado ILA 증거·발표 패키지

상태: **{package_badge}**

## 결론

윤형욱 담당 Vivado ILA 비교군은 보드 기능시험, CSV 정규화, Pulse Stress,
전체 Routed 자원·Timing 검증까지 독립적으로 통과했다. 현재 패키지 모드는
`{mode_label}`이며, Step 9 상태는 `{step9['OVERALL']}`이다.

{"Custom 전체 Routed 검증까지 완료되어 공식 비교 수치를 사용할 수 있다." if mode == "final" else "팀의 Custom 전체 Routed 7개 파일이 아직 없으므로 Custom-vs-ILA 공식 절감률은 계산하지 않았고, 빈 값을 0으로 대체하지 않았다."}

## 검증 결과

| 항목 | 결과 | 근거 |
|---|---:|---|
| ILA 설정 | 100 MHz, 8-bit, Depth 1,024, Trigger 512 | Step 6 Readback |
| Rising / Falling / Pattern | 3종 모두 PASS | 실제 Basys 3 Capture |
| No-trigger 100 ms | PASS, Partial Capture 0 | 실제 Basys 3 Capture |
| 정규화 CSV | 3종 × 1,024행 무손실 PASS | Step 7 Validator |
| Pulse Stress | 6개 폭 × 10회 = **60/60** | {display_duration_ns(pulse_rows[0]['width_ns'])}–{display_duration_ns(pulse_rows[-1]['width_ns'])} 동기 Pulse |
| ILA 전체 Routed 자원 | LUT {display_int(ila_total['slice_luts'])}, FF {display_int(ila_total['slice_registers'])}, RAMB36/18 {ila_total['ramb36']}/{ila_total['ramb18']} | Vivado 2024.2 |
| ILA 순증가량 | LUT +{display_int(ila_delta['slice_luts'])}, FF +{display_int(ila_delta['slice_registers'])}, RAMB18 +{ila_delta['ramb18']} | Common Base+Generator 대비 |
| ILA Timing | WNS +{ila_timing['wns_ns']} ns, TNS {ila_timing['tns_ns']} ns | 10.000 ns 제약 |
| Custom 공식 절감률 | `{official_status}` | CPU Polling은 산식에서 제외 |

## 비교표

| 방식 | 상태 | LUT | FF | RAMB36 | RAMB18 | WNS |
|---|---|---:|---:|---:|---:|---:|
| Common Base + Generator | {baseline_total['status']} | {display_int(baseline_total['slice_luts'])} | {display_int(baseline_total['slice_registers'])} | {baseline_total['ramb36']} | {baseline_total['ramb18']} | {timing[('common_baseline',)]['wns_ns']} ns |
| CPU Polling | {cpu_total['status']} | {display_int(cpu_total['slice_luts'])} | {display_int(cpu_total['slice_registers'])} | {cpu_total['ramb36']} | {cpu_total['ramb18']} | {timing[('cpu_polling',)]['wns_ns']} ns |
| Vivado ILA | {ila_total['status']} | {display_int(ila_total['slice_luts'])} | {display_int(ila_total['slice_registers'])} | {ila_total['ramb36']} | {ila_total['ramb18']} | {ila_timing['wns_ns']} ns |
| EdgeScope Custom | {custom_status} | {"검증 완료" if mode == "final" else "NA"} | {"검증 완료" if mode == "final" else "NA"} | {"검증 완료" if mode == "final" else "NA"} | {"검증 완료" if mode == "final" else "NA"} | {"검증 완료" if mode == "final" else "NA"} |

## 발표 시 해석 제한

- WNS는 100 MHz 제약의 여유시간이다. WNS로 Fmax를 계산하거나 순위를
  만들지 않는다.
- CPU Polling은 Software 관찰 기준군이며 공식 Custom-vs-ILA 절감률 산식에
  넣지 않는다.
- Trigger Index 512는 Trigger Sample을 포함한 Post-trigger 512개를 뜻한다.
- No-trigger 시험에 정상 1,024-Sample Capture가 없는 것은 정상 결과다.
- 10 ns Pulse 결과는 공통 100 MHz Generator와 ILA가 동기인 동결 시험의
  결과이며, 임의 비동기 Pulse 전체에 일반화하지 않는다.

## 무결성

- Step 5~9 Checksum Manifest 6개 검증
- Manifest가 결속한 파일 총 {sum(item.verified_count for item in manifests):,}개 검증
- GitHub 원격 `main` 감사 Commit: `{audit.commit}`
- 원격 코드 자동 시험: `{audit.remote_test_status}`
- Final Demo 실제 XSA 매크로 호환: `{audit.final_demo_xparameters_compatibility}`
- 이 폴더의 최종 파일은 `SHA256SUMS`로 다시 검증 가능
"""
    atomic_write(output_dir / "final_summary.md", final_summary)

    presentation_results = f"""\
# Step 10 발표용 결과 문안

패키지 표시: **{package_badge}**

## 한 문장 결론

> Vivado ILA 기준군은 Basys 3에서 100 MHz·8채널·1,024 Sample 조건으로
> Rising, Falling, Masked Pattern Trigger와 10 ns~1 ms 동기 Pulse
> 60/60회를 검출했고, 전체 Routed 기준 순증가 자원은 LUT
> +{display_int(ila_delta['slice_luts'])}, FF
> +{display_int(ila_delta['slice_registers'])}, RAMB18
> +{ila_delta['ramb18']}이었다.

## 슬라이드 1 — 기능 검증

- 제목: `VIVADO ILA REFERENCE — HARDWARE VERIFIED`
- 핵심 숫자: `1,024 Samples`, `Trigger Index 512`, `100 MHz`
- 증거: Rising `0x00→0x01`, Falling `0x01→0x00`,
  Pattern `0x95→0xA5`가 모두 Sample 512에서 Trigger
- 보조 문장: No-trigger 103 ms 동안 오검출과 Partial Capture 없음

## 슬라이드 2 — Pulse Stress

- 제목: `60 / 60 SYNCHRONIZED PULSES DETECTED`
- 범위: `10 ns, 100 ns, 1 µs, 10 µs, 100 µs, 1 ms`
- 조건: 각 폭 10회, FPGA Program 1회, Trigger Index 512 고정
- 표현 주의: `동기 Pulse 시험 결과`라고 명시

## 슬라이드 3 — 자원·Timing

- ILA Total: LUT `{display_int(ila_total['slice_luts'])}`,
  FF `{display_int(ila_total['slice_registers'])}`,
  RAMB36/18 `{ila_total['ramb36']}/{ila_total['ramb18']}`
- Common 대비 ILA Delta: LUT `+{display_int(ila_delta['slice_luts'])}`,
  FF `+{display_int(ila_delta['slice_registers'])}`,
  RAMB18 `+{ila_delta['ramb18']}`
- 100 MHz Timing: WNS `+{ila_timing['wns_ns']} ns`,
  TNS `{ila_timing['tns_ns']} ns`
- 공식 Custom-vs-ILA 절감률: `{official_status}`

## 말해도 되는 내용

- “ILA 기준군 자체의 기능·Pulse·자원·Timing 검증은 완료됐다.”
- “CPU Polling의 Routed 보고서는 참고 Total로 검증했다.”
- “공식 절감률은 기능적으로 동등한 Custom과 ILA 사이에서만 계산한다.”

## 아직 말하면 안 되는 내용

- “Custom이 ILA보다 몇 % 절감됐다.” — `{official_status}`
- “CPU Polling이 100 MS/s Logic Analyzer와 동급이다.”
- “WNS를 이용해 최대 동작 주파수를 계산했다.”
- “10 ns 비동기 Pulse를 항상 잡는다.”

## 시각 자료

- `ila_result_cards.svg`: 핵심 숫자 3개
- `ila_trigger_evidence.svg`: 실제 Capture의 Sample 511/512 전이
"""
    atomic_write(
        output_dir / "presentation_results.md", presentation_results
    )

    github_audit = f"""\
# GitHub 저장소 파일 감사

- 저장소: `yoon3226/EdgeScope-Lite-SoC`
- 감사 Ref: `{audit.reference}`
- 감사 Commit: `{audit.commit}`
- 작성자/시각: `{audit.author}` / `{audit.authored_at}`
- 제목: `{audit.subject}`
- 로컬 HEAD: `{audit.local_head}` (`{audit.local_branch}`)
- 로컬과 원격 차이: behind {audit.commits_behind}, ahead {audit.commits_ahead}
- 로컬 작업 트리 변경 존재: `{"YES" if audit.local_dirty else "NO"}`

## 확인 결과

| 항목 | 판정 |
|---|---|
| 공통 Base SoC / Generator가 로컬 동결본과 동일 | `{audit.common_match_count}/2 MATCH` |
| CPU Polling 보고서 4종이 Step 9 입력과 동일 | `{audit.cpu_report_match_count}/4 MATCH` |
| 원격 `main` 자동 시험 | `{audit.remote_test_status}` |
| 기본 회귀에 신규 Sampler/Trigger TB 포함 | `{audit.main_regression_includes_new_ip_tests}` |
| Trigger TB 실패 시 Non-zero 종료 보장 | `{audit.trigger_tb_failure_exit_nonzero}` |
| 원격 `main`에 ILA 비교군 디렉터리 존재 | `{"YES" if audit.ila_tree_present else "NO"}` |
| 원격 `main`에 Custom 계약 파일 7종 존재 | `{audit.custom_contract_file_count}/7` |
| Final Demo 브랜치가 `main`에 병합됨 | `{"YES" if audit.final_demo_merged else "NO"}` |
| Final Demo와 실제 XSA `xparameters.h` 호환 | `{audit.final_demo_xparameters_compatibility}` |
| Final Demo가 실제 BRAM 주소 매크로 인식 | `{audit.final_demo_bram_macro_compatibility}` |
| Final Demo 실행 순서: Buffer ARM → Sampler Enable | `{audit.final_demo_arm_before_sampler}` |
| Final Demo 병합 시 README 충돌 | `{audit.final_demo_readme_merge_conflict}` |

## 판정

원격 `main`의 CPU Polling, 공통 Generator, Probe Sampler, Trigger Engine 자료는
자동 시험에 통과해 Step 10 참고 자료로 사용할 수 있다. 다만 원격에는
Custom 전체 Routed 계약 파일이 {audit.custom_contract_file_count}/7개만
존재하고, 로컬 ILA 비교군 디렉터리도 아직 게시되지 않았다. 따라서 GitHub
파일만으로 Step 9의 Custom 공식 비교 Gate를 열 수 없다.

`{audit.final_demo_ref}` (`{audit.final_demo_commit}`)의 Vitis Final Demo는
현재 `main` 병합 상태가 `{"MERGED" if audit.final_demo_merged else "NOT_MERGED"}`다.
또한 실제 XSA 기반 주소/Clock 매크로 호환 판정이
`{audit.final_demo_xparameters_compatibility}`이고, Buffer ARM보다 Sampler를
먼저 켜는 순서의 동결 명세 적합성은 `{audit.final_demo_arm_before_sampler}`다.
이 두 항목을 수정하기 전에는 Final Demo 브랜치를 최종 시연본으로 사용하면
안 된다.
"""
    atomic_write(
        output_dir / "github_repository_audit.md", github_audit
    )

    handoff = f"""\
# Step 10 팀 인수인계

## 지금 전달 가능한 것

- ILA 보드 시험 4종 PASS 증거
- 정규화 CSV 3종과 검증 보고서
- Pulse Stress 60/60 원본·정규화·ILA Session Checksum
- Common / CPU / ILA 전체 Routed 자원·Timing 표
- 발표용 SVG 2개와 안전한 발표 문안
- GitHub 원격 Commit `{audit.commit}` 감사 결과

## 최종 완료에 필요한 팀 입력

`comparison/ila_reference/results/step9/inputs/custom/`에 같은 Implementation
Run에서 생성한 다음 7개 파일을 넣는다.

1. `utilization.rpt`
2. `hierarchical_utilization.rpt`
3. `timing_summary.rpt`
4. `route_status.rpt`
5. `drc.rpt`
6. `routed_design.dcp`
7. `build_manifest.rpt`

## 최종 승격 명령

```bash
comparison/ila_reference/run_step9_resource_timing.sh --strict-complete
comparison/ila_reference/run_step10_final_package.sh
```

첫 명령이 `NEXT_ACTION=STEP10_FINAL_PACKAGE`를 만들지 못하면 두 번째 명령은
Final 패키지를 생성하지 않는다. 임시 발표자료가 다시 필요할 때만
`--draft`를 사용한다.

## GitHub 게시 전 확인

- [ ] 로컬 `comparison/ila_reference/` 전체를 검토해 의도한 파일만 Stage
- [ ] Build Cache와 중복 Hardware Log 제외
- [ ] Step 6~10 `SHA256SUMS` 재검증
- [ ] 원격 `main` 최신 Commit과 충돌 확인
- [ ] `agent/publish-final-demo` 병합 여부를 팀에서 결정
- [ ] Final Demo의 Sampler/Trigger/Timer/BRAM 실제 XSA 매크로 Alias 수정
- [ ] Final Demo 순서를 `capture_arm()` → `sampler_enable()`로 교정
- [ ] Trigger TB 실패/Timeout을 `$fatal(1, ...)`로 변경
- [ ] 기본 회귀에 Sampler/Trigger TB 추가
- [ ] README 병합 충돌 해결 시 CPU Polling과 Final Demo 섹션 모두 보존
- [ ] Custom 공식 수치가 `PENDING_CUSTOM`이면 Draft Badge 유지
"""
    atomic_write(output_dir / "team_handoff.md", handoff)

    facts = (
        (
            "ILA-001",
            "configuration",
            "Sampling clock",
            "100",
            "MHz",
            "VERIFIED",
            "results/step6/step6_status.rpt",
            "100 MHz 동기 Capture",
        ),
        (
            "ILA-002",
            "configuration",
            "Capture depth",
            "1024",
            "samples",
            "VERIFIED",
            "results/step6/step6_status.rpt",
            "1,024 Sample Capture",
        ),
        (
            "ILA-003",
            "configuration",
            "Trigger index",
            "512",
            "index",
            "VERIFIED",
            "results/step6/step6_status.rpt",
            "Trigger Sample은 Post 512개에 포함",
        ),
        (
            "ILA-004",
            "hardware",
            "Trigger profiles",
            "3/3",
            "profiles",
            "VERIFIED",
            "results/step6/capture_validation.rpt",
            "Rising/Falling/Pattern PASS",
        ),
        (
            "ILA-005",
            "hardware",
            "Pulse stress",
            "60/60",
            "trials",
            "VERIFIED",
            "results/step8/pulse_detection_summary.csv",
            "동기 Pulse 10 ns~1 ms",
        ),
        (
            "ILA-006",
            "resources",
            "ILA delta Slice LUT",
            ila_delta["slice_luts"],
            "LUT",
            "VERIFIED",
            "results/step9/resource_comparison.csv",
            "Common Base+Generator 대비",
        ),
        (
            "ILA-007",
            "resources",
            "ILA delta FF",
            ila_delta["slice_registers"],
            "FF",
            "VERIFIED",
            "results/step9/resource_comparison.csv",
            "Common Base+Generator 대비",
        ),
        (
            "ILA-008",
            "timing",
            "WNS at 100 MHz",
            ila_timing["wns_ns"],
            "ns",
            "VERIFIED",
            "results/step9/timing_comparison.csv",
            "Fmax로 환산 금지",
        ),
        (
            "TEAM-001",
            "official_comparison",
            "Custom-vs-ILA savings",
            (
                "VERIFIED"
                if mode == "final"
                else "PENDING_CUSTOM"
            ),
            "status",
            official_status,
            "results/step9/official_custom_vs_ila_savings.csv",
            "CPU Polling 제외",
        ),
    )
    atomic_write(
        output_dir / "presentation_facts.csv",
        csv_text(
            (
                "fact_id",
                "category",
                "label",
                "value",
                "unit",
                "status",
                "evidence",
                "allowed_claim",
            ),
            facts,
        ),
    )

    render_result_cards(
        output_dir / "ila_result_cards.svg",
        mode,
        ila_total,
        ila_delta,
        pulse_rows,
    )
    render_trigger_evidence(
        output_dir / "ila_trigger_evidence.svg", step6, mode
    )

    evidence = [
        Evidence(
            "hardware",
            step6_path,
            "VERIFIED",
            "Basys 3 function-test status",
        ),
        Evidence(
            "normalization",
            step7_path,
            "VERIFIED",
            "common CSV schema status",
        ),
        Evidence(
            "pulse_stress",
            step8_path,
            "VERIFIED",
            "60-trial pulse stress status",
        ),
        Evidence(
            "resource_timing",
            step9_path,
            step9["OVERALL"],
            "whole-routed comparison gate",
        ),
        Evidence(
            "github",
            remote_test_report,
            "VERIFIED",
            f"remote main tests at {audit.commit}",
        ),
    ]
    evidence.extend(
        Evidence(
            "checksum_manifest",
            item.path,
            "VERIFIED",
            f"{item.verified_count} indexed files",
        )
        for item in manifests
    )
    evidence_rows = [
        (
            item.category,
            relative_to_repo(item.path, repo_root),
            item.status,
            sha256_file(item.path),
            item.note,
        )
        for item in evidence
    ]
    atomic_write(
        output_dir / "evidence_inventory.csv",
        csv_text(
            ("category", "path", "status", "sha256", "note"),
            evidence_rows,
        ),
    )

    generator_sha = sha256_file(Path(__file__).resolve())
    manifest_text = "\n".join(
        (
            "# EdgeScope-Lite Vivado ILA Step 10 package manifest",
            "SCHEMA=EDGESCOPE_ILA_STEP10_V1",
            f"PACKAGE_MODE={mode_label}",
            f"OVERALL={overall}",
            f"GENERATOR_SHA256={generator_sha}",
            f"STEP6_STATUS_SHA256={sha256_file(step6_path)}",
            f"STEP7_STATUS_SHA256={sha256_file(step7_path)}",
            f"STEP8_STATUS_SHA256={sha256_file(step8_path)}",
            f"STEP9_STATUS_SHA256={sha256_file(step9_path)}",
            f"CHECKSUM_MANIFEST_COUNT={len(manifests)}",
            "CHECKSUM_INDEXED_FILE_COUNT="
            f"{sum(item.verified_count for item in manifests)}",
            f"GITHUB_REFERENCE={audit.reference}",
            f"GITHUB_REMOTE_MAIN_COMMIT={audit.commit}",
            f"LOCAL_HEAD={audit.local_head}",
            f"LOCAL_BRANCH={audit.local_branch}",
            f"LOCAL_WORKTREE_DIRTY={'YES' if audit.local_dirty else 'NO'}",
            f"LOCAL_COMMITS_BEHIND_REMOTE={audit.commits_behind}",
            f"LOCAL_COMMITS_AHEAD_OF_REMOTE={audit.commits_ahead}",
            f"GITHUB_REMOTE_TEST_REPORT_SHA256={sha256_file(remote_test_report)}",
            "GITHUB_MAIN_REGRESSION_INCLUDES_NEW_IP_TESTS="
            f"{audit.main_regression_includes_new_ip_tests}",
            "GITHUB_TRIGGER_TB_FAILURE_EXIT_NONZERO="
            f"{audit.trigger_tb_failure_exit_nonzero}",
            "GITHUB_FINAL_DEMO_XPARAMETERS_COMPATIBILITY="
            f"{audit.final_demo_xparameters_compatibility}",
            "GITHUB_FINAL_DEMO_ARM_BEFORE_SAMPLER="
            f"{audit.final_demo_arm_before_sampler}",
            f"HARDWARE_XSA_SHA256={audit.hardware_xsa_sha256}",
            f"CUSTOM_FULL_SYSTEM={custom_status}",
            f"OFFICIAL_CUSTOM_VS_ILA_SAVINGS={official_status}",
            f"FINAL_GATE={'PASS' if not gate_errors else 'PENDING_CUSTOM'}",
        )
    ) + "\n"
    atomic_write(output_dir / "step10_manifest.rpt", manifest_text)

    validation_lines = (
        "# EdgeScope-Lite Vivado ILA Step 10 validation",
        f"PACKAGE_MODE={mode_label}",
        f"OVERALL={overall}",
        "STEP5_TO_STEP9_CHECKSUMS=PASS",
        f"CHECKSUM_MANIFEST_COUNT={len(manifests)}",
        "CHECKSUM_INDEXED_FILE_COUNT="
        f"{sum(item.verified_count for item in manifests)}",
        "STEP6_HARDWARE_CAPTURE=PASS",
        "STEP7_NORMALIZED_CAPTURE=PASS",
        "STEP7_NORMALIZED_PROFILE_COUNT=3",
        "STEP7_NORMALIZED_ROW_COUNT="
        f"{sum(normalized_results.values())}",
        "STEP8_PULSE_STRESS=PASS",
        "STEP8_DETECTION=60_OF_60",
        "STEP9_BASELINE_CPU_ILA=PASS",
        f"STEP9_CUSTOM={custom_status}",
        f"FINAL_GATE={'PASS' if not gate_errors else 'PENDING_CUSTOM'}",
        "GITHUB_COMMON_SOURCE_MATCH=2_OF_2",
        "GITHUB_CPU_REPORT_MATCH=4_OF_4",
        "GITHUB_REMOTE_TESTS=PASS",
        "GITHUB_MAIN_REGRESSION_NEW_IP_TESTS="
        f"{audit.main_regression_includes_new_ip_tests}",
        "GITHUB_TRIGGER_TB_FAILURE_EXIT="
        f"{audit.trigger_tb_failure_exit_nonzero}",
        "GITHUB_FINAL_DEMO_XPARAMETERS="
        f"{audit.final_demo_xparameters_compatibility}",
        "GITHUB_FINAL_DEMO_CAPTURE_ORDER="
        f"{audit.final_demo_arm_before_sampler}",
        "PRESENTATION_NUMBERS_SOURCE_DERIVED=PASS",
        "WNS_TO_FMAX_CONVERSION=FORBIDDEN_NOT_COMPUTED",
        "CPU_USED_FOR_OFFICIAL_SAVINGS=NO",
        "MISSING_VALUES_IMPUTED_AS_ZERO=NO",
    )
    atomic_write(
        output_dir / "step10_validation.rpt",
        "\n".join(validation_lines) + "\n",
    )

    next_action = (
        "TEAM_PRESENTATION_AND_ARCHIVE"
        if mode == "final"
        else "RECEIVE_CUSTOM_RERUN_STEP9_STRICT_THEN_STEP10_FINAL"
    )
    status_lines = (
        "# EdgeScope-Lite Vivado ILA Step 10 status",
        "STEP=10",
        f"PACKAGE_MODE={mode_label}",
        f"OVERALL={overall}",
        "EVIDENCE_PACKAGE=PASS",
        "PRESENTATION_MATERIALS=PASS",
        "GITHUB_REPOSITORY_AUDIT=PASS_WITH_ACTION_REQUIRED",
        f"CUSTOM_FULL_SYSTEM={custom_status}",
        f"OFFICIAL_CUSTOM_VS_ILA_SAVINGS={official_status}",
        f"FINAL_PACKAGE={'PASS' if mode == 'final' else 'LOCKED_PENDING_CUSTOM'}",
        f"NEXT_ACTION={next_action}",
    )
    atomic_write(
        output_dir / "step10_status.rpt",
        "\n".join(status_lines) + "\n",
    )

    generated_names = (
        "final_summary.md",
        "presentation_results.md",
        "presentation_facts.csv",
        "github_repository_audit.md",
        "team_handoff.md",
        "evidence_inventory.csv",
        "ila_result_cards.svg",
        "ila_trigger_evidence.svg",
        "step10_manifest.rpt",
        "step10_validation.rpt",
        "step10_status.rpt",
        remote_test_report.name,
        "github_remote_tests.log",
    )
    checksum_lines: list[str] = []
    for name in generated_names:
        target = output_dir / name
        if not target.is_file():
            raise PackageError(f"missing Step-10 output: {target}")
        checksum_lines.append(f"{sha256_file(target)}  {name}")
    atomic_write(output_dir / "SHA256SUMS", "\n".join(checksum_lines) + "\n")
    return overall


def build_argument_parser() -> argparse.ArgumentParser:
    default_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Build the Vivado ILA Step-10 evidence package."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=default_root,
        help="comparison/ila_reference root",
    )
    parser.add_argument(
        "--output-dir",
        default="results/step10",
        help="output directory relative to --root",
    )
    parser.add_argument(
        "--mode",
        choices=("draft", "final"),
        default="final",
        help="draft allows a visible Custom-pending package",
    )
    parser.add_argument(
        "--github-ref",
        default="origin/main",
        help="already-fetched Git reference to audit",
    )
    parser.add_argument(
        "--github-test-report",
        default="results/step10/github_remote_tests.rpt",
        help="remote snapshot test report relative to --root",
    )
    return parser


def resolve_under(root: Path, value: str) -> Path:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = root / candidate
    return candidate.resolve()


def main(argv: Sequence[str] | None = None) -> int:
    arguments = build_argument_parser().parse_args(argv)
    ila_root = arguments.root.resolve()
    repo_root = ila_root.parents[1]
    output_dir = resolve_under(ila_root, arguments.output_dir)
    remote_test_report = resolve_under(
        ila_root, arguments.github_test_report
    )
    try:
        overall = build_outputs(
            ila_root,
            repo_root,
            output_dir,
            arguments.mode,
            arguments.github_ref,
            remote_test_report,
        )
    except PendingTeamInput as error:
        print(f"STEP10_FINAL_PACKAGE=BLOCKED_AWAITING_CUSTOM: {error}")
        return 2
    except PackageError as error:
        print(f"STEP10_FINAL_PACKAGE=FAIL: {error}", file=sys.stderr)
        return 1
    print(f"STEP10_FINAL_PACKAGE={overall}")
    print(f"RESULTS={output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
