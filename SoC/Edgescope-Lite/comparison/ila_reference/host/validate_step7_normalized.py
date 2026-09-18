#!/usr/bin/env python3
"""Independently validate Step-7 normalized ILA comparison data."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
from pathlib import Path


PROFILES = {
    "rising": (0x00, 0x01),
    "falling": (0x01, 0x00),
    "pattern": (0x95, 0xA5),
}
PROFILE_METADATA = {
    "rising": ("1", "CH0_RISING_EDGE", "eq8'bXXXXXXXR"),
    "falling": ("2", "CH0_FALLING_EDGE", "eq8'bXXXXXXXF"),
    "pattern": ("3", "MASKED_PATTERN_VALUE_A0_MASK_F0", "eq8'b1010XXXX"),
}
GENERATOR_RTL_SHA256 = (
    "9f0a1b7f9a54ddc8f9eb3e093382af9eb6a6cdf8c9ab48ab4ce65d83e7eb5440"
)
GENERATOR_ADAPTER_SHA256 = (
    "73fd657010c8109d5a1c7e5168d4ae4a4d576fc80e2ddd02978b087523249580"
)
NORMALIZED_COLUMNS = (
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
RAW_PREFIX = ("Sample in Buffer", "Sample in Window", "TRIGGER")
UPPER_HEX_BYTE = re.compile(r"^[0-9A-F]{2}$")


def fail(message: str) -> None:
    raise SystemExit(f"STEP7_VALIDATE: FAIL: {message}")


def require_equal(label: str, actual: object, expected: object) -> None:
    if actual != expected:
        fail(f"{label}: actual={actual!r}, expected={expected!r}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_report(path: Path) -> dict[str, str]:
    if not path.is_file():
        fail(f"missing report: {path}")
    result: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in result:
            fail(f"{path.name}: duplicate key {key!r}")
        result[key] = value
    return result


def write_atomic(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    temporary.replace(path)


def display_path(path: Path, base: Path) -> str:
    return Path(os.path.relpath(path, base)).as_posix()


def parse_raw(path: Path, profile: str) -> list[tuple[int, int]]:
    if not path.is_file():
        fail(f"{profile}: missing raw CSV: {path}")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fieldnames = tuple(reader.fieldnames or ())
        require_equal(f"{profile} raw column count", len(fieldnames), 4)
        require_equal(f"{profile} raw prefix", fieldnames[:3], RAW_PREFIX)
        if not fieldnames[3].endswith("probe_test_o[7:0]"):
            fail(f"{profile}: unexpected raw probe column {fieldnames[3]!r}")
        rows = list(reader)

    require_equal(f"{profile} raw rows including radix", len(rows), 1025)
    radix = rows[0]
    require_equal(
        f"{profile} raw radix",
        tuple(radix[name].strip() for name in fieldnames),
        ("Radix - UNSIGNED", "UNSIGNED", "UNSIGNED", "HEX"),
    )

    result: list[tuple[int, int]] = []
    for expected_index, row in enumerate(rows[1:]):
        if None in row or any(row.get(name) is None for name in fieldnames):
            fail(f"{profile}: malformed raw column count at {expected_index}")
        try:
            sample_index = int(row[fieldnames[0]], 10)
            window_index = int(row[fieldnames[1]], 10)
            trigger = int(row[fieldnames[2]], 10)
            value = int(row[fieldnames[3]], 16)
        except ValueError as error:
            fail(f"{profile}: invalid raw row {expected_index}: {error}")
        require_equal(f"{profile} raw sample index", sample_index, expected_index)
        require_equal(
            f"{profile} raw window index {expected_index}",
            window_index,
            expected_index,
        )
        if trigger not in (0, 1) or not 0 <= value <= 0xFF:
            fail(
                f"{profile}: invalid raw trigger/value at {expected_index}: "
                f"{trigger}/{value}"
            )
        result.append((value, trigger))
    return result


def parse_normalized(path: Path, profile: str) -> list[tuple[int, int]]:
    if not path.is_file():
        fail(f"{profile}: missing normalized CSV: {path}")
    raw_text = path.read_bytes()
    if b"\r" in raw_text:
        fail(f"{profile}: normalized CSV is not canonical LF text")

    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        require_equal(
            f"{profile} normalized schema",
            tuple(reader.fieldnames or ()),
            NORMALIZED_COLUMNS,
        )
        rows = list(reader)

    require_equal(f"{profile} normalized sample count", len(rows), 1024)
    result: list[tuple[int, int]] = []
    for expected_index, row in enumerate(rows):
        if None in row or any(
            row.get(name) is None for name in NORMALIZED_COLUMNS
        ):
            fail(
                f"{profile}: malformed normalized column count at "
                f"index {expected_index}"
            )
        require_equal(
            f"{profile} canonical index {expected_index}",
            row["index"],
            str(expected_index),
        )
        value_text = row["value_hex"]
        if not UPPER_HEX_BYTE.fullmatch(value_text):
            fail(
                f"{profile}: noncanonical value_hex at {expected_index}: "
                f"{value_text!r}"
            )
        value = int(value_text, 16)
        trigger_text = row["is_trigger"]
        if trigger_text not in ("0", "1"):
            fail(
                f"{profile}: invalid is_trigger at {expected_index}: "
                f"{trigger_text!r}"
            )
        trigger = int(trigger_text)

        expected_bits = tuple(
            str((value >> bit) & 1) for bit in range(7, -1, -1)
        )
        actual_bits = tuple(row[f"ch{bit}"] for bit in range(7, -1, -1))
        require_equal(
            f"{profile} channel bits at {expected_index}",
            actual_bits,
            expected_bits,
        )
        result.append((value, trigger))

    trigger_indices = [
        index for index, (_, trigger) in enumerate(result) if trigger == 1
    ]
    require_equal(f"{profile} normalized trigger indices", trigger_indices, [512])

    before, after = PROFILES[profile]
    require_equal(
        f"{profile} pre-trigger half",
        {value for value, _ in result[:512]},
        {before},
    )
    require_equal(
        f"{profile} trigger/post half",
        {value for value, _ in result[512:]},
        {after},
    )
    return result


def validate_profile(
    source_dir: Path,
    output_dir: Path,
    manifest: dict[str, str],
    profile: str,
) -> list[str]:
    source_path = source_dir / f"{profile}_raw.csv"
    output_path = output_dir / f"{profile}_normalized.csv"
    raw_rows = parse_raw(source_path, profile)
    normalized_rows = parse_normalized(output_path, profile)
    require_equal(f"{profile} lossless round trip", normalized_rows, raw_rows)

    prefix = f"PROFILE.{profile}"
    before, after = PROFILES[profile]
    test_id, trigger_config, ila_compare = PROFILE_METADATA[profile]
    capture_report = read_report(source_dir / f"capture_{profile}.rpt")
    expected_manifest = {
        f"{prefix}.RESULT": "PASS",
        f"{prefix}.TEST_ID": test_id,
        f"{prefix}.TRIGGER_CONFIG": trigger_config,
        f"{prefix}.ILA_COMPARE": ila_compare,
        f"{prefix}.SOURCE": display_path(source_path, output_dir),
        f"{prefix}.SOURCE_SHA256": sha256(source_path),
        f"{prefix}.ILA_SOURCE": f"../step6/{profile}.ila",
        f"{prefix}.ILA_SHA256": capture_report.get("ILA_FILE_SHA256"),
        f"{prefix}.OUTPUT": output_path.name,
        f"{prefix}.OUTPUT_SHA256": sha256(output_path),
        f"{prefix}.SAMPLE_COUNT": "1024",
        f"{prefix}.TRIGGER_COUNT": "1",
        f"{prefix}.TRIGGER_INDEX": "512",
        f"{prefix}.SAMPLE_511": f"0x{before:02X}",
        f"{prefix}.SAMPLE_512": f"0x{after:02X}",
    }
    for key, value in expected_manifest.items():
        require_equal(f"{profile} manifest {key}", manifest.get(key), value)

    return [
        f"{prefix}.RESULT=PASS",
        f"{prefix}.ROW_COUNT=1024",
        f"{prefix}.TRIGGER_COUNT=1",
        f"{prefix}.TRIGGER_INDEX=512",
        f"{prefix}.SAMPLE_511=0x{before:02X}",
        f"{prefix}.SAMPLE_512=0x{after:02X}",
        f"{prefix}.BIT_COLUMNS=PASS",
        f"{prefix}.RAW_ROUND_TRIP=PASS",
        f"{prefix}.OUTPUT_SHA256={sha256(output_path)}",
    ]


def validate_no_trigger(
    source_dir: Path,
    output_dir: Path,
    manifest: dict[str, str],
) -> list[str]:
    report = read_report(source_dir / "no_trigger_100ms.rpt")
    require_equal(
        "no-trigger result",
        report.get("RESULT"),
        "PASS_NO_TRIGGER_100MS",
    )
    required_ms = int(report.get("REQUIRED_DURATION_MS", "0"))
    observed_ms = int(report.get("OBSERVED_DURATION_MS", "0"))
    if required_ms < 100 or observed_ms < required_ms:
        fail(
            f"no-trigger duration: required={required_ms}, observed={observed_ms}"
        )
    require_equal(
        "no-trigger manifest result",
        manifest.get("PROFILE.no_trigger.RESULT"),
        "PASS_NO_TRIGGER_100MS",
    )
    require_equal(
        "no-trigger manifest test ID",
        manifest.get("PROFILE.no_trigger.TEST_ID"),
        "5",
    )
    require_equal(
        "no-trigger manifest comparator",
        manifest.get("PROFILE.no_trigger.ILA_COMPARE"),
        "eq8'hFF",
    )
    require_equal(
        "no-trigger manifest trigger count",
        manifest.get("PROFILE.no_trigger.TRIGGER_COUNT"),
        "0",
    )
    require_equal(
        "no-trigger manifest CSV",
        manifest.get("PROFILE.no_trigger.NORMALIZED_CSV"),
        "NOT_APPLICABLE_NO_COMPLETE_CAPTURE",
    )
    for name in (
        "no_trigger_normalized.csv",
        "no_trigger.ila",
        "no_trigger_raw.csv",
    ):
        if (output_dir / name).exists():
            fail(f"unexpected Step-7 no-trigger artifact: {name}")
    require_equal(
        "P-04 separate capture status",
        manifest.get("P04_PATTERN_HOLD"),
        "NOT_RUN_SEPARATE_CAPTURE_REQUIRED",
    )
    return [
        "PROFILE.no_trigger.RESULT=PASS_NO_TRIGGER_100MS",
        f"PROFILE.no_trigger.REQUIRED_MS={required_ms}",
        f"PROFILE.no_trigger.OBSERVED_MS={observed_ms}",
        "PROFILE.no_trigger.NORMALIZED_CSV=NOT_APPLICABLE_NO_COMPLETE_CAPTURE",
        "PROFILE.no_trigger.PARTIAL_CAPTURE=0",
    ]


def main() -> int:
    reference_dir = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(
        description="Validate official Step-7 normalized comparison CSVs."
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=reference_dir / "results" / "step6",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=reference_dir / "results" / "step7",
    )
    args = parser.parse_args()

    source_dir = args.source_dir.resolve()
    output_dir = args.output_dir.resolve()
    step6_validation = read_report(source_dir / "capture_validation.rpt")
    require_equal(
        "Step-6 capture validation",
        step6_validation.get("STEP6_CAPTURE_VALIDATION"),
        "PASS",
    )
    step6_status = read_report(source_dir / "step6_status.rpt")
    require_equal("Step-6 status", step6_status.get("OVERALL"), "PASS")
    pair = read_report(source_dir / "pair_readback.rpt")
    require_equal("Step-6 pair result", pair.get("RESULT"), "PASS")
    manifest = read_report(output_dir / "normalization_manifest.rpt")

    global_expected = {
        "STEP": "7",
        "OVERALL": "PASS",
        "SCHEMA_VERSION": "EDGESCOPE_NORMALIZED_CSV_V1",
        "METHOD": "VIVADO_ILA",
        "SOURCE_KIND": "100MHZ_HARDWARE_SAMPLE",
        "SOURCE_FORMAT": "VIVADO_ILA_CSV",
        "NORMALIZED_SCHEMA": ",".join(NORMALIZED_COLUMNS),
        "LOGICAL_ORDER": "OLDEST_TO_NEWEST",
        "LOGICAL_INDEX_FIRST": "0",
        "LOGICAL_INDEX_LAST": "1023",
        "SAMPLE_COUNT": "1024",
        "PRE_TRIGGER_SAMPLES": "512",
        "POST_TRIGGER_INCLUDING_TRIGGER_SAMPLES": "512",
        "TRIGGER_INDEX": "512",
        "VALUE_WIDTH_BITS": "8",
        "VALUE_HEX_FORMAT": "UPPERCASE_TWO_DIGITS_NO_PREFIX",
        "ILA_CLOCK_HZ": "100000000",
        "ILA_SAMPLE_PERIOD_NS": "10",
        "NORMALIZED_TIME_AXIS": "LOGICAL_INDEX_ONLY",
        "TIME_COLUMN": "NOT_INCLUDED_BY_COMMON_CONTRACT",
        "TRANSPORT_THROUGHPUT_COMPARISON": "OUT_OF_SCOPE",
        "GENERATOR_RTL_SHA256": GENERATOR_RTL_SHA256,
        "GENERATOR_ADAPTER_SHA256": GENERATOR_ADAPTER_SHA256,
        "RUNTIME_BIT_SHA256": pair.get("bit_sha256"),
        "LTX_SHA256": pair.get("ltx_sha256"),
        "PATTERN_TRIGGER_EQUIVALENCE": (
            "FROZEN_NONMATCH_TO_MATCH_WAVEFORM_ONLY"
        ),
        "STEP7_NORMALIZATION": "PASS",
    }
    for key, value in global_expected.items():
        require_equal(f"manifest {key}", manifest.get(key), value)

    validation_lines = [
        "# EdgeScope-Lite Vivado ILA Reference - Step 7 validation",
        "STEP=7",
        "OVERALL=PASS",
        "STEP6_CAPTURE_VALIDATION=PASS",
        "SCHEMA_VERSION=EDGESCOPE_NORMALIZED_CSV_V1",
        "METHOD=VIVADO_ILA",
        "SOURCE_KIND=100MHZ_HARDWARE_SAMPLE",
        f"NORMALIZED_SCHEMA={','.join(NORMALIZED_COLUMNS)}",
        f"NORMALIZED_COLUMN_COUNT={len(NORMALIZED_COLUMNS)}",
        "LOGICAL_ORDER=OLDEST_TO_NEWEST",
        "SAMPLE_COUNT=1024",
        "PRE_TRIGGER_SAMPLES=512",
        "POST_TRIGGER_INCLUDING_TRIGGER_SAMPLES=512",
        "TRIGGER_INDEX=512",
        "VALUE_WIDTH_BITS=8",
        "ILA_CLOCK_HZ=100000000",
        "ILA_SAMPLE_PERIOD_NS=10",
        "TIME_COLUMN=NOT_INCLUDED_BY_COMMON_CONTRACT",
        "TRANSPORT_THROUGHPUT_COMPARISON=OUT_OF_SCOPE",
    ]
    for profile in PROFILES:
        validation_lines.extend(
            validate_profile(source_dir, output_dir, manifest, profile)
        )
    validation_lines.extend(
        validate_no_trigger(source_dir, output_dir, manifest)
    )
    validation_lines.extend(
        [
            "PATTERN_TRIGGER_EQUIVALENCE=FROZEN_NONMATCH_TO_MATCH_WAVEFORM_ONLY",
            "P04_PATTERN_HOLD=NOT_RUN_SEPARATE_CAPTURE_REQUIRED",
        ]
    )
    validation_lines.append("STEP7_VALIDATION=PASS")

    validation_path = output_dir / "normalization_validation.rpt"
    write_atomic(validation_path, validation_lines)

    status_lines = [
        "# EdgeScope-Lite Vivado ILA Reference - Step 7 Current Status",
        "STEP=7",
        "OVERALL=PASS",
        "STEP6_SOURCE_VALIDATION=PASS",
        "NORMALIZATION_MANIFEST=PASS",
        "NORMALIZATION_VALIDATION=PASS",
        "SCHEMA_VERSION=EDGESCOPE_NORMALIZED_CSV_V1",
        f"COMMON_SCHEMA={','.join(NORMALIZED_COLUMNS)}",
        f"COMMON_SCHEMA_COLUMN_COUNT={len(NORMALIZED_COLUMNS)}",
        "LOGICAL_ORDER=OLDEST_TO_NEWEST",
        "SAMPLE_COUNT=1024",
        "TRIGGER_INDEX=512",
        "RISING_NORMALIZATION=PASS",
        "FALLING_NORMALIZATION=PASS",
        "PATTERN_NORMALIZATION=PASS",
        "NO_TRIGGER_NORMALIZATION=NOT_APPLICABLE_NO_COMPLETE_CAPTURE",
        "NO_TRIGGER_EVIDENCE=PASS_NO_TRIGGER_100MS",
        "P04_PATTERN_HOLD=NOT_RUN_SEPARATE_CAPTURE_REQUIRED",
        "NEXT_ACTION=STEP8_PULSE_STRESS",
    ]
    status_path = output_dir / "step7_status.rpt"
    write_atomic(status_path, status_lines)

    print(f"STEP7_VALIDATE: PASS: {validation_path}")
    print(f"STEP7_STATUS: PASS: {status_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
