#!/usr/bin/env python3
"""Validate the fixed Step-6 ILA hardware evidence."""

from __future__ import annotations

import argparse
import csv
import hashlib
from pathlib import Path


PROFILE_EXPECTATIONS = {
    "rising": (0x00, 0x01),
    "falling": (0x01, 0x00),
    "pattern": (0x95, 0xA5),
}


def fail(message: str) -> None:
    raise SystemExit(f"STEP6_CAPTURE_VALIDATION: FAIL: {message}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_report(path: Path) -> dict[str, str]:
    if not path.is_file():
        fail(f"missing report: {path}")
    fields: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key] = value
    return fields


def require_equal(label: str, actual: object, expected: object) -> None:
    if actual != expected:
        fail(f"{label}: actual={actual!r}, expected={expected!r}")


def validate_profile(results_dir: Path, profile: str) -> list[str]:
    expected_before, expected_trigger = PROFILE_EXPECTATIONS[profile]
    csv_path = results_dir / f"{profile}_raw.csv"
    ila_path = results_dir / f"{profile}.ila"
    report = read_report(results_dir / f"capture_{profile}.rpt")

    for path in (csv_path, ila_path):
        if not path.is_file() or path.stat().st_size == 0:
            fail(f"{profile}: missing or empty artifact: {path}")

    require_equal(f"{profile} report profile", report.get("PROFILE"), profile)
    require_equal(
        f"{profile} report result", report.get("RESULT"), "CAPTURE_COMPLETE"
    )
    require_equal(f"{profile} partial capture", report.get("PARTIAL_CAPTURE"), "0")
    require_equal(
        f"{profile} CSV hash",
        sha256(csv_path),
        report.get("RAW_CSV_SHA256"),
    )
    require_equal(
        f"{profile} ILA hash",
        sha256(ila_path),
        report.get("ILA_FILE_SHA256"),
    )

    with csv_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None or len(reader.fieldnames) != 4:
            fail(f"{profile}: unexpected CSV header: {reader.fieldnames!r}")
        sample_key, window_key, trigger_key, value_key = reader.fieldnames
        require_equal(f"{profile} sample column", sample_key, "Sample in Buffer")
        require_equal(f"{profile} window column", window_key, "Sample in Window")
        require_equal(f"{profile} trigger column", trigger_key, "TRIGGER")

        samples: list[tuple[int, int, int]] = []
        for row in reader:
            try:
                sample = int(row[sample_key])
            except ValueError:
                # Vivado emits one "Radix - ..." metadata row after the header.
                continue
            window = int(row[window_key])
            trigger = int(row[trigger_key])
            value = int(row[value_key], 16)
            require_equal(f"{profile} window index {sample}", window, sample)
            samples.append((sample, trigger, value))

    require_equal(f"{profile} sample count", len(samples), 1024)
    require_equal(
        f"{profile} sample indices",
        [sample for sample, _, _ in samples],
        list(range(1024)),
    )
    trigger_samples = [sample for sample, trigger, _ in samples if trigger == 1]
    require_equal(f"{profile} trigger markers", trigger_samples, [512])
    require_equal(
        f"{profile} sample 511",
        samples[511][2],
        expected_before,
    )
    require_equal(
        f"{profile} sample 512",
        samples[512][2],
        expected_trigger,
    )

    return [
        f"{profile.upper()}_SAMPLE_COUNT=1024",
        f"{profile.upper()}_TRIGGER_SAMPLE=512",
        f"{profile.upper()}_SAMPLE_511=0x{samples[511][2]:02X}",
        f"{profile.upper()}_SAMPLE_512=0x{samples[512][2]:02X}",
        f"{profile.upper()}_RESULT=PASS",
    ]


def validate_pair(results_dir: Path) -> list[str]:
    report = read_report(results_dir / "pair_readback.rpt")
    require_equal("pair result", report.get("RESULT"), "PASS")
    require_equal("pair ILA cell", report.get("ILA_CELL"), "base_soc_i/ila_reference_0")
    for profile in (*PROFILE_EXPECTATIONS, "no_trigger"):
        require_equal(
            f"{profile} pair result",
            report.get(f"PROFILE.{profile}.RESULT"),
            "PASS",
        )
        require_equal(
            f"{profile} data depth",
            report.get(f"PROFILE.{profile}.DATA_DEPTH"),
            "1024",
        )
        require_equal(
            f"{profile} trigger position",
            report.get(f"PROFILE.{profile}.TRIGGER_POSITION"),
            "512",
        )
    return [
        "PAIR_PROGRAM_READBACK=PASS",
        "ILA_CELL=base_soc_i/ila_reference_0",
        "ILA_DATA_DEPTH=1024",
        "ILA_TRIGGER_POSITION=512",
    ]


def validate_no_trigger(results_dir: Path) -> list[str]:
    report = read_report(results_dir / "no_trigger_100ms.rpt")
    require_equal(
        "no-trigger result", report.get("RESULT"), "PASS_NO_TRIGGER_100MS"
    )
    required_ms = int(report.get("REQUIRED_DURATION_MS", "0"))
    observed_ms = int(report.get("OBSERVED_DURATION_MS", "0"))
    if observed_ms < required_ms or required_ms < 100:
        fail(
            "no-trigger duration: "
            f"observed={observed_ms}, required={required_ms}"
        )
    if "WAITING_FOR_TRIGGER" not in report.get("CORE_STATUS", ""):
        fail(f"no-trigger core status: {report.get('CORE_STATUS')!r}")
    require_equal(
        "no-trigger partial capture", report.get("PARTIAL_CAPTURE_SAVED"), "0"
    )
    require_equal(
        "no-trigger upload attempt", report.get("PARTIAL_UPLOAD_ATTEMPTED"), "0"
    )
    for name in ("no_trigger.ila", "no_trigger_raw.csv"):
        if (results_dir / name).exists():
            fail(f"unexpected no-trigger partial artifact: {name}")
    return [
        f"NO_TRIGGER_REQUIRED_MS={required_ms}",
        f"NO_TRIGGER_OBSERVED_MS={observed_ms}",
        "NO_TRIGGER_CORE_STATUS=WAITING_FOR_TRIGGER",
        "NO_TRIGGER_PARTIAL_CAPTURE=0",
        "NO_TRIGGER_RESULT=PASS",
    ]


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    default_results = script_dir.parent / "results" / "step6"
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", type=Path, default=default_results)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    results_dir = args.results_dir.resolve()
    output = (
        args.output.resolve()
        if args.output is not None
        else results_dir / "capture_validation.rpt"
    )

    lines = [
        "# EdgeScope-Lite Step 6 capture validation",
        "STEP=6",
        "OVERALL=PASS",
        *validate_pair(results_dir),
    ]
    for profile in PROFILE_EXPECTATIONS:
        lines.extend(validate_profile(results_dir, profile))
    lines.extend(validate_no_trigger(results_dir))
    lines.append("STEP6_CAPTURE_VALIDATION=PASS")

    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"STEP6_CAPTURE_VALIDATION: PASS: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
