#!/usr/bin/env python3
"""Convert fixed Vivado ILA exports to the common comparison CSV schema."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import os
import re
from dataclasses import dataclass
from pathlib import Path


PROFILES = {
    "rising": (0x00, 0x01),
    "falling": (0x01, 0x00),
    "pattern": (0x95, 0xA5),
}
PROFILE_METADATA = {
    "rising": {
        "test_id": "1",
        "trigger_config": "CH0_RISING_EDGE",
        "ila_compare": "eq8'bXXXXXXXR",
    },
    "falling": {
        "test_id": "2",
        "trigger_config": "CH0_FALLING_EDGE",
        "ila_compare": "eq8'bXXXXXXXF",
    },
    "pattern": {
        "test_id": "3",
        "trigger_config": "MASKED_PATTERN_VALUE_A0_MASK_F0",
        "ila_compare": "eq8'b1010XXXX",
    },
}
GENERATOR_RTL_SHA256 = (
    "9f0a1b7f9a54ddc8f9eb3e093382af9eb6a6cdf8c9ab48ab4ce65d83e7eb5440"
)
GENERATOR_ADAPTER_SHA256 = (
    "73fd657010c8109d5a1c7e5168d4ae4a4d576fc80e2ddd02978b087523249580"
)
RAW_PREFIX = ("Sample in Buffer", "Sample in Window", "TRIGGER")
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
HEX_BYTE = re.compile(r"^[0-9A-Fa-f]{1,2}$")


@dataclass(frozen=True)
class Sample:
    index: int
    is_trigger: int
    value: int


def fail(message: str) -> None:
    raise SystemExit(f"STEP7_NORMALIZE: FAIL: {message}")


def require_equal(label: str, actual: object, expected: object) -> None:
    if actual != expected:
        fail(f"{label}: actual={actual!r}, expected={expected!r}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def read_report(path: Path) -> dict[str, str]:
    if not path.is_file():
        fail(f"missing report: {path}")
    fields: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in fields:
            fail(f"{path.name}: duplicate report key {key!r}")
        fields[key] = value
    return fields


def read_checksum_index(path: Path) -> dict[str, str]:
    if not path.is_file():
        fail(f"missing checksum index: {path}")
    result: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if not raw_line.strip():
            continue
        parts = raw_line.split(maxsplit=1)
        if len(parts) != 2 or not re.fullmatch(r"[0-9a-f]{64}", parts[0]):
            fail(f"{path.name}: malformed checksum line {raw_line!r}")
        name = parts[1].lstrip("*")
        if name in result:
            fail(f"{path.name}: duplicate checksum entry {name!r}")
        result[name] = parts[0]
    return result


def parse_vivado_csv(path: Path, profile: str) -> list[Sample]:
    if not path.is_file():
        fail(f"{profile}: missing Vivado CSV: {path}")

    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        fieldnames = tuple(reader.fieldnames or ())
        require_equal(f"{profile} raw column count", len(fieldnames), 4)
        require_equal(f"{profile} raw prefix", fieldnames[:3], RAW_PREFIX)
        if not fieldnames[3].endswith("probe_test_o[7:0]"):
            fail(f"{profile}: unexpected raw probe column {fieldnames[3]!r}")

        sample_key, window_key, trigger_key, value_key = fieldnames
        rows = list(reader)

    require_equal(f"{profile} raw row count including radix", len(rows), 1025)
    radix = rows[0]
    require_equal(
        f"{profile} radix sample",
        radix[sample_key].strip(),
        "Radix - UNSIGNED",
    )
    require_equal(
        f"{profile} radix window", radix[window_key].strip(), "UNSIGNED"
    )
    require_equal(
        f"{profile} radix trigger", radix[trigger_key].strip(), "UNSIGNED"
    )
    require_equal(f"{profile} radix value", radix[value_key].strip(), "HEX")

    samples: list[Sample] = []
    for expected_index, row in enumerate(rows[1:]):
        if None in row or any(row.get(name) is None for name in fieldnames):
            fail(f"{profile}: malformed raw column count at index {expected_index}")
        try:
            index = int(row[sample_key], 10)
            window = int(row[window_key], 10)
            is_trigger = int(row[trigger_key], 10)
        except ValueError as error:
            fail(f"{profile}: invalid numeric field at row {expected_index}: {error}")
        value_text = row[value_key].strip()
        if not HEX_BYTE.fullmatch(value_text):
            fail(
                f"{profile}: value at index {expected_index} is not "
                f"two-digit hexadecimal: {value_text!r}"
            )
        value = int(value_text, 16)

        require_equal(f"{profile} logical index", index, expected_index)
        require_equal(f"{profile} window index {index}", window, index)
        if is_trigger not in (0, 1):
            fail(f"{profile}: trigger marker at index {index} is {is_trigger}")
        samples.append(Sample(index, is_trigger, value))

    require_equal(f"{profile} sample count", len(samples), 1024)
    trigger_indices = [
        sample.index for sample in samples if sample.is_trigger == 1
    ]
    require_equal(f"{profile} trigger indices", trigger_indices, [512])
    expected_before, expected_trigger = PROFILES[profile]
    require_equal(f"{profile} sample 511", samples[511].value, expected_before)
    require_equal(f"{profile} sample 512", samples[512].value, expected_trigger)
    return samples


def validate_step6_source(
    source_dir: Path, profile: str, csv_path: Path
) -> dict[str, str]:
    report = read_report(source_dir / f"capture_{profile}.rpt")
    require_equal(f"{profile} source profile", report.get("PROFILE"), profile)
    require_equal(
        f"{profile} source result", report.get("RESULT"), "CAPTURE_COMPLETE"
    )
    require_equal(
        f"{profile} source partial capture",
        report.get("PARTIAL_CAPTURE"),
        "0",
    )
    require_equal(
        f"{profile} source CSV hash",
        sha256(csv_path),
        report.get("RAW_CSV_SHA256"),
    )
    ila_path = source_dir / f"{profile}.ila"
    if not ila_path.is_file() or ila_path.stat().st_size == 0:
        fail(f"{profile}: missing or empty ILA capture: {ila_path}")
    require_equal(
        f"{profile} source ILA hash",
        sha256(ila_path),
        report.get("ILA_FILE_SHA256"),
    )
    return report


def validate_no_trigger(source_dir: Path) -> dict[str, str]:
    report = read_report(source_dir / "no_trigger_100ms.rpt")
    require_equal(
        "no-trigger source result",
        report.get("RESULT"),
        "PASS_NO_TRIGGER_100MS",
    )
    required_ms = int(report.get("REQUIRED_DURATION_MS", "0"))
    observed_ms = int(report.get("OBSERVED_DURATION_MS", "0"))
    if required_ms < 100 or observed_ms < required_ms:
        fail(
            "no-trigger source duration: "
            f"required={required_ms}, observed={observed_ms}"
        )
    if "WAITING_FOR_TRIGGER" not in report.get("CORE_STATUS", ""):
        fail(f"no-trigger source core status: {report.get('CORE_STATUS')!r}")
    require_equal(
        "no-trigger source partial capture",
        report.get("PARTIAL_CAPTURE_SAVED"),
        "0",
    )
    require_equal(
        "no-trigger source upload attempt",
        report.get("PARTIAL_UPLOAD_ATTEMPTED"),
        "0",
    )
    for name in ("no_trigger.ila", "no_trigger_raw.csv"):
        if (source_dir / name).exists():
            fail(f"unexpected no-trigger capture artifact: {name}")
    return report


def normalized_csv_text(samples: list[Sample]) -> str:
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(NORMALIZED_COLUMNS)
    for sample in samples:
        bits = [(sample.value >> bit) & 1 for bit in range(7, -1, -1)]
        writer.writerow(
            (
                sample.index,
                f"{sample.value:02X}",
                sample.is_trigger,
                *bits,
            )
        )
    return output.getvalue()


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def display_path(path: Path, base: Path) -> str:
    return Path(os.path.relpath(path, base)).as_posix()


def main() -> int:
    reference_dir = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(
        description="Normalize the official Step-6 ILA captures."
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
    step6_status = read_report(source_dir / "step6_status.rpt")
    require_equal("Step-6 status", step6_status.get("OVERALL"), "PASS")
    step6_validation = read_report(source_dir / "capture_validation.rpt")
    require_equal(
        "Step-6 validation", step6_validation.get("OVERALL"), "PASS"
    )
    pair = read_report(source_dir / "pair_readback.rpt")
    require_equal("Step-6 pair result", pair.get("RESULT"), "PASS")
    require_equal("Step-6 probe width", pair.get("probe_width"), "8")
    for profile in (*PROFILES, "no_trigger"):
        require_equal(
            f"Step-6 {profile} pair result",
            pair.get(f"PROFILE.{profile}.RESULT"),
            "PASS",
        )
        require_equal(
            f"Step-6 {profile} pair depth",
            pair.get(f"PROFILE.{profile}.DATA_DEPTH"),
            "1024",
        )
        require_equal(
            f"Step-6 {profile} pair trigger position",
            pair.get(f"PROFILE.{profile}.TRIGGER_POSITION"),
            "512",
        )

    checksum_index = read_checksum_index(source_dir / "SHA256SUMS")
    generator_rtl = reference_dir.parent / "common" / "rtl" / "test_pattern_generator.sv"
    generator_adapter = (
        reference_dir.parent
        / "common"
        / "rtl"
        / "test_pattern_generator_gpio_adapter.v"
    )
    require_equal(
        "Generator RTL hash", sha256(generator_rtl), GENERATOR_RTL_SHA256
    )
    require_equal(
        "Generator adapter hash",
        sha256(generator_adapter),
        GENERATOR_ADAPTER_SHA256,
    )
    no_trigger = validate_no_trigger(source_dir)

    manifest = [
        "# EdgeScope-Lite Vivado ILA Reference - Step 7 normalization manifest",
        "STEP=7",
        "OVERALL=PASS",
        "SCHEMA_VERSION=EDGESCOPE_NORMALIZED_CSV_V1",
        "METHOD=VIVADO_ILA",
        "SOURCE_KIND=100MHZ_HARDWARE_SAMPLE",
        "SOURCE_FORMAT=VIVADO_ILA_CSV",
        f"NORMALIZED_SCHEMA={','.join(NORMALIZED_COLUMNS)}",
        "LOGICAL_ORDER=OLDEST_TO_NEWEST",
        "LOGICAL_INDEX_FIRST=0",
        "LOGICAL_INDEX_LAST=1023",
        "SAMPLE_COUNT=1024",
        "PRE_TRIGGER_SAMPLES=512",
        "POST_TRIGGER_INCLUDING_TRIGGER_SAMPLES=512",
        "TRIGGER_INDEX=512",
        "VALUE_WIDTH_BITS=8",
        "VALUE_HEX_FORMAT=UPPERCASE_TWO_DIGITS_NO_PREFIX",
        "ILA_CLOCK_HZ=100000000",
        "ILA_SAMPLE_PERIOD_NS=10",
        "NORMALIZED_TIME_AXIS=LOGICAL_INDEX_ONLY",
        "TIME_COLUMN=NOT_INCLUDED_BY_COMMON_CONTRACT",
        "TRANSPORT_THROUGHPUT_COMPARISON=OUT_OF_SCOPE",
        f"GENERATOR_RTL_SHA256={GENERATOR_RTL_SHA256}",
        f"GENERATOR_ADAPTER_SHA256={GENERATOR_ADAPTER_SHA256}",
        f"RUNTIME_BIT_SHA256={pair['bit_sha256']}",
        f"LTX_SHA256={pair['ltx_sha256']}",
        "PATTERN_TRIGGER_EQUIVALENCE=FROZEN_NONMATCH_TO_MATCH_WAVEFORM_ONLY",
    ]

    # Validate every official input and build every output in memory before
    # replacing any existing Step-7 file.
    prepared: dict[str, tuple[Path, Path, str, dict[str, str]]] = {}
    for profile, (expected_before, expected_trigger) in PROFILES.items():
        source_path = source_dir / f"{profile}_raw.csv"
        source_report = validate_step6_source(source_dir, profile, source_path)
        require_equal(
            f"{profile} Step-6 checksum index",
            checksum_index.get(source_path.name),
            sha256(source_path),
        )
        samples = parse_vivado_csv(source_path, profile)
        output_path = output_dir / f"{profile}_normalized.csv"
        output_text = normalized_csv_text(samples)
        prepared[profile] = (
            source_path,
            output_path,
            output_text,
            source_report,
        )

    if (output_dir / "no_trigger_normalized.csv").exists():
        fail("unexpected existing no_trigger_normalized.csv")

    output_dir.mkdir(parents=True, exist_ok=True)
    for profile, (expected_before, expected_trigger) in PROFILES.items():
        source_path, output_path, output_text, source_report = prepared[profile]
        write_atomic(output_path, output_text)
        metadata = PROFILE_METADATA[profile]
        prefix = f"PROFILE.{profile}"
        manifest.extend(
            [
                f"{prefix}.RESULT=PASS",
                f"{prefix}.TEST_ID={metadata['test_id']}",
                f"{prefix}.TRIGGER_CONFIG={metadata['trigger_config']}",
                f"{prefix}.ILA_COMPARE={metadata['ila_compare']}",
                f"{prefix}.SOURCE={display_path(source_path, output_dir)}",
                f"{prefix}.SOURCE_SHA256={sha256(source_path)}",
                f"{prefix}.ILA_SOURCE=../step6/{profile}.ila",
                f"{prefix}.ILA_SHA256={source_report['ILA_FILE_SHA256']}",
                f"{prefix}.OUTPUT={output_path.name}",
                f"{prefix}.OUTPUT_SHA256={sha256_text(output_text)}",
                f"{prefix}.SAMPLE_COUNT=1024",
                f"{prefix}.TRIGGER_COUNT=1",
                f"{prefix}.TRIGGER_INDEX=512",
                f"{prefix}.SAMPLE_511=0x{expected_before:02X}",
                f"{prefix}.SAMPLE_512=0x{expected_trigger:02X}",
            ]
        )
        print(
            f"NORMALIZED: {profile}: {source_path.name} -> "
            f"{output_path.name}: 1024 samples"
        )

    manifest.extend(
        [
            "PROFILE.no_trigger.RESULT=PASS_NO_TRIGGER_100MS",
            "PROFILE.no_trigger.TEST_ID=5",
            "PROFILE.no_trigger.TRIGGER_CONFIG=IMPOSSIBLE_EQ_FF",
            "PROFILE.no_trigger.ILA_COMPARE=eq8'hFF",
            "PROFILE.no_trigger.TRIGGER_COUNT=0",
            "PROFILE.no_trigger.NORMALIZED_CSV=NOT_APPLICABLE_NO_COMPLETE_CAPTURE",
            f"PROFILE.no_trigger.REQUIRED_MS={no_trigger['REQUIRED_DURATION_MS']}",
            f"PROFILE.no_trigger.OBSERVED_MS={no_trigger['OBSERVED_DURATION_MS']}",
            f"PROFILE.no_trigger.CORE_STATUS={no_trigger['CORE_STATUS']}",
            "PROFILE.no_trigger.PARTIAL_CAPTURE=0",
            "P04_PATTERN_HOLD=NOT_RUN_SEPARATE_CAPTURE_REQUIRED",
            "STEP7_NORMALIZATION=PASS",
        ]
    )
    manifest_path = output_dir / "normalization_manifest.rpt"
    write_atomic(manifest_path, "\n".join(manifest) + "\n")
    print(f"STEP7_NORMALIZE: PASS: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
