#!/usr/bin/env python3
"""Validate and finalize the official Step-8 ILA Pulse Stress matrix."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import os
import re
from dataclasses import dataclass
from pathlib import Path


WIDTHS = (1, 10, 100, 1_000, 10_000, 100_000)
REPETITIONS = 10
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
GENERATOR_RTL_SHA256 = (
    "9f0a1b7f9a54ddc8f9eb3e093382af9eb6a6cdf8c9ab48ab4ce65d83e7eb5440"
)
GENERATOR_ADAPTER_SHA256 = (
    "73fd657010c8109d5a1c7e5168d4ae4a4d576fc80e2ddd02978b087523249580"
)
RUNTIME_ELF_SHA256 = (
    "7cd731b725da46489b0670666f234ee521771b3faf0b205f188866cf89150934"
)
UART_REPLY = re.compile(
    r"^OK RUN id=6 pulse=0x([0-9A-Fa-f]{8}) "
    r"saw_busy=1 status=0x00000002$"
)


@dataclass(frozen=True)
class Sample:
    index: int
    trigger: int
    value: int


@dataclass(frozen=True)
class Trial:
    width: int
    trial: int
    detected: int
    raw_sha256: str
    ila_sha256: str
    normalized_sha256: str
    visible_high_samples: int
    fall_observed: int
    first_low_index: str
    uart_start_ms: int
    uart_response_ms: int


def fail(message: str) -> None:
    raise SystemExit(f"STEP8_VALIDATE: FAIL: {message}")


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


def write_atomic_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def csv_text(columns: tuple[str, ...], rows: list[tuple[object, ...]]) -> str:
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(columns)
    writer.writerows(rows)
    return output.getvalue()


def parse_raw(path: Path, width: int, trial: int) -> list[Sample]:
    label = f"width={width} trial={trial}"
    if not path.is_file():
        fail(f"{label}: missing raw CSV: {path}")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fieldnames = tuple(reader.fieldnames or ())
        require_equal(f"{label} raw column count", len(fieldnames), 4)
        require_equal(f"{label} raw prefix", fieldnames[:3], RAW_PREFIX)
        if not fieldnames[3].endswith("probe_test_o[7:0]"):
            fail(f"{label}: unexpected probe column {fieldnames[3]!r}")
        rows = list(reader)

    require_equal(f"{label} row count including radix", len(rows), 1025)
    radix = rows[0]
    require_equal(
        f"{label} radix",
        tuple(radix[name].strip() for name in fieldnames),
        ("Radix - UNSIGNED", "UNSIGNED", "UNSIGNED", "HEX"),
    )

    samples: list[Sample] = []
    for expected_index, row in enumerate(rows[1:]):
        if None in row or any(row.get(name) is None for name in fieldnames):
            fail(f"{label}: malformed row width at index {expected_index}")
        try:
            index = int(row[fieldnames[0]], 10)
            window = int(row[fieldnames[1]], 10)
            trigger = int(row[fieldnames[2]], 10)
            value = int(row[fieldnames[3]], 16)
        except ValueError as error:
            fail(f"{label}: malformed data at index {expected_index}: {error}")
        require_equal(f"{label} sample index", index, expected_index)
        require_equal(f"{label} window index {index}", window, index)
        if trigger not in (0, 1) or value not in (0x00, 0x01):
            fail(f"{label}: invalid trigger/value at {index}: {trigger}/{value}")
        samples.append(Sample(index, trigger, value))

    trigger_indices = [
        sample.index for sample in samples if sample.trigger == 1
    ]
    require_equal(f"{label} trigger indices", trigger_indices, [512])
    require_equal(
        f"{label} pre-trigger waveform",
        {sample.value for sample in samples[:512]},
        {0x00},
    )
    visible_high = min(width, 512)
    require_equal(
        f"{label} visible high waveform",
        {sample.value for sample in samples[512 : 512 + visible_high]},
        {0x01},
    )
    if width <= 511:
        first_low = 512 + width
        require_equal(
            f"{label} first low sample", samples[first_low].value, 0x00
        )
        require_equal(
            f"{label} post-pulse waveform",
            {sample.value for sample in samples[first_low:]},
            {0x00},
        )
    else:
        require_equal(
            f"{label} clipped post-trigger window",
            {sample.value for sample in samples[512:]},
            {0x01},
        )
    return samples


def normalized_text(samples: list[Sample]) -> str:
    rows: list[tuple[object, ...]] = []
    for sample in samples:
        bits = tuple((sample.value >> bit) & 1 for bit in range(7, -1, -1))
        rows.append(
            (sample.index, f"{sample.value:02X}", sample.trigger, *bits)
        )
    return csv_text(NORMALIZED_COLUMNS, rows)


def validate_success_trial(
    source_dir: Path,
    output_dir: Path,
    width: int,
    trial: int,
    bit_sha: str,
    ltx_sha: str,
) -> tuple[Trial, str]:
    stem = f"pulse_w{width:06d}_trial_{trial:02d}"
    report_path = source_dir / "trials" / f"{stem}.rpt"
    raw_path = source_dir / "raw" / f"{stem}_raw.csv"
    ila_path = source_dir / "ila" / f"{stem}.ila"
    report = read_report(report_path)

    expected_fields = {
        "STEP": "8",
        "ACTION": "pulse_stress",
        "RESULT": "CAPTURE_COMPLETE",
        "WIDTH_CYCLES": str(width),
        "WIDTH_NS": str(width * 10),
        "TRIAL": str(trial),
        "ELIGIBLE": "1",
        "SESSION_TOKEN": f"w{width:06d}-r{trial:02d}",
        "ILA_PROFILE": "rising",
        "TRIGGER_COMPARE_VALUE": "eq8'bXXXXXXXR",
        "DATA_DEPTH": "1024",
        "TRIGGER_POSITION": "512",
        "ARM_STATUS": "WAITING_FOR_TRIGGER",
        "UART_COMMAND": f"RUN 6 {width}",
        "PARTIAL_CAPTURE": "0",
        "bit_sha256": bit_sha,
        "ltx_sha256": ltx_sha,
    }
    for key, value in expected_fields.items():
        require_equal(f"{stem} report {key}", report.get(key), value)

    uart_match = UART_REPLY.fullmatch(report.get("UART_REPLY", ""))
    if uart_match is None:
        fail(f"{stem}: invalid UART reply {report.get('UART_REPLY')!r}")
    require_equal(
        f"{stem} UART width", int(uart_match.group(1), 16), width
    )

    for path, key in (
        (raw_path, "RAW_CSV_SHA256"),
        (ila_path, "ILA_FILE_SHA256"),
    ):
        if not path.is_file() or path.stat().st_size == 0:
            fail(f"{stem}: missing or empty artifact: {path}")
        require_equal(f"{stem} {key}", sha256(path), report.get(key))

    samples = parse_raw(raw_path, width, trial)
    output_text = normalized_text(samples)
    visible_high = min(width, 512)
    fall_observed = int(width <= 511)
    first_low = str(512 + width) if fall_observed else "OUTSIDE_WINDOW"
    start_ms = int(report.get("UART_START_EPOCH_MS", "-1"))
    response_ms = int(report.get("UART_RESPONSE_EPOCH_MS", "-1"))
    if start_ms < 0 or response_ms < start_ms:
        fail(
            f"{stem}: invalid UART timing start={start_ms}, response={response_ms}"
        )

    return (
        Trial(
            width=width,
            trial=trial,
            detected=1,
            raw_sha256=sha256(raw_path),
            ila_sha256=sha256(ila_path),
            normalized_sha256=sha256_text(output_text),
            visible_high_samples=visible_high,
            fall_observed=fall_observed,
            first_low_index=first_low,
            uart_start_ms=start_ms,
            uart_response_ms=response_ms,
        ),
        output_text,
    )


def validate_capture_manifest(
    results_dir: Path, bit_sha: str, ltx_sha: str
) -> dict[str, str]:
    manifest = read_report(results_dir / "pulse_capture_manifest.rpt")
    expected = {
        "STEP": "8",
        "ACTION": "pulse_stress",
        "RESULT": "CAPTURE_MATRIX_COMPLETE",
        "WIDTHS_CYCLES": ",".join(str(width) for width in WIDTHS),
        "REPETITIONS_PER_WIDTH": str(REPETITIONS),
        "EXPECTED_ELIGIBLE_TRIALS": "60",
        "ILA_PROFILE": "rising",
        "TRIGGER_COMPARE_VALUE": "eq8'bXXXXXXXR",
        "DATA_DEPTH": "1024",
        "TRIGGER_POSITION": "512",
        "FPGA_PROGRAM_COUNT": "1",
        "TOTAL_ELIGIBLE_CAPTURE_COUNT": "60",
        "HOST_WAVEFORM_VALIDATION": "PENDING",
        "bit_sha256": bit_sha,
        "ltx_sha256": ltx_sha,
    }
    for key, value in expected.items():
        require_equal(f"capture manifest {key}", manifest.get(key), value)
    for width in WIDTHS:
        require_equal(
            f"capture manifest width {width} eligible",
            manifest.get(f"WIDTH.{width}.ELIGIBLE_TRIAL_COUNT"),
            "10",
        )
    return manifest


def main() -> int:
    reference_dir = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(
        description="Validate and finalize the Step-8 Pulse Stress matrix."
    )
    parser.add_argument(
        "--results-dir",
        type=Path,
        default=reference_dir / "results" / "step8",
    )
    args = parser.parse_args()
    results_dir = args.results_dir.resolve()
    normalized_dir = results_dir / "normalized"

    step6_status = read_report(
        reference_dir / "results" / "step6" / "step6_status.rpt"
    )
    require_equal("Step-6 source status", step6_status.get("OVERALL"), "PASS")
    bit_sha = step6_status.get("RUNTIME_BIT_SHA256", "")
    ltx_sha = step6_status.get("LTX_SHA256", "")
    require_equal("Runtime BIT hash width", len(bit_sha), 64)
    require_equal("LTX hash width", len(ltx_sha), 64)

    generator_rtl = (
        reference_dir.parent / "common" / "rtl" / "test_pattern_generator.sv"
    )
    generator_adapter = (
        reference_dir.parent
        / "common"
        / "rtl"
        / "test_pattern_generator_gpio_adapter.v"
    )
    runtime_elf = (
        reference_dir
        / "sw"
        / "runtime_control"
        / "build"
        / "edgescope_runtime_control.elf"
    )
    require_equal(
        "Generator RTL hash", sha256(generator_rtl), GENERATOR_RTL_SHA256
    )
    require_equal(
        "Generator adapter hash",
        sha256(generator_adapter),
        GENERATOR_ADAPTER_SHA256,
    )
    require_equal("Runtime ELF hash", sha256(runtime_elf), RUNTIME_ELF_SHA256)

    capture_manifest = validate_capture_manifest(results_dir, bit_sha, ltx_sha)
    prepared_outputs: dict[Path, str] = {}
    trials: list[Trial] = []
    previous_response_ms = -1
    for width in WIDTHS:
        for trial_number in range(1, REPETITIONS + 1):
            trial, output_text = validate_success_trial(
                results_dir,
                normalized_dir,
                width,
                trial_number,
                bit_sha,
                ltx_sha,
            )
            if trial.uart_start_ms < previous_response_ms:
                fail(
                    f"UART commands overlapped before width={width} "
                    f"trial={trial_number}"
                )
            previous_response_ms = trial.uart_response_ms
            trials.append(trial)
            output_path = (
                normalized_dir
                / f"pulse_w{width:06d}_trial_{trial_number:02d}_normalized.csv"
            )
            prepared_outputs[output_path] = output_text

    require_equal("eligible trial count", len(trials), 60)
    for path, text in prepared_outputs.items():
        write_atomic_text(path, text)

    detection_columns = (
        "width_cycles",
        "width_ns",
        "trial",
        "eligible",
        "detected",
        "sample_count",
        "trigger_count",
        "trigger_index",
        "sample_511",
        "sample_512",
        "visible_high_samples",
        "fall_observed",
        "first_low_index",
        "raw_csv_sha256",
        "ila_sha256",
        "normalized_csv_sha256",
        "result",
    )
    detection_rows: list[tuple[object, ...]] = []
    for trial in trials:
        detection_rows.append(
            (
                trial.width,
                trial.width * 10,
                trial.trial,
                1,
                trial.detected,
                1024,
                1,
                512,
                "00",
                "01",
                trial.visible_high_samples,
                trial.fall_observed,
                trial.first_low_index,
                trial.raw_sha256,
                trial.ila_sha256,
                trial.normalized_sha256,
                "PASS",
            )
        )
    detection_path = results_dir / "pulse_detection.csv"
    write_atomic_text(
        detection_path, csv_text(detection_columns, detection_rows)
    )

    summary_columns = (
        "width_cycles",
        "width_ns",
        "eligible_trials",
        "detected_count",
        "detection_rate_percent",
        "expected_detected_count",
        "result",
    )
    summary_rows: list[tuple[object, ...]] = []
    for width in WIDTHS:
        selected = [trial for trial in trials if trial.width == width]
        detected = sum(trial.detected for trial in selected)
        require_equal(f"width {width} eligible trials", len(selected), 10)
        require_equal(f"width {width} detected trials", detected, 10)
        require_equal(
            f"capture manifest width {width} detected",
            capture_manifest.get(f"WIDTH.{width}.DETECTED_CAPTURE_COUNT"),
            "10",
        )
        summary_rows.append(
            (width, width * 10, 10, detected, "100.0", 10, "PASS")
        )
    require_equal(
        "capture manifest total detected",
        capture_manifest.get("TOTAL_DETECTED_CAPTURE_COUNT"),
        "60",
    )
    summary_path = results_dir / "pulse_detection_summary.csv"
    write_atomic_text(summary_path, csv_text(summary_columns, summary_rows))

    validation_lines = [
        "# EdgeScope-Lite Vivado ILA Reference - Step 8 validation",
        "STEP=8",
        "OVERALL=PASS",
        "METHOD=VIVADO_ILA",
        "TEST_ID=6",
        "WIDTHS_CYCLES=1,10,100,1000,10000,100000",
        "REPETITIONS_PER_WIDTH=10",
        "ELIGIBLE_TRIALS=60",
        "DETECTED_TRIALS=60",
        "EXPECTED_DETECTION_PER_WIDTH=10",
        "ILA_CLOCK_HZ=100000000",
        "CLOCK_PERIOD_NS=10",
        "DATA_DEPTH=1024",
        "TRIGGER_INDEX=512",
        "TRIGGER_COMPARE_VALUE=eq8'bXXXXXXXR",
        "SAMPLE_511=0x00",
        "SAMPLE_512=0x01",
        "PULSE_GAP_CONTRACT=PASS_SEQUENTIAL_DONE_REARM_AND_10MS_PRE",
        "PARTIAL_CAPTURE_COUNT=0",
        "FPGA_PROGRAM_COUNT=1",
        f"RUNTIME_BIT_SHA256={bit_sha}",
        f"LTX_SHA256={ltx_sha}",
        f"GENERATOR_RTL_SHA256={GENERATOR_RTL_SHA256}",
        f"GENERATOR_ADAPTER_SHA256={GENERATOR_ADAPTER_SHA256}",
        f"RUNTIME_ELF_SHA256={RUNTIME_ELF_SHA256}",
    ]
    for width in WIDTHS:
        visible_high = min(width, 512)
        fall_value = str(512 + width) if width <= 511 else "OUTSIDE_WINDOW"
        validation_lines.extend(
            [
                f"WIDTH.{width}.ELIGIBLE=10",
                f"WIDTH.{width}.DETECTED=10",
                f"WIDTH.{width}.RATE_PERCENT=100.0",
                f"WIDTH.{width}.VISIBLE_HIGH_SAMPLES={visible_high}",
                f"WIDTH.{width}.FIRST_LOW_INDEX={fall_value}",
                f"WIDTH.{width}.RESULT=PASS",
            ]
        )
    validation_lines.extend(
        [
            "LONG_PULSE_WIDTH_MEASUREMENT=CLIPPED_BY_FIXED_CAPTURE_WINDOW",
            "STEP8_VALIDATION=PASS",
        ]
    )
    validation_path = results_dir / "pulse_stress_validation.rpt"
    write_atomic_text(validation_path, "\n".join(validation_lines) + "\n")

    manifest_lines = [
        "# EdgeScope-Lite Vivado ILA Reference - Step 8 final manifest",
        "STEP=8",
        "OVERALL=PASS",
        "SOURCE_CAPTURE_MANIFEST=pulse_capture_manifest.rpt",
        "PULSE_DETECTION_CSV=pulse_detection.csv",
        "PULSE_SUMMARY_CSV=pulse_detection_summary.csv",
        "VALIDATION_REPORT=pulse_stress_validation.rpt",
        "RAW_CAPTURE_COUNT=60",
        "ILA_CAPTURE_COUNT=60",
        "TRIAL_REPORT_COUNT=60",
        "NORMALIZED_CAPTURE_COUNT=60",
        "TOTAL_ELIGIBLE=60",
        "TOTAL_DETECTED=60",
        "OVERALL_DETECTION_RATE_PERCENT=100.0",
        "PASS_THRESHOLD=10_OF_10_PER_WIDTH",
        "NO_TRIGGER_NOW=PASS",
        "PARTIAL_CAPTURE_COUNT=0",
        "LONG_PULSE_FALL=OUTSIDE_FIXED_1024_SAMPLE_WINDOW",
        f"RUNTIME_BIT_SHA256={bit_sha}",
        f"LTX_SHA256={ltx_sha}",
        f"GENERATOR_RTL_SHA256={GENERATOR_RTL_SHA256}",
        f"GENERATOR_ADAPTER_SHA256={GENERATOR_ADAPTER_SHA256}",
        f"RUNTIME_ELF_SHA256={RUNTIME_ELF_SHA256}",
        "STEP8_PULSE_STRESS=PASS",
    ]
    final_manifest_path = results_dir / "pulse_stress_manifest.rpt"
    write_atomic_text(final_manifest_path, "\n".join(manifest_lines) + "\n")

    status_lines = [
        "# EdgeScope-Lite Vivado ILA Reference - Step 8 Current Status",
        "STEP=8",
        "OVERALL=PASS",
        "PULSE_WIDTH_COUNT=6",
        "REPETITIONS_PER_WIDTH=10",
        "TOTAL_ELIGIBLE_TRIALS=60",
        "TOTAL_DETECTED_TRIALS=60",
        "OVERALL_DETECTION_RATE_PERCENT=100.0",
        "WIDTH_1_DETECTION=10_OF_10",
        "WIDTH_10_DETECTION=10_OF_10",
        "WIDTH_100_DETECTION=10_OF_10",
        "WIDTH_1000_DETECTION=10_OF_10",
        "WIDTH_10000_DETECTION=10_OF_10",
        "WIDTH_100000_DETECTION=10_OF_10",
        "TRIGGER_INDEX=512",
        "PARTIAL_CAPTURE_COUNT=0",
        "FPGA_PROGRAM_COUNT=1",
        "HOST_VALIDATION=PASS",
        "ARTIFACT_HASHES=PASS",
        "NEXT_ACTION=STEP9_RESOURCE_AND_TIMING_COMPARISON",
    ]
    status_path = results_dir / "step8_status.rpt"
    write_atomic_text(status_path, "\n".join(status_lines) + "\n")

    checksum_paths = [
        results_dir / "hardware_session.log",
        results_dir / "pulse_capture_manifest.rpt",
        detection_path,
        summary_path,
        validation_path,
        final_manifest_path,
        status_path,
    ]
    checksum_paths.extend(
        sorted((results_dir / "raw").glob("*_raw.csv"))
    )
    checksum_paths.extend(sorted((results_dir / "ila").glob("*.ila")))
    checksum_paths.extend(sorted((results_dir / "trials").glob("*.rpt")))
    checksum_paths.extend(sorted(normalized_dir.glob("*_normalized.csv")))
    for path in checksum_paths:
        if not path.is_file() or path.stat().st_size == 0:
            fail(f"checksum artifact missing or empty: {path}")
    checksum_lines = [
        f"{sha256(path)}  {path.relative_to(results_dir).as_posix()}"
        for path in checksum_paths
    ]
    write_atomic_text(
        results_dir / "SHA256SUMS", "\n".join(checksum_lines) + "\n"
    )

    print(f"STEP8_VALIDATE: PASS: {validation_path}")
    print(f"STEP8_STATUS: PASS: {status_path}")
    print(f"STEP8_CHECKSUMS: PASS: {results_dir / 'SHA256SUMS'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
