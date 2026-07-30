#!/usr/bin/env python3
"""Browser GUI for CPU Polling, EdgeScope-Lite, and Vivado ILA.

Demo mode keeps the checked-in CPU-polling UART evidence intact and derives
explicitly labelled hardware-analyzer previews from it.  Live mode auto-detects
the analyzer from its ``*_REFERENCE_READY`` UART marker.
"""

from __future__ import annotations

import argparse
import copy
import csv
import io
import json
import os
import queue
import re
import shutil
import subprocess
import threading
import time
import webbrowser
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOG = ROOT / "comparison/cpu_polling/results/uart_capture.log"
VIVADO_ILA_ROOT = ROOT / "comparison/vivado_ila"
VIVADO_ILA_CAPTURE_DIR = VIVADO_ILA_ROOT / "results/captures"
REQUIRED_VIVADO_VERSION = "2024.2"
DEFAULT_ILA_TIMEOUT_SECONDS = 60
MAX_ILA_TIMEOUT_SECONDS = 3600
MAX_CAPTURE_DEPTH = 65_536
SUPPORTED_UART_COMMANDS = frozenset("brfphzsq")

# Frozen v2.1 capture geometry (docs/day1_common_spec.md).
SYSTEM_CLOCK_HZ = 100_000_000
FROZEN_CAPTURE_DEPTH = 1024
FROZEN_TRIGGER_INDEX = 512
DIVIDER_BY_CODE = {0: 1, 1: 2, 2: 4, 3: 8}

# The EdgeScope-Lite firmware hardcodes one trigger profile and never accepts
# PC->board configuration commands, so these are the settings actually applied
# on the board.  Mirrors config_for_mode() and prepare_capture() in
# comparison/edgescope_lite/sw/edgescope_lite_reference.c.  Newer firmware may
# report the same values over UART, in which case the reported values win and
# the GUI labels them as measured instead of assumed.
FIRMWARE_FIXED_CONFIG = {
    "divider": 1,
    "channel_mask": 0xFF,
    "trigger_channel": 0,
    "pattern_value": 0xA0,
    "pattern_mask": 0xF0,
}

# Section 2.3 shooting presets.  ``command`` is the single UART byte the
# firmware really understands; ``expect`` is what section 2.4 must validate.
# ``firmware_supported`` is False when the profile needs a divider or trigger
# channel the current firmware cannot be told to use.
DEMO_PROFILES = {
    "demo1": {
        "label": "DEMO 1 – Rising CH0 100M",
        "command": "r",
        "mode": "RISING",
        "divider": 1,
        "trigger_channel": 0,
        "channel_mask": 0xFF,
        "firmware_supported": True,
        "note": "",
    },
    "demo2": {
        "label": "DEMO 2 – Falling CH1 12.5M",
        "command": "f",
        "mode": "FALLING",
        "divider": 8,
        "trigger_channel": 1,
        "channel_mask": 0xFF,
        "firmware_supported": False,
        "note": (
            "현재 firmware는 divider 1과 trigger CH0으로 고정되어 있어 "
            "divider 8·CH1을 보드에 지시할 수 없습니다. Falling 캡처는 "
            "실제 실행되며 GUI는 보드가 실제로 사용한 설정만 표시합니다."
        ),
    },
    "demo3": {
        "label": "DEMO 3 – Pattern A0/F0",
        "command": "p",
        "mode": "PATTERN",
        "divider": 1,
        "trigger_channel": 0,
        "channel_mask": 0xFF,
        "pattern_value": 0xA0,
        "pattern_mask": 0xF0,
        "firmware_supported": True,
        "note": "",
    },
}
VIVADO_INSTALL_ROOTS = (
    Path("/tools/Xilinx/Vivado"),
    Path("/opt/Xilinx/Vivado"),
    Path("/tools/AMD/Vivado"),
    Path("/opt/AMD/Vivado"),
)
VIVADO_ILA_SCRIPT_CANDIDATES = (
    VIVADO_ILA_ROOT / "hw/capture_ila.tcl",
    VIVADO_ILA_ROOT / "hw/capture.tcl",
    VIVADO_ILA_ROOT / "hw/hardware_capture.tcl",
)
IMPLEMENTATION_REPORTS = {
    "cpu_polling": ROOT / "comparison/cpu_polling/reports",
    "edgescope_lite": ROOT / "comparison/edgescope_lite/reports",
    "vivado_ila": ROOT / "comparison/vivado_ila/reports",
}


def _fields(line: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for item in line.split(",")[1:]:
        if "=" in item:
            key, value = item.split("=", 1)
            result[key.strip()] = value.strip()
    return result


ANALYZERS = {
    "cpu_polling": {
        "analyzer": "CPU_POLLING",
        "name": "A · CPU Polling",
    },
    "edgescope_lite": {
        "analyzer": "EDGESCOPE_LITE",
        "name": "B · EdgeScope-Lite",
    },
    "vivado_ila": {
        "analyzer": "VIVADO_ILA",
        "name": "C · Vivado ILA",
    },
}


def _analyzer_key(value: str | None) -> str | None:
    """Normalize firmware and GUI analyzer names to a stable API key."""
    if not value:
        return None
    normalized = re.sub(r"[^A-Z0-9]+", "_", value.strip().upper()).strip("_")
    if normalized.endswith("_READY"):
        normalized = normalized.removesuffix("_READY")
    if normalized in {
        "A", "CPU", "CPU_POLLING", "CPU_POLLING_REFERENCE",
    }:
        return "cpu_polling"
    if normalized in {
        "B", "EDGESCOPE", "EDGESCOPE_LITE", "EDGE_SCOPE_LITE",
        "EDGESCOPE_LITE_REFERENCE",
    }:
        return "edgescope_lite"
    if normalized in {
        "C", "ILA", "VIVADO_ILA", "VIVADO_ILA_REFERENCE",
        "XILINX_ILA",
    }:
        return "vivado_ila"
    return None


def _integer(value: str | None, default: int = 0) -> int:
    if value is None:
        return default
    try:
        return int(value.strip(), 0)
    except (TypeError, ValueError):
        return default


def _empty_dataset(key: str) -> dict:
    return {
        **ANALYZERS[key],
        "benchmarks": [],
        "pulses": [],
        "captures": [],
        "warnings": [],
        "representative": None,
        "ready": False,
        "zero_mask_pass": False,
        "zero_mask_tests": 0,
        "simulated": False,
        "evidence": "LIVE UART",
        "receiving": None,
    }


def _utilization_value(text: str, label: str) -> int | float | None:
    match = re.search(
        rf"^\|\s*{re.escape(label)}\s*\|\s*([0-9]+(?:\.[0-9]+)?)\s*\|",
        text,
        re.MULTILINE,
    )
    if not match:
        return None
    value = float(match.group(1))
    return int(value) if value.is_integer() else value


def _timing_values(text: str) -> dict[str, int | float | None]:
    marker = "| Design Timing Summary"
    section = text.split(marker, 1)[1] if marker in text else text
    match = re.search(
        r"^\s*(-?[0-9]+\.[0-9]+)\s+"
        r"(-?[0-9]+\.[0-9]+)\s+(\d+)\s+\d+\s+"
        r"(-?[0-9]+\.[0-9]+)\s+"
        r"(-?[0-9]+\.[0-9]+)\s+(\d+)\s+\d+",
        section,
        re.MULTILINE,
    )
    if not match:
        return {
            "wns_ns": None,
            "tns_ns": None,
            "setup_failing": None,
            "whs_ns": None,
            "ths_ns": None,
            "hold_failing": None,
        }
    return {
        "wns_ns": float(match.group(1)),
        "tns_ns": float(match.group(2)),
        "setup_failing": int(match.group(3)),
        "whs_ns": float(match.group(4)),
        "ths_ns": float(match.group(5)),
        "hold_failing": int(match.group(6)),
    }


def implementation_payload() -> dict:
    """Read the checked-in Vivado implementation reports for A/B/C."""
    builds = {}
    for key, report_dir in IMPLEMENTATION_REPORTS.items():
        utilization_file = report_dir / "utilization.rpt"
        timing_file = report_dir / "timing_summary.rpt"
        if not utilization_file.is_file() or not timing_file.is_file():
            builds[key] = {
                **ANALYZERS[key],
                "available": False,
            }
            continue
        utilization = utilization_file.read_text(
            encoding="utf-8", errors="replace"
        )
        timing = timing_file.read_text(encoding="utf-8", errors="replace")
        metrics = {
            "luts": _utilization_value(utilization, "Slice LUTs"),
            "registers": _utilization_value(
                utilization, "Slice Registers"
            ),
            "bram_tiles": _utilization_value(
                utilization, "Block RAM Tile"
            ),
            "dsps": _utilization_value(utilization, "DSPs"),
            **_timing_values(timing),
        }
        builds[key] = {
            **ANALYZERS[key],
            **metrics,
            "available": all(value is not None for value in metrics.values()),
            "source": str(report_dir.relative_to(ROOT)),
        }
    return {
        "builds": builds,
        "comparison_rule": (
            "A is a functional baseline; official resource savings are "
            "calculated only between B and C."
        ),
    }


CSV_HEADER = ["index", "ch7", "ch6", "ch5", "ch4", "ch3", "ch2", "ch1", "ch0"]


def _is_csv_header(line: str) -> bool:
    return [part.strip().lower() for part in line.split(",")] == CSV_HEADER


def _csv_sample(line: str) -> tuple[int, int] | None:
    parts = [part.strip() for part in line.split(",")]
    if len(parts) != 9:
        return None
    try:
        index = int(parts[0], 0)
        bits = [int(part, 0) for part in parts[1:]]
    except ValueError:
        return None
    if index < 0 or any(bit not in (0, 1) for bit in bits):
        return None
    value = 0
    for bit in bits:
        value = (value << 1) | bit
    return index, value


def _csv_cell(value: str) -> str:
    return re.sub(r"\s+", " ", value.lstrip("\ufeff").strip()).lower()


def _ila_value(value: str, radix: str) -> int | None:
    """Parse one Vivado ILA probe cell using the second header's radix."""
    clean = value.strip().replace("_", "")
    if not clean or re.search(r"[xz?]", clean, re.IGNORECASE):
        return None
    hint = radix.upper()
    try:
        if "BINARY" in hint or "BIN" in hint:
            parsed = int(clean.removeprefix("0b"), 2)
        elif "HEX" in hint:
            parsed = int(clean.removeprefix("0x"), 16)
        elif "UNSIGNED" in hint or "DEC" in hint:
            parsed = int(clean, 10)
        else:
            parsed = int(clean, 0)
    except ValueError:
        # Vivado commonly emits unprefixed hexadecimal bytes.
        try:
            parsed = int(clean, 16)
        except ValueError:
            return None
    return parsed if 0 <= parsed <= 0xFF else None


def _append_vivado_ila_csv(dataset: dict, lines: list[str]) -> bool:
    """Find and parse Vivado's two-row ILA CSV export.

    A valid C capture is deliberately strict: exactly 1024 unique logical
    samples (0..1023), one trigger assertion, and trigger index 512.  This
    prevents a partial/stale ILA export from being presented as evidence.
    """
    rows = list(csv.reader(io.StringIO("\n".join(lines))))
    header_row = -1
    index_column = trigger_column = probe_column = -1

    for row_number, row in enumerate(rows):
        normalized = [_csv_cell(cell) for cell in row]
        buffer_columns = [
            i for i, cell in enumerate(normalized)
            if "sample in buffer" in cell
        ]
        trigger_columns = [
            i for i, cell in enumerate(normalized) if "trigger" in cell
        ]
        if not buffer_columns or not trigger_columns:
            continue
        excluded = set(buffer_columns + trigger_columns)
        excluded.update(
            i for i, cell in enumerate(normalized) if "sample in window" in cell
        )
        candidates = [
            i for i, cell in enumerate(normalized)
            if i not in excluded
            and (
                "[7:0]" in cell
                or "probe" in cell
                or cell in {"data", "sample data", "gpio"}
            )
        ]
        if not candidates:
            continue
        header_row = row_number
        index_column = buffer_columns[0]
        trigger_column = trigger_columns[0]
        probe_column = candidates[0]
        break

    if header_row < 0:
        return False

    dataset["ready"] = True
    if header_row + 1 >= len(rows):
        dataset["warnings"].append(
            "Vivado ILA CSV 무결성 오류: 두 번째 radix header가 없습니다."
        )
        return True

    radix_row = rows[header_row + 1]
    if not any("radix" in _csv_cell(cell) for cell in radix_row):
        dataset["warnings"].append(
            "Vivado ILA CSV 무결성 오류: 두 번째 radix header를 인식하지 못했습니다."
        )
        return True
    probe_radix = (
        radix_row[probe_column] if probe_column < len(radix_row) else ""
    )

    samples: dict[int, int] = {}
    trigger_rows: list[int] = []
    duplicate_count = 0
    malformed_count = 0
    required_column = max(index_column, trigger_column, probe_column)
    for row in rows[header_row + 2:]:
        if not row or all(not cell.strip() for cell in row):
            continue
        if len(row) <= required_column:
            if samples:
                malformed_count += 1
            continue
        try:
            index_text = row[index_column].strip()
            try:
                sample_index = int(index_text, 0)
            except ValueError:
                sample_index = int(index_text, 10)
        except ValueError:
            if samples:
                malformed_count += 1
            continue
        sample_value = _ila_value(row[probe_column], probe_radix)
        if sample_value is None:
            malformed_count += 1
            continue
        if sample_index in samples:
            duplicate_count += 1
        samples[sample_index] = sample_value
        trigger_value = _csv_cell(row[trigger_column])
        if trigger_value in {"1", "true", "yes", "trigger"}:
            trigger_rows.append(sample_index)

    expected_indices = set(range(1024))
    missing_count = len(expected_indices - set(samples))
    out_of_range_count = len(set(samples) - expected_indices)
    integrity_errors = []
    if len(samples) != 1024 or missing_count or out_of_range_count:
        integrity_errors.append(
            f"샘플 1024개 필요(현재 {len(samples)}, 누락 {missing_count}, "
            f"범위 초과 {out_of_range_count})"
        )
    if duplicate_count:
        integrity_errors.append(f"중복 index {duplicate_count}개")
    if malformed_count:
        integrity_errors.append(f"해석 불가 row {malformed_count}개")
    if trigger_rows != [512]:
        shown = ", ".join(str(index) for index in trigger_rows) or "없음"
        integrity_errors.append(f"trigger index 512 필요(현재 {shown})")
    if integrity_errors:
        dataset["warnings"].append(
            "Vivado ILA CSV 무결성 오류: " + "; ".join(integrity_errors)
        )
        return True

    _append_capture(
        dataset,
        "vivado_ila",
        "IMPORTED VIVADO ILA",
        {
            "SAMPLE_HZ": 100_000_000,
            "OBSERVATIONS": 1024,
            "TRIGGER_INDEX": 512,
        },
        samples,
        512,
        duplicate_count,
    )
    return True


def _divider_from_meta(value: int | None) -> int | None:
    """Accept either a literal 1/2/4/8 divide factor or a raw register code."""
    if value is None:
        return None
    if value in {1, 2, 4, 8}:
        return value
    return DIVIDER_BY_CODE.get(value)


def _infer_edge_channel(
    samples: list[int],
    trigger_index: int,
    rising: bool,
) -> int | None:
    """Return the only channel whose 511->512 transition matches the mode.

    This is read straight out of the capture, so it is real evidence rather
    than an assumption about what the firmware was configured to do.  An
    ambiguous capture (several channels switching together) returns None.
    """
    if trigger_index <= 0 or trigger_index >= len(samples):
        return None
    before, after = samples[trigger_index - 1], samples[trigger_index]
    low, high = (0, 1) if rising else (1, 0)
    matches = [
        channel
        for channel in range(8)
        if (before >> channel) & 1 == low and (after >> channel) & 1 == high
    ]
    return matches[0] if len(matches) == 1 else None


def _resolve_capture_config(
    analyzer_key: str,
    mode: str,
    meta: dict[str, int],
    samples: list[int],
    trigger_index: int,
) -> dict:
    """Resolve the settings the board actually used for this capture.

    Section 2.5 of the demo scenario forbids showing settings the GUI cannot
    stand behind, so every field carries its provenance:

    ``uart``      firmware reported it explicitly
    ``derived``   computed from data the firmware reported
    ``firmware``  not reported; the frozen hardcoded firmware value
    """
    sources: dict[str, str] = {}
    hardware = analyzer_key != "cpu_polling"

    sample_hz = meta.get("SAMPLE_HZ") or meta.get("RATE") or 0
    if not sample_hz and hardware:
        sample_hz = SYSTEM_CLOCK_HZ

    if not hardware:
        # A is software polling: it has an observation throughput, not a
        # sample-clock divider or a fixed sample period.
        return {
            "hardware": False,
            "divider": None,
            "sample_hz": sample_hz,
            "sample_period_ns": None,
            "channel_mask": 0xFF,
            "trigger_channel": (
                _infer_edge_channel(samples, trigger_index, mode == "RISING")
                if mode in {"RISING", "FALLING"}
                else None
            ) or 0,
            "pattern_value": FIRMWARE_FIXED_CONFIG["pattern_value"],
            "pattern_mask": FIRMWARE_FIXED_CONFIG["pattern_mask"],
            "sources": {},
        }

    divider = _divider_from_meta(meta.get("SAMPLE_DIVIDER"))
    if divider is not None:
        sources["divider"] = "uart"
    elif sample_hz and SYSTEM_CLOCK_HZ % sample_hz == 0:
        candidate = SYSTEM_CLOCK_HZ // sample_hz
        if candidate in {1, 2, 4, 8}:
            divider = candidate
            sources["divider"] = "derived"
    if divider is None:
        divider = FIRMWARE_FIXED_CONFIG["divider"]
        sources["divider"] = "firmware"

    if "CHANNEL_MASK" in meta:
        channel_mask = meta["CHANNEL_MASK"] & 0xFF
        sources["channel_mask"] = "uart"
    else:
        channel_mask = FIRMWARE_FIXED_CONFIG["channel_mask"]
        sources["channel_mask"] = "firmware"

    trigger_channel: int | None = None
    if "TRIGGER_CHANNEL" in meta:
        trigger_channel = meta["TRIGGER_CHANNEL"] & 0x7
        sources["trigger_channel"] = "uart"
    elif mode in {"RISING", "FALLING"}:
        trigger_channel = _infer_edge_channel(
            samples, trigger_index, mode == "RISING"
        )
        if trigger_channel is not None:
            sources["trigger_channel"] = "derived"
    if trigger_channel is None:
        trigger_channel = FIRMWARE_FIXED_CONFIG["trigger_channel"]
        sources["trigger_channel"] = "firmware"

    for name, key in (
        ("pattern_value", "PATTERN_VALUE"),
        ("pattern_mask", "PATTERN_MASK"),
    ):
        sources[name] = "uart" if key in meta else "firmware"

    return {
        "hardware": True,
        "divider": divider,
        "sample_hz": sample_hz,
        "sample_period_ns": (1e9 / sample_hz) if sample_hz else None,
        "channel_mask": channel_mask,
        "trigger_channel": trigger_channel,
        "pattern_value": meta.get(
            "PATTERN_VALUE", FIRMWARE_FIXED_CONFIG["pattern_value"]
        ) & 0xFF,
        "pattern_mask": meta.get(
            "PATTERN_MASK", FIRMWARE_FIXED_CONFIG["pattern_mask"]
        ) & 0xFF,
        "sources": sources,
    }


def _pattern_display(value: int, mask: int) -> str:
    """Render a masked pattern as 0xA? with don't-care nibbles hidden."""
    digits = ""
    for shift in (4, 0):
        nibble_mask = (mask >> shift) & 0xF
        if nibble_mask == 0xF:
            digits += f"{(value >> shift) & 0xF:X}"
        elif nibble_mask == 0x0:
            digits += "?"
        else:
            digits += "*"
    return "0x" + digits


def _validate_capture(
    analyzer_key: str,
    mode: str,
    samples: list[int],
    trigger_index: int,
    config: dict,
) -> dict:
    """Apply the section 2.4 automatic validation rules.

    Every check reports ``PASS``, ``FAIL`` or ``N/A``.  The capture is only
    ``CAPTURE VALID`` when no check failed.
    """
    checks: list[dict] = []

    def add(name: str, detail: str, state: str) -> None:
        checks.append({"name": name, "detail": detail, "state": state})

    depth = len(samples)
    add(
        "Samples",
        f"{depth:,} / {FROZEN_CAPTURE_DEPTH:,}",
        "PASS" if depth == FROZEN_CAPTURE_DEPTH else "FAIL",
    )
    add(
        "Trigger",
        f"Index {trigger_index}",
        "PASS" if trigger_index == FROZEN_TRIGGER_INDEX else "FAIL",
    )

    channel = config["trigger_channel"]
    in_range = 0 < trigger_index < depth
    before = samples[trigger_index - 1] if in_range else 0
    after = samples[trigger_index] if in_range else 0

    if mode in {"RISING", "FALLING"}:
        want_before, want_after = (0, 1) if mode == "RISING" else (1, 0)
        got_before = (before >> channel) & 1
        got_after = (after >> channel) & 1
        state = "N/A"
        if in_range:
            state = (
                "PASS"
                if (got_before, got_after) == (want_before, want_after)
                else "FAIL"
            )
        add(
            "Condition",
            f"{mode.title()} CH{channel} · "
            f"CH{channel}[{trigger_index - 1}]={got_before}, "
            f"CH{channel}[{trigger_index}]={got_after}",
            state,
        )
    elif mode.startswith("PATTERN"):
        mask = config["pattern_mask"]
        value = config["pattern_value"]
        target = value & mask
        entry_hold = mode == "PATTERN HOLD"
        match_state = "N/A"
        if in_range:
            match_state = "PASS" if (after & mask) == target else "FAIL"
        add(
            "Condition",
            f"Sample[{trigger_index}] = 0x{after:02X} · "
            f"Pattern {_pattern_display(value, mask)} · "
            f"Mask 0x{mask:02X} · "
            f"{'MATCH' if match_state == 'PASS' else 'NO MATCH'}",
            match_state,
        )
        if entry_hold:
            # Pattern-hold arms after the pattern has been held, so the
            # preceding sample legitimately matches too.
            add(
                "Entry edge",
                f"Sample[{trigger_index - 1}] = 0x{before:02X} · "
                "PATTERN HOLD은 진입 edge를 요구하지 않습니다",
                "N/A",
            )
        else:
            entry_state = "N/A"
            if in_range:
                entry_state = (
                    "PASS" if (before & mask) != target else "FAIL"
                )
            add(
                "Entry edge",
                f"Sample[{trigger_index - 1}] = 0x{before:02X} · "
                f"masked 0x{before & mask:02X} "
                f"{'!=' if entry_state == 'PASS' else '=='} "
                f"0x{target:02X}",
                entry_state,
            )
    else:
        add("Condition", f"{mode} 검증 규칙 없음", "N/A")

    if analyzer_key == "cpu_polling":
        # A is a software-polling baseline, not a 100 MS/s hardware capture.
        add(
            "Sample rate",
            "CPU polling baseline · 100 MS/s 검증 대상 아님",
            "N/A",
        )
    else:
        add(
            "Sample rate",
            f"{config['sample_hz'] / 1e6:.2f} MS/s · divider {config['divider']}"
            if config["sample_hz"]
            else "보고된 sample rate 없음",
            "PASS" if config["sample_hz"] else "N/A",
        )

    failed = [check["name"] for check in checks if check["state"] == "FAIL"]
    return {
        "checks": checks,
        "failed": failed,
        "valid": not failed,
    }


def _append_capture(
    dataset: dict,
    analyzer_key: str,
    mode: str,
    meta: dict[str, int],
    sample_rows: dict[int, int],
    trigger_index: int,
    duplicate_count: int = 0,
) -> None:
    """Validate logical sample indices and append one normalized capture."""
    if not sample_rows:
        return

    inferred_depth = max(sample_rows) + 1
    depth = meta.get(
        "OBSERVATIONS",
        meta.get("DEPTH", meta.get("CAPTURE_DEPTH", inferred_depth)),
    )
    if depth <= 0 or depth > MAX_CAPTURE_DEPTH:
        dataset["warnings"].append(
            "캡처 무결성 오류: "
            f"depth {depth}는 지원 범위 1..{MAX_CAPTURE_DEPTH} 밖입니다."
        )
        return
    missing_count = sum(index not in sample_rows for index in range(depth))
    out_of_range_count = sum(index >= depth for index in sample_rows)
    if duplicate_count or missing_count or out_of_range_count:
        dataset["warnings"].append(
            "캡처 무결성 오류: "
            f"누락 {missing_count}, 중복 {duplicate_count}, "
            f"범위 초과 {out_of_range_count}"
        )
        return

    trigger_index = meta.get("TRIGGER_INDEX", trigger_index)
    if trigger_index < 0 or trigger_index >= depth:
        dataset["warnings"].append(
            f"캡처 무결성 오류: trigger index {trigger_index}, depth {depth}"
        )
        return

    samples = [sample_rows[index] for index in range(depth)]
    sample_hz = meta.get(
        "SAMPLE_HZ",
        meta.get(
            "RATE",
            meta.get("OBS_PER_SEC", 0)
            if analyzer_key == "cpu_polling"
            else 100_000_000,
        ),
    )
    config = _resolve_capture_config(
        analyzer_key, mode, {**meta, "SAMPLE_HZ": sample_hz}, samples,
        trigger_index,
    )
    dataset["captures"].append({
        "analyzer": ANALYZERS[analyzer_key]["analyzer"],
        "mode": mode,
        "samples": samples,
        "trigger_index": trigger_index,
        "timer_hz": meta.get("TIMER_HZ", 100_000_000),
        "observations": depth,
        "elapsed_ticks": meta.get("ELAPSED_TICKS", 0),
        "rate": meta.get("OBS_PER_SEC", sample_hz),
        "sample_hz": sample_hz,
        "start_addr": meta.get("START_ADDR"),
        "trigger_addr": meta.get("TRIGGER_ADDR"),
        "write_addr": meta.get("WRITE_ADDR"),
        "config": config,
        "validation": _validate_capture(
            analyzer_key, mode, samples, trigger_index, config
        ),
    })


def parse_uart(text: str) -> dict:
    """Parse complete or in-progress output from analyzer A, B, or C.

    A legacy-compatible view of the active dataset remains at the top level.
    The ``datasets`` member contains the lossless analyzer-separated results.
    """
    lines = text.replace("\r", "").splitlines()
    datasets = {key: _empty_dataset(key) for key in ANALYZERS}
    ila_csv_found = _append_vivado_ila_csv(datasets["vivado_ila"], lines)
    pending_mode = {key: "UNKNOWN" for key in ANALYZERS}
    last_command = ""
    current_analyzer: str | None = "vivado_ila" if ila_csv_found else None
    last_ready_analyzer: str | None = current_analyzer
    i = 0

    while i < len(lines):
        line = lines[i].strip()
        if re.match(r"^(?:>\s*)?[brfphzs]$", line, re.IGNORECASE):
            last_command = line[-1].lower()
        elif line in {
            "CPU_POLLING_REFERENCE_READY",
            "EDGESCOPE_LITE_REFERENCE_READY",
            "VIVADO_ILA_REFERENCE_READY",
        }:
            key = _analyzer_key(line.removesuffix("_READY"))
            if key:
                datasets[key]["ready"] = True
                current_analyzer = key
                last_ready_analyzer = key
        elif line.startswith("ANALYZER="):
            key = _analyzer_key(line.split("=", 1)[1])
            if key:
                datasets[key]["ready"] = True
                current_analyzer = key
                last_ready_analyzer = key
        elif line.startswith((
            "ILA_TRIAL_BEGIN,",
            "ILA_TRIAL_READY,",
            "ILA_TRIAL_COMPLETE,",
        )):
            values = _fields(line)
            key = _analyzer_key(values.get("ANALYZER")) or "vivado_ila"
            datasets[key]["ready"] = True
            pending_mode[key] = values.get("MODE", pending_mode[key])
            current_analyzer = key
            last_ready_analyzer = key
        elif line.startswith("CAPTURE_PASS,"):
            values = _fields(line)
            key = (
                _analyzer_key(values.get("ANALYZER"))
                or current_analyzer
                or last_ready_analyzer
                or "cpu_polling"
            )
            mode = values.get("MODE", "UNKNOWN")
            if mode == "PATTERN" and last_command == "h":
                mode = "PATTERN HOLD"
            pending_mode[key] = mode
            current_analyzer = key
        elif line.startswith("MODE_SUMMARY,"):
            values = _fields(line)
            if "AVG_OBS_PER_SEC" in values:
                key = (
                    _analyzer_key(values.get("ANALYZER"))
                    or current_analyzer
                    or last_ready_analyzer
                    or "cpu_polling"
                )
                current_analyzer = key
                datasets[key]["benchmarks"].append({
                    "mode": values.get("MODE", "?"),
                    "rate": _integer(values["AVG_OBS_PER_SEC"]),
                    "period_ps": _integer(values.get("AVG_PERIOD_PS")),
                })
        elif line.startswith("REPRESENTATIVE_LOWEST_MODE_AVG_OBS_PER_SEC="):
            key = current_analyzer or last_ready_analyzer or "cpu_polling"
            datasets[key]["representative"] = _integer(line.split("=", 1)[1])
        elif line.startswith("PULSE_WIDTH_CYCLES="):
            values = dict(
                part.split("=", 1) for part in line.split(",") if "=" in part
            )
            key = (
                _analyzer_key(values.get("ANALYZER"))
                or current_analyzer
                or last_ready_analyzer
                or "cpu_polling"
            )
            current_analyzer = key
            datasets[key]["pulses"].append({
                "cycles": _integer(values.get("PULSE_WIDTH_CYCLES")),
                "detected": _integer(values.get("DETECTED")),
                "trials": _integer(values.get("TRIALS")),
            })
        elif line in {
            "CPU_POLLING_REFERENCE",
            "EDGESCOPE_LITE_REFERENCE",
            "EDGE_SCOPE_LITE",
            "VIVADO_ILA_REFERENCE",
        }:
            key = _analyzer_key(line) or "cpu_polling"
            current_analyzer = key
            meta: dict[str, int] = {}
            sample_rows: dict[int, int] = {}
            trigger_index = 512
            duplicate_count = 0
            csv_mode = False
            i += 1
            while i < len(lines) and lines[i].strip() != "CAPTURE_END":
                current = lines[i].strip()
                sample = re.match(r"^(\d{4}):\s*([0-9A-Fa-f]{2})", current)
                if sample:
                    sample_index = int(sample.group(1))
                    if sample_index in sample_rows:
                        duplicate_count += 1
                    sample_rows[sample_index] = int(sample.group(2), 16)
                    if "<TRIGGER>" in current:
                        trigger_index = sample_index
                elif _is_csv_header(current):
                    csv_mode = True
                elif csv_mode and (csv_sample := _csv_sample(current)):
                    sample_index, sample_value = csv_sample
                    if sample_index in sample_rows:
                        duplicate_count += 1
                    sample_rows[sample_index] = sample_value
                elif "=" in current:
                    meta_key, value = current.split("=", 1)
                    parsed_value = _integer(value, -1)
                    if parsed_value >= 0:
                        meta[meta_key.strip().upper()] = parsed_value
                i += 1
            analyzer_key = current_analyzer or "cpu_polling"
            if i >= len(lines):
                # The dump is still arriving.  A 1,024-sample dump takes about
                # 11 s at 9,600 baud and the GUI re-parses the whole transcript
                # twice a second, so validating a truncated capture here would
                # raise a bogus integrity error for the entire transfer.
                datasets[analyzer_key]["receiving"] = {
                    "mode": pending_mode[analyzer_key],
                    "received": len(sample_rows),
                    "expected": meta.get(
                        "OBSERVATIONS", meta.get("DEPTH", FROZEN_CAPTURE_DEPTH)
                    ),
                }
            else:
                _append_capture(
                    datasets[analyzer_key],
                    analyzer_key,
                    pending_mode[analyzer_key],
                    meta,
                    sample_rows,
                    trigger_index,
                    duplicate_count,
                )
        elif _is_csv_header(line):
            # Day 3 standalone export format: no UART marker is required.
            analyzer_key = "edgescope_lite"
            current_analyzer = analyzer_key
            datasets[analyzer_key]["ready"] = True
            sample_rows: dict[int, int] = {}
            duplicate_count = 0
            i += 1
            while i < len(lines):
                csv_sample = _csv_sample(lines[i].strip())
                if csv_sample is None:
                    break
                sample_index, sample_value = csv_sample
                if sample_index in sample_rows:
                    duplicate_count += 1
                sample_rows[sample_index] = sample_value
                i += 1
            _append_capture(
                datasets[analyzer_key],
                analyzer_key,
                "IMPORTED CSV",
                {
                    "RATE": 100_000_000,
                    "DEPTH": max(sample_rows) + 1 if sample_rows else 0,
                },
                sample_rows,
                512 if len(sample_rows) > 512 else len(sample_rows) // 2,
                duplicate_count,
            )
            i -= 1
        elif line.startswith(("P-05_PASS=", "P-05_FAIL=")):
            key = current_analyzer or last_ready_analyzer or "cpu_polling"
            datasets[key]["zero_mask_tests"] += 1
            if line.startswith("P-05_PASS=NO_TRIGGER"):
                datasets[key]["zero_mask_pass"] = True
        i += 1

    active_key = current_analyzer or last_ready_analyzer
    legacy_key = active_key or "cpu_polling"
    result = dict(datasets[legacy_key])
    result.update({
        "datasets": datasets,
        "active_analyzer": active_key,
        "ready_analyzers": [
            key for key, dataset in datasets.items() if dataset["ready"]
        ],
    })
    return result


def demo_payload(text: str) -> dict:
    """Return recorded A evidence plus clearly labelled synthetic B/C previews."""
    result = parse_uart(text)
    cpu = result["datasets"]["cpu_polling"]
    cpu["evidence"] = "RECORDED UART"

    edgescope = copy.deepcopy(cpu)
    edgescope.update({
        **ANALYZERS["edgescope_lite"],
        "ready": True,
        "simulated": True,
        "evidence": "SYNTHETIC DEMO · HARDWARE MEASUREMENT PENDING",
        "representative": 100_000_000,
        "benchmarks": [{
            "mode": "SAMPLE CLK",
            "rate": 100_000_000,
            "period_ps": 10_000,
            "simulated": True,
        }],
    })
    for capture_number, capture in enumerate(edgescope["captures"]):
        start_addr = (137 + capture_number * 173) & 0x3FF
        capture.update({
            "analyzer": "EDGESCOPE_LITE",
            "rate": 100_000_000,
            "sample_hz": 100_000_000,
            "timer_hz": 100_000_000,
            "start_addr": start_addr,
            "trigger_addr": (start_addr + capture["trigger_index"]) & 0x3FF,
            "write_addr": (start_addr + len(capture["samples"]) - 1) & 0x3FF,
            "simulated": True,
        })
        # The preview reinterprets A's samples as a 100 MS/s hardware capture,
        # so its settings and section 2.4 verdict have to be recomputed.
        capture["config"] = _resolve_capture_config(
            "edgescope_lite",
            capture["mode"],
            {"SAMPLE_HZ": 100_000_000},
            capture["samples"],
            capture["trigger_index"],
        )
        capture["validation"] = _validate_capture(
            "edgescope_lite",
            capture["mode"],
            capture["samples"],
            capture["trigger_index"],
            capture["config"],
        )
    for pulse in edgescope["pulses"]:
        pulse.update({
            "detected": pulse["trials"],
            "expected": True,
            "simulated": True,
        })

    vivado_ila = copy.deepcopy(edgescope)
    vivado_ila.update({
        **ANALYZERS["vivado_ila"],
        "evidence": "SYNTHETIC DEMO · VIVADO ILA CAPTURE PENDING",
        "benchmarks": [{
            "mode": "ILA SAMPLE CLK",
            "rate": 100_000_000,
            "period_ps": 10_000,
            "simulated": True,
        }],
    })
    for capture in vivado_ila["captures"]:
        capture.update({
            "analyzer": "VIVADO_ILA",
            "start_addr": None,
            "trigger_addr": None,
            "write_addr": None,
        })

    result["datasets"]["edgescope_lite"] = edgescope
    result["datasets"]["vivado_ila"] = vivado_ila
    result["active_analyzer"] = "cpu_polling"
    result["ready_analyzers"] = list(ANALYZERS)
    return result


@dataclass
class SerialManager:
    serial: object | None = None
    port: str | None = None
    transcript: str = ""
    error: str | None = None
    lock: threading.Lock = field(default_factory=threading.Lock)
    parse_lock: threading.Lock = field(default_factory=threading.Lock)
    stop_event: threading.Event = field(default_factory=threading.Event)
    reader_thread: threading.Thread | None = field(
        default=None, init=False, repr=False
    )
    transcript_revision: int = 0
    parsed_revision: int = -1
    parsed_data: dict | None = field(default=None, init=False, repr=False)

    def ports(self) -> list[str]:
        try:
            from serial.tools import list_ports
            ports = list(list_ports.comports())
            usb_ports = [
                port.device
                for port in ports
                if port.vid is not None
                or port.device.startswith(("/dev/ttyUSB", "/dev/ttyACM"))
                if not (
                    port.vid == 0x0403
                    and port.pid == 0x6010
                    and (port.location or "").endswith(".0")
                )
            ]
            return usb_ports
        except ImportError:
            return []

    def connect(self, port: str, baud: int = 9600) -> None:
        self.disconnect()
        try:
            import serial
            connection = serial.Serial(port, baudrate=baud, timeout=0.1)
        except Exception as exc:
            raise RuntimeError(f"UART 연결 실패: {exc}") from exc
        stop_event = threading.Event()
        reader = threading.Thread(
            target=self._reader,
            args=(connection, stop_event),
            daemon=True,
        )
        with self.lock:
            self.serial = connection
            self.port = port
            self.transcript = ""
            self.error = None
            self.stop_event = stop_event
            self.reader_thread = reader
            self.transcript_revision += 1
            self.parsed_revision = -1
            self.parsed_data = None
        reader.start()

    def _reader(
        self,
        connection: object,
        stop_event: threading.Event,
    ) -> None:
        while not stop_event.is_set():
            try:
                data = connection.read(4096)
                if data:
                    with self.lock:
                        if self.serial is not connection:
                            return
                        self.transcript = (
                            self.transcript + data.decode("ascii", errors="replace")
                        )[-2_000_000:]
                        self.transcript_revision += 1
            except Exception as exc:
                if stop_event.is_set():
                    return
                with self.lock:
                    if self.serial is connection:
                        self.error = str(exc)
                        self.serial = None
                        self.port = None
                        self.reader_thread = None
                stop_event.set()
                try:
                    connection.close()
                except Exception:
                    pass
                return

    def command(self, value: str) -> None:
        if len(value) != 1 or value not in SUPPORTED_UART_COMMANDS:
            raise ValueError("지원하지 않는 명령입니다.")
        with self.lock:
            if not self.serial:
                raise RuntimeError("먼저 UART를 연결하세요.")
            connection = self.serial
            try:
                connection.write(value.encode("ascii"))
                connection.flush()
            except Exception as exc:
                self.error = str(exc)
                self.serial = None
                self.port = None
                self.stop_event.set()
                try:
                    connection.close()
                except Exception:
                    pass
                raise RuntimeError(f"UART 명령 전송 실패: {exc}") from exc

    def disconnect(self) -> None:
        with self.lock:
            stop_event = self.stop_event
            connection = self.serial
            reader = self.reader_thread
            stop_event.set()
            self.serial = None
            self.port = None
            self.reader_thread = None
            self.error = None
        if connection:
            try:
                connection.close()
            except Exception:
                pass
        if reader and reader is not threading.current_thread():
            reader.join(timeout=0.5)

    def _parse_snapshot(self, transcript: str, revision: int) -> dict:
        with self.parse_lock:
            with self.lock:
                if (
                    self.parsed_data is not None
                    and self.parsed_revision == revision
                ):
                    return self.parsed_data
            parsed = parse_uart(transcript)
            with self.lock:
                if self.transcript_revision == revision:
                    self.parsed_data = parsed
                    self.parsed_revision = revision
            return parsed

    def state(self) -> dict:
        with self.lock:
            transcript = self.transcript
            revision = self.transcript_revision
            connected = self.serial is not None
            port = self.port
            error = self.error
        data = self._parse_snapshot(transcript, revision)
        return {
            "connected": connected,
            "board_ready": data["active_analyzer"] is not None,
            "port": port,
            "error": error,
            "transcript_tail": transcript[-12000:],
            "data": data,
        }


def _vivado_version(executable: str) -> str | None:
    """Return Vivado's major.minor release without invoking a shell."""
    try:
        completed = subprocess.run(
            [executable, "-version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.search(
        r"\bvivado\s+v?(\d{4}\.\d+)\b",
        completed.stdout or "",
        re.IGNORECASE,
    )
    return match.group(1) if match else None


def _vivado_executable() -> str | None:
    """Resolve and verify Vivado 2024.2, preferring its canonical installs."""
    configured = os.environ.get("VIVADO")
    if configured:
        configured_path = Path(configured).expanduser()
        if not configured_path.is_file():
            raise RuntimeError(
                f"VIVADO 실행 파일이 없습니다: {configured_path}"
            )
        configured_version = _vivado_version(str(configured_path))
        if configured_version != REQUIRED_VIVADO_VERSION:
            shown = configured_version or "인식 불가"
            raise RuntimeError(
                f"VIVADO는 Vivado {shown}를 가리킵니다. "
                f"이 프로젝트에는 Vivado {REQUIRED_VIVADO_VERSION}가 필요합니다."
            )
        return str(configured_path)

    candidates: list[Path] = []
    for root in VIVADO_INSTALL_ROOTS:
        candidates.append(root / REQUIRED_VIVADO_VERSION / "bin/vivado")
    discovered = shutil.which("vivado")
    if discovered:
        candidates.append(Path(discovered))
    for root in VIVADO_INSTALL_ROOTS:
        if root.is_dir():
            candidates.extend(root.glob("*/bin/vivado"))

    seen: set[Path] = set()
    found_versions: list[str] = []
    for candidate in candidates:
        candidate = candidate.expanduser()
        try:
            identity = candidate.resolve()
        except OSError:
            identity = candidate
        if identity in seen or not candidate.is_file():
            continue
        seen.add(identity)
        version = _vivado_version(str(candidate))
        if version == REQUIRED_VIVADO_VERSION:
            return str(candidate)
        if version:
            found_versions.append(f"{version} ({candidate})")
    if found_versions:
        raise RuntimeError(
            f"Vivado {REQUIRED_VIVADO_VERSION}를 찾지 못했습니다. "
            f"감지된 버전: {', '.join(found_versions)}"
        )
    return None


def _ila_timeout_seconds() -> int:
    raw_value = os.environ.get("EDGESCOPE_ILA_TIMEOUT_SECONDS")
    if raw_value is None:
        return DEFAULT_ILA_TIMEOUT_SECONDS
    try:
        seconds = int(raw_value.strip(), 10)
    except ValueError as exc:
        raise ValueError(
            "EDGESCOPE_ILA_TIMEOUT_SECONDS는 정수 초 단위여야 합니다."
        ) from exc
    if not 1 <= seconds <= MAX_ILA_TIMEOUT_SECONDS:
        raise ValueError(
            "EDGESCOPE_ILA_TIMEOUT_SECONDS는 "
            f"1..{MAX_ILA_TIMEOUT_SECONDS} 범위여야 합니다."
        )
    return seconds


def _ila_capture_script() -> Path | None:
    for candidate in VIVADO_ILA_SCRIPT_CANDIDATES:
        if candidate.is_file():
            return candidate
    hardware_dir = VIVADO_ILA_ROOT / "hw"
    if hardware_dir.is_dir():
        matches = sorted(hardware_dir.glob("*capture*.tcl"))
        if matches:
            return matches[0]
    return None


@dataclass
class IlaCaptureManager:
    """Asynchronous Vivado/JTAG capture bridge.

    The Tcl process must print ``VIVADO_ILA_ARMED`` before this bridge sends
    the UART stimulus.  This ordering prevents a generator run from racing
    ahead of the ILA trigger arm.
    """

    serial_manager: SerialManager
    status_name: str = "idle"
    mode: str | None = None
    csv_path: str | None = None
    output: str = ""
    error: str | None = None
    data: dict | None = None
    process: subprocess.Popen | None = None
    lock: threading.Lock = field(default_factory=threading.Lock)

    MODE_COMMANDS = {
        "RISING": "r",
        "FALLING": "f",
        "PATTERN": "p",
        "PATTERN HOLD": "h",
        "PATTERN_HOLD": "h",
    }

    def start(self, mode: str, program: bool = False) -> dict:
        normalized_mode = re.sub(r"\s+", " ", mode.strip().upper())
        command = self.MODE_COMMANDS.get(normalized_mode)
        if command is None:
            raise ValueError("C 캡처 mode는 RISING/FALLING/PATTERN/PATTERN HOLD만 지원합니다.")
        if not self.serial_manager.state()["connected"]:
            raise RuntimeError(
                "C Vivado ILA 캡처에는 UART 연결이 필요합니다. "
                "보드가 연결되지 않아 자극을 시작하지 않았습니다."
            )
        script = _ila_capture_script()
        if script is None:
            raise RuntimeError(
                "Vivado ILA capture Tcl을 찾지 못했습니다. "
                "comparison/vivado_ila/hw의 C 빌드를 먼저 완료하세요."
            )
        vivado = _vivado_executable()
        if vivado is None:
            raise RuntimeError(
                f"Vivado {REQUIRED_VIVADO_VERSION} 실행 파일을 찾지 못했습니다. "
                "VIVADO 환경 변수 또는 설치 경로를 확인하세요."
            )
        timeout_seconds = _ila_timeout_seconds()

        with self.lock:
            if self.status_name in {"arming", "capturing"}:
                raise RuntimeError("Vivado ILA 캡처가 이미 진행 중입니다.")
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            safe_mode = normalized_mode.replace(" ", "_").lower()
            csv_path = VIVADO_ILA_CAPTURE_DIR / f"vivado_ila_{safe_mode}_{timestamp}.csv"
            self.status_name = "arming"
            self.mode = normalized_mode
            self.csv_path = str(csv_path)
            self.output = ""
            self.error = None
            self.data = None

        thread = threading.Thread(
            target=self._run,
            args=(
                vivado,
                script,
                csv_path,
                normalized_mode,
                command,
                program,
                timeout_seconds,
            ),
            daemon=True,
        )
        thread.start()
        return self.state()

    def _append_output(self, line: str) -> None:
        with self.lock:
            self.output = (self.output + line)[-20000:]

    def _run(
        self,
        vivado: str,
        script: Path,
        csv_path: Path,
        mode: str,
        command: str,
        program: bool,
        timeout_seconds: int,
    ) -> None:
        try:
            csv_path.parent.mkdir(parents=True, exist_ok=True)
            environment = os.environ.copy()
            tcl_mode = "PATTERN" if mode == "PATTERN HOLD" else mode
            environment.update({
                "EDGESCOPE_ILA_MODE": tcl_mode.replace(" ", "_"),
                "EDGESCOPE_ILA_CSV": str(csv_path),
                "EDGESCOPE_ILA_PROGRAM": "1" if program else "0",
            })
            preferred_bit = (
                VIVADO_ILA_ROOT / "vitis_artifacts/vivado_ila_app.bit"
            )
            preferred_ltx = VIVADO_ILA_ROOT / "hw/vivado_ila_reference.ltx"
            if program and not preferred_bit.is_file():
                raise RuntimeError(
                    "C Vitis 애플리케이션이 포함된 bitstream이 없습니다: "
                    f"{preferred_bit}"
                )
            ltx_files = (
                [preferred_ltx]
                if preferred_ltx.is_file()
                else sorted((VIVADO_ILA_ROOT / "hw").glob("**/*.ltx"))
            )
            if preferred_bit.is_file():
                environment["EDGESCOPE_ILA_BIT"] = str(preferred_bit)
            if ltx_files:
                environment["EDGESCOPE_ILA_LTX"] = str(ltx_files[-1])

            process = subprocess.Popen(
                [
                    vivado,
                    "-mode", "batch",
                    "-nojournal",
                    "-nolog",
                    "-source", str(script),
                ],
                cwd=script.parent,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            with self.lock:
                self.process = process

            assert process.stdout is not None
            output_queue: queue.Queue[str] = queue.Queue()

            def read_output() -> None:
                assert process.stdout is not None
                for output_line in process.stdout:
                    output_queue.put(output_line)

            reader = threading.Thread(target=read_output, daemon=True)
            reader.start()
            deadline = time.monotonic() + timeout_seconds
            armed = False
            capture_pass = False
            while reader.is_alive() or not output_queue.empty():
                if time.monotonic() >= deadline:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                    raise RuntimeError(
                        f"Vivado ILA 캡처가 {timeout_seconds}초를 "
                        "초과했습니다. JTAG/hw_server 상태를 확인하세요."
                    )
                try:
                    line = output_queue.get(timeout=0.2)
                except queue.Empty:
                    if process.poll() is not None and not reader.is_alive():
                        break
                    continue
                self._append_output(line)
                if "VIVADO_ILA_ARMED" in line and not armed:
                    armed = True
                    with self.lock:
                        self.status_name = "capturing"
                    self.serial_manager.command(command)
                if "VIVADO_ILA_CAPTURE_PASS" in line:
                    capture_pass = True

            return_code = process.wait()
            if return_code != 0:
                raise RuntimeError(f"Vivado ILA capture Tcl 종료 코드: {return_code}")
            if not armed:
                raise RuntimeError(
                    "JTAG ILA가 arm되지 않았습니다. 보드/JTAG 연결과 hw_server를 확인하세요."
                )
            if not capture_pass:
                raise RuntimeError("Vivado ILA 완료 marker를 받지 못했습니다.")
            if not csv_path.is_file():
                raise RuntimeError(f"Vivado ILA CSV가 생성되지 않았습니다: {csv_path}")

            parsed = parse_uart(
                csv_path.read_text(encoding="utf-8-sig", errors="replace")
            )
            dataset = parsed["datasets"]["vivado_ila"]
            if not dataset["captures"]:
                detail = dataset["warnings"][-1] if dataset["warnings"] else "알 수 없는 CSV 형식"
                raise RuntimeError(detail)
            dataset["captures"][0]["mode"] = mode
            dataset["evidence"] = "MEASURED · VIVADO ILA JTAG CSV"
            dataset["simulated"] = False
            with self.lock:
                self.status_name = "complete"
                self.data = parsed
        except Exception as exc:
            with self.lock:
                running_process = self.process
            if running_process and running_process.poll() is None:
                running_process.terminate()
            with self.lock:
                self.status_name = "error"
                self.error = str(exc)
        finally:
            with self.lock:
                self.process = None

    def state(self) -> dict:
        with self.lock:
            return {
                "status": self.status_name,
                "mode": self.mode,
                "csv_path": self.csv_path,
                "output_tail": self.output[-12000:],
                "error": self.error,
                "data": self.data,
            }

    def stop(self) -> None:
        with self.lock:
            process = self.process
        if process and process.poll() is None:
            process.terminate()


HTML = r"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="data:,">
<title>EdgeScope-Lite · A/B/C Analyzer Console</title>
<style>
:root{
  --bg:#071019;--panel:#0d1925;--panel2:#111f2d;--line:#203348;
  --text:#e6f1fb;--muted:#8298aa;--cyan:#22d3ee;--green:#34d399;
  --amber:#fbbf24;--red:#fb7185;
}
*{box-sizing:border-box}
body{
  margin:0;min-height:100vh;color:var(--text);
  background:radial-gradient(circle at 30% 0,#10263a 0,#071019 48%);
  font:14px Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;
}
.shell{width:min(100%,1600px);margin:auto;padding:14px}
.top{min-height:48px;display:flex;align-items:center;gap:12px;margin-bottom:10px}
.brand{font-size:20px;font-weight:800;letter-spacing:.3px;white-space:nowrap;line-height:1.15}
.brand span{color:var(--cyan)}
.brand small{
  display:block;margin-top:1px;color:var(--muted);
  font-size:10px;font-weight:500;letter-spacing:.2px;
}
.tag{
  font:10px ui-monospace,monospace;color:var(--muted);border:1px solid var(--line);
  padding:4px 8px;border-radius:99px;white-space:nowrap;
}
.tabs{
  display:flex;gap:4px;margin-left:6px;padding:3px;background:#091520;
  border:1px solid var(--line);border-radius:9px;
}
.analyzer-tab{padding:7px 11px;border-color:transparent;background:transparent;color:var(--muted)}
.analyzer-tab.active{background:#12314a;border-color:#216383;color:var(--cyan)}
.status{margin-left:auto;display:flex;align-items:center;gap:8px;color:var(--muted);white-space:nowrap}
.dot{width:9px;height:9px;border-radius:50%;background:var(--amber);box-shadow:0 0 12px var(--amber)}
.dot.live{background:var(--green);box-shadow:0 0 12px var(--green)}
.panel{
  background:linear-gradient(145deg,#0f1d2a,#0b1621);border:1px solid var(--line);
  border-radius:11px;box-shadow:0 12px 32px #0004;overflow:hidden;
}
.head{
  min-height:42px;display:flex;align-items:center;padding:0 14px;
  border-bottom:1px solid var(--line);font-weight:700;
}
.head small{margin-left:auto;color:var(--muted);font-weight:400;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.connection-panel{
  display:grid;grid-template-columns:auto minmax(270px,440px) auto minmax(250px,1fr);
  align-items:center;gap:12px;padding:10px 14px;margin-bottom:12px;
}
.connection-title{font-weight:750;white-space:nowrap}
.connection-title small{display:block;margin-top:2px;color:var(--muted);font-size:10px;font-weight:500}
.connection-controls{display:flex;gap:7px;min-width:0}
.connection-controls select{flex:1;min-width:0}
.connection-actions{display:flex;gap:7px}
.connection-help{color:var(--muted);font-size:11px;line-height:1.45}
.grid{display:grid;grid-template-columns:minmax(0,1fr) 320px;gap:12px;align-items:start}
.side{display:flex;flex-direction:column;gap:12px;min-width:0}
.toolbar{
  display:flex;gap:6px;padding:9px 12px;border-bottom:1px solid var(--line);
  flex-wrap:wrap;
}
button,select,.filebtn{
  min-height:34px;background:#132537;color:var(--text);border:1px solid #294158;
  border-radius:7px;padding:7px 10px;font-weight:650;cursor:pointer;
}
button:hover,.filebtn:hover{border-color:var(--cyan);color:var(--cyan)}
button.primary{background:#0e7490;border-color:#0891b2;color:white}
button:disabled{opacity:.45;cursor:not-allowed}
.filebtn{display:inline-flex;align-items:center}
.filebtn input{display:none}
.wavewrap{padding:8px 10px 2px;overflow-x:auto}
canvas{
  display:block;width:100%;height:clamp(350px,calc(100vh - 310px),520px);
  min-width:680px;
}
.legend{
  min-height:34px;display:flex;align-items:center;gap:16px;padding:4px 14px 10px;
  color:var(--muted);font-size:11px;overflow:hidden;
}
#cursor{margin-left:auto;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.swatch{display:inline-block;width:18px;height:2px;background:var(--cyan);vertical-align:middle;margin-right:6px}
.trigger{background:var(--red)}
.metrics{display:grid;grid-template-columns:1fr 1fr}
.metric{padding:12px 14px;border-right:1px solid var(--line);border-bottom:1px solid var(--line)}
.metric:nth-child(even){border-right:0}
.metric label{display:block;color:var(--muted);font-size:10px;text-transform:uppercase;letter-spacing:.8px}
.metric b{display:block;font-size:18px;margin-top:4px}
.metric b.cyan{color:var(--cyan)}
.addrline{padding:8px 12px;color:var(--muted);font:10px/1.6 ui-monospace,monospace}
.badge{
  display:inline-block;margin-left:6px;padding:2px 5px;border:1px solid #765d18;
  border-radius:5px;color:var(--amber);font:9px ui-monospace,monospace;vertical-align:2px;
}
.io{padding:11px 12px}
.hint{color:var(--muted);font-size:11px;line-height:1.5}
.barrow{
  display:grid;grid-template-columns:58px 1fr 48px;gap:7px;align-items:center;
  margin:7px 0;font-size:11px;
}
.bar{height:7px;background:#16293a;border-radius:8px;overflow:hidden}
.fill{height:100%;background:linear-gradient(90deg,#0891b2,var(--cyan));border-radius:8px}
.summary-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:12px}
.compare{display:grid;grid-template-columns:repeat(3,1fr);gap:7px}
.comparebox{background:#0a1621;border:1px solid var(--line);padding:9px;border-radius:8px;min-width:0}
.comparebox small{display:block;color:var(--muted);font-size:9px;white-space:nowrap}
.comparebox strong{display:block;font-size:clamp(11px,1.1vw,15px);margin:3px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.comparebox.active{border-color:#16718b}
.speedup{margin:9px 0 7px;padding:7px;text-align:center;border:1px solid #145369;background:#0b2936;border-radius:7px;color:var(--cyan)}
.pulse-seq{font:10px/1.5 ui-monospace,monospace;color:var(--muted);word-break:break-word}
.impltable{width:100%;border-collapse:collapse;font:10px/1.4 ui-monospace,monospace}
.impltable th,.impltable td{padding:5px 3px;border-bottom:1px solid var(--line);text-align:right}
.impltable th:first-child,.impltable td:first-child{text-align:left}
.impltable th{color:var(--muted);font-weight:500}
.implnote{margin-top:8px;color:var(--cyan);font-size:10px;line-height:1.4}
/* Section 2.4 validation card */
.verdict{
  display:flex;align-items:center;gap:9px;padding:11px 13px;
  border-bottom:1px solid var(--line);font-weight:800;letter-spacing:.4px;
}
.verdict.pass{background:#062b21;color:var(--green)}
.verdict.fail{background:#2c1119;color:var(--red)}
.verdict.idle{background:#111f2d;color:var(--muted)}
.verdict small{margin-left:auto;font:10px ui-monospace,monospace;font-weight:500;letter-spacing:0}
.checks{padding:5px 0}
.check{
  display:grid;grid-template-columns:78px 1fr auto;gap:8px;align-items:baseline;
  padding:6px 13px;font-size:11px;
}
.check+.check{border-top:1px solid #16273600}
.check label{color:var(--muted);font-size:10px;text-transform:uppercase;letter-spacing:.6px}
.check span{color:var(--text);font:10px/1.5 ui-monospace,monospace;word-break:break-word}
.check b{font:10px ui-monospace,monospace;padding:2px 6px;border-radius:5px}
.check b.PASS{color:var(--green);background:#062b21}
.check b.FAIL{color:var(--red);background:#2c1119}
.check b.NA{color:var(--muted);background:#16283a}
/* Section 2.2 read-only settings */
.settings{padding:4px 0}
.setrow{
  display:grid;grid-template-columns:104px 1fr auto;gap:8px;align-items:baseline;
  padding:5px 13px;font-size:11px;
}
.setrow label{color:var(--muted);font-size:10px;text-transform:uppercase;letter-spacing:.6px}
.setrow b{font:11px ui-monospace,monospace;color:var(--text)}
.src{font:8px ui-monospace,monospace;padding:2px 5px;border-radius:4px;letter-spacing:.3px}
.src.uart{color:var(--green);background:#062b21}
.src.derived{color:var(--cyan);background:#07293a}
.src.firmware{color:var(--amber);background:#2a1f06}
.readonly-note{
  margin:4px 13px 10px;padding:7px 9px;border:1px solid #765d18;border-radius:6px;
  color:var(--amber);font-size:10px;line-height:1.5;background:#1e1706;
}
/* Section 2.2 data inspector */
.datatable{width:100%;border-collapse:collapse;font:10px/1.5 ui-monospace,monospace}
.datatable td{padding:4px 13px;border-bottom:1px solid #16273a}
.datatable td:first-child{color:var(--muted);width:88px}
.datatable td:last-child{text-align:right;color:var(--text)}
.bits{display:flex;gap:3px;justify-content:flex-end;flex-wrap:wrap}
.bit{
  width:19px;text-align:center;border-radius:4px;padding:2px 0;
  font:9px ui-monospace,monospace;border:1px solid var(--line);
}
.bit.hi{color:#062b21;background:var(--cyan);border-color:var(--cyan);font-weight:700}
.bit.lo{color:var(--muted)}
.presets{display:flex;gap:6px;padding:9px 12px;border-bottom:1px solid var(--line);flex-wrap:wrap}
.presets button{font-size:11px}
button.on{background:#12314a;border-color:#216383;color:var(--cyan)}
.terminal{margin-top:12px}
.terminal pre{
  height:120px;margin:0;padding:11px 14px;overflow:auto;color:#7dd3fc;background:#050b11;
  font:11px/1.45 ui-monospace,SFMono-Regular,monospace;
}
.toast{
  position:fixed;right:20px;bottom:20px;background:#15293a;border:1px solid #2b4961;
  padding:10px 14px;border-radius:8px;opacity:0;transform:translateY(8px);
  transition:.2s;pointer-events:none;z-index:10;
}
.toast.on{opacity:1;transform:none}
@media(max-width:1100px){
  .top{flex-wrap:wrap}
  .status{margin-left:0}
  .tabs{margin-left:auto}
  .connection-panel{grid-template-columns:auto minmax(240px,1fr) auto}
  .connection-help{display:none}
  .grid{grid-template-columns:minmax(0,1fr) 290px}
  canvas{height:400px}
}
@media(max-width:1050px){
  .grid,.summary-grid{grid-template-columns:1fr}
  .side{display:grid;grid-template-columns:repeat(3,minmax(0,1fr))}
}
@media(max-width:820px){
  .shell{padding:8px}
  .top{gap:8px}
  .tag{display:none}
  .tabs{order:3;width:100%;margin-left:0}
  .analyzer-tab{flex:1;padding:7px 5px}
  .status{margin-left:auto;font-size:11px;max-width:65%;overflow:hidden;text-overflow:ellipsis}
  .connection-panel{grid-template-columns:1fr;gap:8px}
  .connection-title small,.connection-help{display:block}
  .connection-actions button{flex:1}
  .grid,.summary-grid{grid-template-columns:1fr}
  .side{display:grid;grid-template-columns:1fr 1fr}
  .side .panel:first-child{grid-column:1/-1}
  canvas{height:360px}
}
@media(max-width:560px){
  .side{display:flex}
  .toolbar button,.toolbar .filebtn{flex:1 1 44%}
  .legend{flex-wrap:wrap}
  #cursor{width:100%;margin-left:0}
  canvas{height:330px;min-width:0}
  .compare{gap:4px}
  .comparebox{padding:6px 5px}
  .comparebox .hint{font-size:9px}
}
@media(min-width:1051px) and (max-height:760px){
  .head{min-height:38px}
  .side{gap:8px}
  .metric{padding:8px 12px}
  .metric b{font-size:16px}
  .io{padding:8px 10px}
  .barrow{margin:4px 0}
  .addrline{padding:6px 10px}
  canvas{height:350px}
}
</style></head><body><div class="shell">
<header class="top">
 <div class="brand"><span>EdgeScope</span>-Lite<small>8-Channel 100 MS/s Standalone Logic Analyzer</small></div>
 <div class="tag" id="analyzerTag">CPU POLLING REFERENCE</div>
 <nav class="tabs" aria-label="분석기 선택">
  <button class="analyzer-tab active" data-analyzer="cpu_polling">A · CPU Polling</button>
  <button class="analyzer-tab" data-analyzer="edgescope_lite">B · EdgeScope-Lite</button>
  <button class="analyzer-tab" data-analyzer="vivado_ila">C · Vivado ILA</button>
 </nav>
 <div class="status"><i class="dot" id="dot"></i><span id="status">DEMO · RECORDED UART</span></div>
</header>
<section class="panel connection-panel" aria-label="Basys3 연결">
 <div class="connection-title">Basys3 연결<small>UART 9600 baud · 8-N-1</small></div>
 <div class="connection-controls">
  <select id="ports" aria-label="UART 포트"><option>포트 검색 중…</option></select>
  <button id="refresh" title="포트 새로고침">↻ 새로고침</button>
 </div>
 <div class="connection-actions">
  <button class="primary" id="connect">보드 연결</button>
  <button id="demo">데모 모드</button>
 </div>
 <div class="connection-help">B는 연결 후 Benchmark로 통신을 확인하세요. C 캡처는 ILA ARM 완료 후 자동으로 UART 자극을 전송합니다.</div>
</section>
<div class="grid">
 <section class="panel trace-panel"><div class="head">8-Channel Logic Trace <small id="captureLabel">—</small></div>
  <div class="presets" id="presets" aria-label="촬영 Demo Profile"></div>
  <div class="toolbar">
   <button class="primary" data-cmd="r">Rising 캡처</button><button data-cmd="f">Falling 캡처</button>
   <button data-cmd="p">Pattern 캡처</button><button data-cmd="h">Pattern Hold</button>
   <button data-cmd="b">Benchmark</button><button data-cmd="s">Pulse Stress</button><button data-cmd="z">Zero Mask</button>
   <button id="zoomTrigger" title="Trigger 주변 [448,576) 확대">Trigger 확대</button>
   <button id="savePng">PNG 저장</button><button id="saveCsv">CSV 저장</button>
   <label class="filebtn">UART/CSV 불러오기<input id="captureFile" type="file" accept=".log,.txt,.csv,text/plain,text/csv"></label>
  </div><div class="wavewrap"><canvas id="wave"></canvas></div>
  <div class="legend"><span><i class="swatch"></i>Logic High / Low</span><span id="triggerLegend"><i class="swatch trigger"></i>Trigger @ 512</span><span id="cursor">파형 위에서 위치를 확인하세요</span></div>
 </section>
 <aside class="side">
  <section class="panel"><div class="verdict idle" id="verdict">CAPTURE 대기<small id="verdictNote"></small></div>
   <div class="checks" id="checks"><div class="hint" style="padding:8px 13px">캡처를 실행하면 자동 검증 결과가 표시됩니다.</div></div></section>
  <section class="panel"><div class="head">Capture Metrics <small id="evidence"></small></div><div class="metrics">
   <div class="metric"><label>Trigger</label><b class="cyan" id="mode">—</b></div>
   <div class="metric"><label>Samples</label><b id="samples">—</b></div>
   <div class="metric"><label id="rateLabel">Throughput</label><b id="rate">—</b></div>
   <div class="metric"><label>Trigger Index</label><b id="trigIndex">—</b></div>
  </div><div class="addrline" id="addresses">START — · TRIGGER — · WRITE —</div></section>
  <section class="panel"><div class="head">Capture / Trigger Settings <small>read-only</small></div>
   <div class="settings" id="settings"></div><div id="readonlyNote"></div></section>
  <section class="panel"><div class="head">Data <small id="dataHint">파형을 클릭하세요</small></div>
   <table class="datatable"><tbody id="dataTable"></tbody></table></section>
  <section class="panel"><div class="head" id="benchTitle">Polling Benchmark</div><div class="io" id="bench"></div></section>
  <section class="panel"><div class="head">Pulse Detection</div><div class="io" id="pulse"></div></section>
 </aside>
</div>
<div class="summary-grid">
 <section class="panel"><div class="head">A/B/C Capture Comparison</div><div class="io">
  <div class="compare"><div class="comparebox" id="compareA"><small>A · CPU polling</small><strong>1.67 MS/s</strong><span class="hint">실측 최저 처리량</span></div>
  <div class="comparebox" id="compareB"><small>B · EdgeScope-Lite</small><strong>100.00 MS/s</strong><span class="hint">sample clock <i class="badge">DEMO</i></span></div>
  <div class="comparebox" id="compareC"><small>C · Vivado ILA</small><strong>100.00 MS/s</strong><span class="hint">sample clock <i class="badge">DEMO</i></span></div></div>
  <div class="speedup" id="speedup">B/C · 60.0× faster sampling</div><div class="pulse-seq" id="comparePulse"></div>
 </div></section>
 <section class="panel"><div class="head">Implementation Comparison <small>Vivado reports</small></div><div class="io" id="implementation"><div class="hint">보고서 읽는 중…</div></div></section>
</div>
<section class="panel terminal"><div class="head">UART Activity <small>최근 수신 데이터</small></div><pre id="term"></pre></section>
</div><div class="toast" id="toast"></div>
<script>
let demoData=null, rootData=null, activeAnalyzer='cpu_polling', captureIndices={cpu_polling:0,edgescope_lite:0,vivado_ila:0};
let live=false, poller=null, liveDetectedAnalyzer=null, lastIlaStatus='idle', lastIlaError=null;
let sourceMode='demo',pollEpoch=0,pollBusy=false,connectionProbeTimer=null,commandPending=null;
let profiles={},frozenSpec={depth:1024,trigger_index:512},activePreset=null;
let zoomed=false,selectedIndex=null;
const ZOOM_SPAN=[448,576];
const analyzerKeys=['cpu_polling','edgescope_lite','vivado_ila'];
const requestedValue=new URLSearchParams(location.search).get('analyzer');
const requestedAnalyzer=analyzerKeys.includes(requestedValue)?requestedValue:null;
const $=id=>document.getElementById(id), esc=s=>String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
function toast(s){$('toast').textContent=s;$('toast').classList.add('on');setTimeout(()=>$('toast').classList.remove('on'),1800)}
async function api(path,options){let r=await fetch(path,options);let j=await r.json();if(!r.ok)throw Error(j.error||r.statusText);return j}
function fmt(n){return Number.isFinite(Number(n))?Number(n).toLocaleString('ko-KR'):'—'}
function rateText(n){return n?`${(Number(n)/1e6).toFixed(2)} MS/s`:'—'}
function hex8(v){return '0x'+Number(v).toString(16).padStart(2,'0').toUpperCase()}
function periodText(ns){
 if(!Number.isFinite(ns)||ns<=0)return '—';
 return ns<1000?`${ns%1?ns.toFixed(2):ns} ns`:`${(ns/1000).toFixed(2)} µs`
}
function timeText(seconds){
 let ns=seconds*1e9,sign=ns<0?'-':'+',abs=Math.abs(ns);
 return abs<1000?`${sign}${abs.toFixed(0)} ns`:`${sign}${(abs/1000).toFixed(2)} µs`
}
/* Section 2.4 validation card. */
function renderValidation(c,d){
 let receiving=d?.receiving;
 if(receiving){
  $('verdict').className='verdict idle';
  $('verdict').innerHTML=`CAPTURE 수신 중<small>${fmt(receiving.received)} / ${fmt(receiving.expected)}</small>`;
  $('checks').innerHTML=`<div class="hint" style="padding:8px 13px">${esc(receiving.mode)} 캡처를 9,600 baud로 수신하고 있습니다. 1,024 Sample 전송에는 약 11초가 걸립니다.</div>`;
  return
 }
 let v=c?.validation;
 if(!v){
  $('verdict').className='verdict idle';$('verdict').innerHTML='CAPTURE 대기<small></small>';
  $('checks').innerHTML='<div class="hint" style="padding:8px 13px">캡처를 실행하면 자동 검증 결과가 표시됩니다.</div>';
  return
 }
 let simulated=d?.simulated?'DEMO · 예상 데이터':'';
 $('verdict').className='verdict '+(v.valid?'pass':'fail');
 $('verdict').innerHTML=(v.valid?'CAPTURE VALID':'CAPTURE INVALID')+`<small>${esc(simulated)}</small>`;
 $('checks').innerHTML=v.checks.map(k=>
  `<div class="check"><label>${esc(k.name)}</label><span>${esc(k.detail)}</span><b class="${k.state==='N/A'?'NA':k.state}">${k.state}</b></div>`
 ).join('')
}
/* Section 2.2 settings, read-only per section 2.5. */
function renderSettings(c){
 if(!c?.config){$('settings').innerHTML='<div class="hint" style="padding:8px 13px">—</div>';$('readonlyNote').innerHTML='';return}
 let g=c.config,s=g.sources||{},depth=c.samples.length;
 let tag=key=>{let src=s[key];return src?`<i class="src ${src}">${{uart:'UART',derived:'DERIVED',firmware:'FW FIXED'}[src]}</i>`:''};
 let rows=g.hardware===false
  /* A is software polling: no sample-clock divider, no fixed sample period. */
  ? [['Observation Rate',rateText(g.sample_hz),null],
     ['Sample Divider','해당 없음 · CPU Polling',null]]
  : [['Sample Divider',`1 / ${g.divider}`,'divider'],
     ['Sample Rate',rateText(g.sample_hz),'divider'],
     ['Sample Period',periodText(g.sample_period_ns),'divider'],
     ['Channel Mask',hex8(g.channel_mask),'channel_mask']];
 rows=rows.concat([
  ['Capture Depth',fmt(depth)+' Samples',null],
  ['Trigger Mode',c.mode,null],
  ['Trigger Index',String(c.trigger_index),null],
 ]);
 if(c.mode==='RISING'||c.mode==='FALLING')rows.push(['Edge Channel','CH'+g.trigger_channel,'trigger_channel']);
 if(String(c.mode).startsWith('PATTERN')){
  rows.push(['Pattern Value',hex8(g.pattern_value),'pattern_value']);
  rows.push(['Pattern Mask',hex8(g.pattern_mask),'pattern_mask'])
 }
 $('settings').innerHTML=rows.map(([label,value,key])=>
  `<div class="setrow"><label>${esc(label)}</label><b>${esc(value)}</b>${key?tag(key):''}</div>`
 ).join('');
 let assumed=Object.entries(s).filter(([,src])=>src==='firmware').length;
 $('readonlyNote').innerHTML=assumed
  ? `<div class="readonly-note">이 Firmware는 PC→보드 설정 명령을 지원하지 않습니다. <b>FW FIXED</b> 항목은 Firmware에 고정된 값이며 GUI에서 변경할 수 없습니다.</div>`
  : ''
}
/* Section 2.2 data inspector. */
function renderData(c,index){
 if(!c||index===null||index===undefined||index<0||index>=c.samples.length){
  $('dataTable').innerHTML='<tr><td>Index</td><td>—</td></tr>';
  $('dataHint').textContent='파형을 클릭하세요';return
 }
 let value=c.samples[index],hz=c.config?.sample_hz||c.sample_hz;
 let bits=[7,6,5,4,3,2,1,0].map(ch=>{let on=(value>>ch)&1;return `<i class="bit ${on?'hi':'lo'}" title="CH${ch}">${on}</i>`}).join('');
 $('dataHint').textContent=`Index ${index}`;
 $('dataTable').innerHTML=
  `<tr><td>Index</td><td>${index}</td></tr>`+
  `<tr><td>Time</td><td>${hz?timeText((index-c.trigger_index)/hz):(index-c.trigger_index)+' samples'}</td></tr>`+
  `<tr><td>Hex</td><td>${hex8(value)}</td></tr>`+
  `<tr><td>Binary</td><td>${value.toString(2).padStart(8,'0')}</td></tr>`+
  `<tr><td>CH7…CH0</td><td><div class="bits">${bits}</div></td></tr>`
}
/* Section 2.3 shooting presets. */
function renderPresets(){
 let keys=Object.keys(profiles);
 if(!keys.length){$('presets').innerHTML='';return}
 $('presets').innerHTML=keys.map(key=>{
  let p=profiles[key];
  return `<button data-preset="${key}" class="${activePreset===key?'on':''}" title="${esc(p.note||p.label)}">${esc(p.label)}${p.firmware_supported?'':' <i class="badge">FW 제한</i>'}</button>`
 }).join('');
 document.querySelectorAll('[data-preset]').forEach(b=>b.onclick=()=>runPreset(b.dataset.preset))
}
function selected(root,key=activeAnalyzer){return root?.datasets?.[key]||null}
function isHardware(key=activeAnalyzer){return key==='edgescope_lite'||key==='vivado_ila'}
function analyzerLabel(key){return {cpu_polling:'A · CPU Polling',edgescope_lite:'B · EdgeScope-Lite',vivado_ila:'C · Vivado ILA'}[key]||key}
function representativeRate(d){
 if(!d)return 0;if(d.representative)return d.representative;
 let rates=(d.captures||[]).map(c=>c.sample_hz||c.rate||0).filter(Boolean);
 return rates.length?Math.min(...rates):0
}
function selectAnalyzer(key, renderNow=true){
 if(!analyzerKeys.includes(key))key='cpu_polling';
 if(activeAnalyzer!==key)selectedIndex=null;
 activeAnalyzer=key;
 document.querySelectorAll('[data-analyzer]').forEach(b=>b.classList.toggle('active',b.dataset.analyzer===key));
 $('analyzerTag').textContent={cpu_polling:'CPU POLLING REFERENCE',edgescope_lite:'EDGESCOPE-LITE REFERENCE',vivado_ila:'VIVADO ILA REFERENCE'}[key];
 if(sourceMode==='demo')$('status').textContent=key==='cpu_polling'?'DEMO · RECORDED UART':`DEMO · SYNTHETIC ${key==='edgescope_lite'?'B':'C'} PREVIEW`;
 if(renderNow&&rootData)render(rootData);
}
function render(root,preferred){
 rootData=root;let d=selected(root);
 if(!d)return;
 let index=captureIndices[activeAnalyzer]||0;
 if(sourceMode==='live'&&d.captures.length)index=d.captures.length-1;
 if(preferred){for(let n=d.captures.length-1;n>=0;n--){if(d.captures[n].mode===preferred){index=n;break}}}
 if(index>=d.captures.length)index=0;captureIndices[activeAnalyzer]=index;
 let c=d.captures[index];
 let warning=(d.warnings||[]).slice(-1)[0];
 $('evidence').innerHTML=(d.simulated?'<span class="badge">DEMO · 예상</span>':esc(d.evidence||'LIVE UART'))+(warning?' <span class="badge">DATA CHECK</span>':'');
 $('rateLabel').textContent=isHardware()?'Sample Rate':'Throughput';
 $('benchTitle').textContent=activeAnalyzer==='vivado_ila'?'ILA Sampling':activeAnalyzer==='edgescope_lite'?'Hardware Sampling':'Polling Benchmark';
 renderValidation(c,d);renderSettings(c);
 if(c){
  let shownRate=isHardware()?(c.sample_hz||c.rate):c.rate;
  $('mode').textContent=c.mode;$('samples').textContent=fmt(c.samples.length);$('rate').textContent=rateText(shownRate);
  $('trigIndex').textContent=c.trigger_index;$('triggerLegend').innerHTML=`<i class="swatch trigger"></i>Trigger @ ${c.trigger_index}`;
  let timing=isHardware()?` · ${rateText(c.sample_hz)}`:'';
  $('captureLabel').textContent=`${c.mode} · ${c.samples.length} samples · PRE ${c.trigger_index} / POST ${c.samples.length-c.trigger_index}${timing}`;
  let addr=v=>v===null||v===undefined?'—':fmt(v);
  $('addresses').textContent=activeAnalyzer==='vivado_ila'?`ILA BUFFER 0–${c.samples.length-1} · TRIGGER ${c.trigger_index} · JTAG CSV`:`START ${addr(c.start_addr)} · TRIGGER ${addr(c.trigger_addr)} · WRITE ${addr(c.write_addr)}`;
  if(selectedIndex===null)selectedIndex=c.trigger_index;
  if(selectedIndex>=c.samples.length)selectedIndex=c.samples.length-1;
  renderData(c,selectedIndex);draw(c)
 } else {
  $('mode').textContent='—';$('samples').textContent='—';$('rate').textContent=isHardware()&&d.ready?'100.00 MS/s':'—';
  $('trigIndex').textContent='—';$('captureLabel').textContent=warning?warning:(d.receiving?'캡처 수신 중…':'캡처 실행 대기 중');$('addresses').textContent='START — · TRIGGER — · WRITE —';
  renderData(null,null);clearWave()
 }
 let maxRate=Math.max(1,...d.benchmarks.map(x=>x.rate));
 $('bench').innerHTML=(d.benchmarks.length?d.benchmarks.map(x=>`<div class="barrow"><span>${esc(x.mode)}</span><div class="bar"><div class="fill" style="width:${x.rate/maxRate*100}%"></div></div><b>${(x.rate/1e6).toFixed(2)}M</b></div>`).join(''):'<div class="hint">Benchmark 실행 대기 중</div>')+
 (d.representative?`<div class="hint" style="margin-top:10px">${isHardware()?'캡처 sample rate':'대표 최저 처리량'} <b style="color:var(--cyan)">${rateText(d.representative)}</b>${d.simulated?' <i class="badge">DEMO</i>':''}</div>`:'');
 $('pulse').innerHTML=d.pulses.length?d.pulses.map(x=>`<div class="barrow"><span>${fmt(x.cycles)} cyc</span><div class="bar"><div class="fill" style="width:${x.trials?x.detected/x.trials*100:0}%;background:${x.detected?'var(--green)':'var(--red)'}"></div></div><b>${x.detected}/${x.trials}</b></div>`).join('')+
 (d.pulses.some(x=>x.expected)?`<div class="hint">${activeAnalyzer==='vivado_ila'?'C Vivado ILA':'B EdgeScope-Lite'} 결과는 100 MHz 동기 캡처의 DEMO 예상값이며 보드 실측값이 아닙니다.</div>`:''):'<div class="hint">Pulse Stress 실행 대기 중</div>';
 renderComparison(root)
}
function renderComparison(root){
 let a=selected(root,'cpu_polling'),b=selected(root,'edgescope_lite'),c=selected(root,'vivado_ila'),ar=representativeRate(a),br=representativeRate(b),cr=representativeRate(c);
 $('compareA').classList.toggle('active',activeAnalyzer==='cpu_polling');$('compareB').classList.toggle('active',activeAnalyzer==='edgescope_lite');$('compareC').classList.toggle('active',activeAnalyzer==='vivado_ila');
 $('compareA').innerHTML=`<small>A · CPU polling</small><strong>${rateText(ar)}</strong><span class="hint">${ar?(a?.simulated?'DEMO':'실측 최저 처리량'):'데이터 대기'}</span>`;
 $('compareB').innerHTML=`<small>B · EdgeScope-Lite</small><strong>${rateText(br)}</strong><span class="hint">${br?'sample clock':'데이터 대기'}${b?.simulated?' <i class="badge">DEMO</i>':''}</span>`;
 $('compareC').innerHTML=`<small>C · Vivado ILA</small><strong>${rateText(cr)}</strong><span class="hint">${cr?'sample clock':'데이터 대기'}${c?.simulated?' <i class="badge">DEMO</i>':''}</span>`;
 $('speedup').textContent=ar&&(br||cr)?`B ${br?(br/ar).toFixed(1):'—'}× · C ${cr?(cr/ar).toFixed(1):'—'}× vs A`:'A/B/C 데이터 대기 중';
 let pulse=d=>(d?.pulses||[]).map(x=>x.detected).join(' / ')||'—';
 let evidence=d=>!d||!(d.ready||d.captures.length||d.benchmarks.length||d.pulses.length)?'데이터 없음':d.simulated?'DEMO 예상':'실제';
 $('comparePulse').innerHTML=`Pulse hit (1 → 100000 cyc)<br>A ${evidence(a)} · ${pulse(a)}<br>B ${evidence(b)} · ${pulse(b)}<br>C ${evidence(c)} · ${pulse(c)}`;
}
function renderImplementation(payload){
 let builds=payload.builds||{},order=[['cpu_polling','A'],['edgescope_lite','B'],['vivado_ila','C']];
 let numeric=value=>value!==null&&value!==undefined&&value!==''&&Number.isFinite(Number(value));
 let cell=(value,digits=0)=>numeric(value)?Number(value).toFixed(digits):'—';
 let rows=order.map(([key,label])=>{let d=builds[key]||{};return `<tr><td>${label}</td><td>${cell(d.luts)}</td><td>${cell(d.registers)}</td><td>${cell(d.bram_tiles,1)}</td><td>${cell(d.wns_ns,3)}</td></tr>`}).join('');
 let b=builds.edgescope_lite||{},c=builds.vivado_ila||{},pct=(bv,cv)=>numeric(bv)&&numeric(cv)&&Number(cv)>0?((Number(cv)-Number(bv))/Number(cv)*100).toFixed(1):'—';
 let bramDelta=numeric(b.bram_tiles)&&numeric(c.bram_tiles)?Number(b.bram_tiles)-Number(c.bram_tiles):NaN,bramText=Number.isFinite(bramDelta)?(bramDelta===0?'BRAM 동일':`B가 BRAM ${Math.abs(bramDelta).toFixed(1)} tile ${bramDelta>0?'더 사용':'덜 사용'}`):'BRAM 비교 대기';
 $('implementation').innerHTML=`<table class="impltable"><thead><tr><th>Build</th><th>LUT</th><th>FF</th><th>BRAM</th><th>WNS</th></tr></thead><tbody>${rows}</tbody></table><div class="implnote">B vs C · LUT ${pct(b.luts,c.luts)}% 절감 · FF ${pct(b.registers,c.registers)}% 절감 · ${bramText}<br>A는 baseline이며 공식 절감률에 포함하지 않습니다.</div>`;
}
async function loadImplementation(){
 try{renderImplementation(await api('/api/implementation'))}catch(e){$('implementation').innerHTML=`<div class="hint">${esc(e.message)}</div>`}
}
function waveHeight(){
 let height=Math.round($('wave').getBoundingClientRect().height);
 return Math.max(300,height||420)
}
function clearWave(){
 let cv=$('wave'),rect=cv.getBoundingClientRect(),ratio=devicePixelRatio||1,h=waveHeight();cv.width=rect.width*ratio;cv.height=h*ratio;
 cv.onpointermove=null;cv.onpointerleave=null;$('cursor').textContent='파형 위에서 위치를 확인하세요';
 let x=cv.getContext('2d');x.scale(ratio,ratio);x.fillStyle='#09131d';x.fillRect(0,0,rect.width,h);x.fillStyle='#8298aa';x.textAlign='center';x.font='13px ui-monospace';x.fillText('CAPTURE DATA WAITING',rect.width/2,h/2)
}
/* Visible logical index window: whole capture, or the section 2.2 trigger zoom. */
function viewWindow(c){
 if(!zoomed)return [0,c.samples.length];
 let start=Math.max(0,Math.min(ZOOM_SPAN[0],c.samples.length-1));
 return [start,Math.min(ZOOM_SPAN[1],c.samples.length)]
}
function draw(c){
 let cv=$('wave'),rect=cv.getBoundingClientRect(),ratio=devicePixelRatio||1,h=waveHeight();cv.width=rect.width*ratio;cv.height=h*ratio;
 let x=cv.getContext('2d');x.scale(ratio,ratio);let w=rect.width,left=54,right=14,top=12,bottom=38,row=(h-top-bottom)/8,plot=w-left-right;
 let [v0,v1]=viewWindow(c),denom=Math.max(1,v1-1-v0),hz=c.config?.sample_hz||c.sample_hz;
 let px=i=>left+(i-v0)/denom*plot;
 x.fillStyle='#09131d';x.fillRect(0,0,w,h);
 /* Section 2.2: pre/post background separation. */
 let tx=px(c.trigger_index),plotTop=top-6,plotBottom=h-bottom+row*.1;
 let clamp=v=>Math.max(left,Math.min(w-right,v));
 if(c.trigger_index>v0){x.fillStyle='#081521';x.fillRect(left,plotTop,clamp(tx)-left,plotBottom-plotTop)}
 if(c.trigger_index<v1){x.fillStyle='#152032';x.fillRect(clamp(tx),plotTop,w-right-clamp(tx),plotBottom-plotTop)}
 x.font='11px ui-monospace';x.textAlign='right';
 for(let ch=7;ch>=0;ch--){let ri=7-ch,y=top+ri*row,high=y+row*.18,low=y+row*.68;x.strokeStyle='#1b3042';x.beginPath();x.moveTo(left,y+row*.74);x.lineTo(w-right,y+row*.74);x.stroke();
  x.fillStyle='#8298aa';x.fillText('CH'+ch,left-10,y+row*.5);x.strokeStyle=ch===0?'#22d3ee':'#38bdf8';x.lineWidth=1.4;x.beginPath();
  let previousY=null;
  for(let i=v0;i<v1;i++){let cx=px(i),py=(c.samples[i]>>ch)&1?high:low;if(i===v0)x.moveTo(cx,py);else{x.lineTo(cx,previousY);x.lineTo(cx,py)}previousY=py}
  x.stroke()}
 /* Trigger cursor sits on the leading boundary of logical index 512, so the
    511->512 transition and t=0 land on exactly the same x. */
 if(c.trigger_index>=v0&&c.trigger_index<v1){
  x.strokeStyle='#fb7185';x.lineWidth=1.5;x.beginPath();x.moveTo(tx,4);x.lineTo(tx,h-20);x.stroke();
  x.fillStyle='#fb7185';x.textAlign='center';x.fillText('TRIGGER',tx,h-20)
 }
 /* Selected-sample marker for the Data panel. */
 if(selectedIndex!==null&&selectedIndex>=v0&&selectedIndex<v1){
  let sx=px(selectedIndex);x.strokeStyle='#fbbf24';x.lineWidth=1;x.setLineDash([3,3]);
  x.beginPath();x.moveTo(sx,plotTop);x.lineTo(sx,h-20);x.stroke();x.setLineDash([])
 }
 x.fillStyle='#8298aa';
 if(hz){
  x.textAlign='left';x.fillText(timeText((v0-c.trigger_index)/hz),left,h-6);
  x.textAlign='right';x.fillText(timeText((v1-1-c.trigger_index)/hz),w-right,h-6);
  if(c.trigger_index>=v0&&c.trigger_index<v1){x.textAlign='center';x.fillText('0 ns',tx,h-6)}
 }else{
  x.textAlign='left';x.fillText(`index ${v0}`,left,h-6);
  x.textAlign='right';x.fillText(`index ${v1-1}`,w-right,h-6)
 }
 x.fillStyle='#64798c';x.font='10px ui-monospace';
 if(c.trigger_index-v0>12){x.textAlign='center';x.fillText('PRE-TRIGGER',(left+clamp(tx))/2,top-1)}
 if(v1-c.trigger_index>12){x.textAlign='center';x.fillText('POST-TRIGGER',(clamp(tx)+w-right)/2,top-1)}
 let indexAt=e=>{let r=cv.getBoundingClientRect();
  return Math.max(v0,Math.min(v1-1,Math.round((e.clientX-r.left-left)/(r.width-left-right)*denom)+v0))};
 cv.onpointermove=e=>{let idx=indexAt(e),offset=idx-c.trigger_index;
  let time=hz?` · ${timeText(offset/hz)}`:` · ${offset} samples`;
  $('cursor').textContent=`Index ${idx} · ${hex8(c.samples[idx])}${time}`};
 cv.onpointerleave=()=>{$('cursor').textContent='파형 위에서 위치를 확인하세요'};
 cv.onclick=e=>{selectedIndex=indexAt(e);renderData(c,selectedIndex);draw(c)};
 cv.style.cursor='crosshair'
}
function stopPolling(){
 pollEpoch++;clearInterval(poller);poller=null;pollBusy=false;clearTimeout(connectionProbeTimer);connectionProbeTimer=null
}
function syncCommandButtons(){
 document.querySelectorAll('[data-cmd]').forEach(button=>{
  let waiting=sourceMode==='live'&&live&&!liveDetectedAnalyzer&&button.dataset.cmd!=='b';
  button.disabled=Boolean(commandPending)||waiting||(sourceMode==='live'&&!live)
 })
}
function setDisconnected(message){
 stopPolling();live=false;liveDetectedAnalyzer=null;commandPending=null;$('dot').className='dot';$('connect').textContent='보드 연결';
 $('status').textContent=message||'보드 연결 끊김';syncCommandButtons()
}
function armProbeTimer(port,epoch){
 clearTimeout(connectionProbeTimer);
 connectionProbeTimer=setTimeout(()=>{
  if(live&&epoch===pollEpoch&&!liveDetectedAnalyzer){
   $('status').textContent=`UART 열림 · 보드 응답 없음 · ${port}`;
   toast('보드 비트스트림과 UART 포트를 확인하세요')
  }
 },5000)
}
async function loadDemo(preferred='RISING'){
 let initial=rootData&&analyzerKeys.includes(activeAnalyzer)?activeAnalyzer:(requestedAnalyzer||'cpu_polling');
 stopPolling();let epoch=pollEpoch;sourceMode='demo';live=false;liveDetectedAnalyzer=null;commandPending=null;$('dot').className='dot';$('connect').textContent='보드 연결';syncCommandButtons();
 let j=await api('/api/demo');if(epoch!==pollEpoch)return;
 demoData=j.data;rootData=demoData;
 $('term').textContent='A는 저장된 Basys3 실측 UART 로그입니다.\nB와 C는 동일 파형을 100 MHz 하드웨어 캡처 형식으로 변환한 DEMO이며 실측값이 아닙니다.';
 selectAnalyzer(initial,false);render(demoData,preferred)
}
async function refreshPorts(){
 let p=$('ports'),previous=p.value,j=await api('/api/ports');
 p.innerHTML=j.ports.length?j.ports.map(x=>`<option>${esc(x)}</option>`).join(''):'<option value="">감지된 Basys3 UART 없음</option>';
 if(j.ports.includes(previous))p.value=previous
}
async function disconnectBoard(showToast=true){
 stopPolling();sourceMode='demo';live=false;liveDetectedAnalyzer=null;commandPending=null;
 try{await api('/api/disconnect',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})}catch(e){}
 $('dot').className='dot';$('connect').textContent='보드 연결';syncCommandButtons();
 if(showToast)toast('보드 연결을 해제했습니다')
}
async function connect(){
 if(live){await disconnectBoard();await loadDemo();return}
 let p=$('ports').value;if(!p)return toast('Basys3 UART 포트가 없습니다');
 stopPolling();let epoch=pollEpoch;
 try{
  await api('/api/connect',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({port:p})});
  if(epoch!==pollEpoch){await api('/api/disconnect',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});return}
  sourceMode='live';live=true;liveDetectedAnalyzer=null;commandPending=null;$('dot').className='dot';$('connect').textContent='연결 취소';
  $('status').textContent='UART 연결됨 · 보드 응답 확인 중 · '+p;$('term').textContent='보드 응답 확인 중…';syncCommandButtons();
  let j=await api('/api/state');if(epoch!==pollEpoch)return;rootData=j.data;render(j.data);
  poller=setInterval(()=>poll(epoch),500);armProbeTimer(p,epoch);
  await api('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command:'b'})});
  poll(epoch);toast('UART 연결 · 보드 응답 확인 중')
 }catch(e){setDisconnected('연결 실패');toast(e.message)}
}
function completePending(data){
 if(!commandPending)return;
 let d=selected(data,commandPending.analyzer),done=false;
 if(!d)return;
 if(commandPending.kind==='capture')done=d.captures.length>commandPending.before;
 else if(commandPending.kind==='benchmark')done=d.benchmarks.length>commandPending.before;
 else if(commandPending.kind==='pulse')done=d.pulses.length>commandPending.before;
 else if(commandPending.kind==='zero')done=d.zero_mask_tests>commandPending.before;
 if(done){
  let label=commandPending.label;commandPending=null;selectedIndex=null;syncCommandButtons();toast(label+' 완료')
 }else if(Date.now()-commandPending.started>commandPending.timeout){
  commandPending=null;syncCommandButtons();toast('명령 응답 시간이 초과되었습니다')
 }
}
async function poll(epoch=pollEpoch){
 if(!live||epoch!==pollEpoch||pollBusy)return;
 pollBusy=true;
 try{
  let [j,ila]=await Promise.all([api('/api/state'),api('/api/ila/status')]);
  if(!live||epoch!==pollEpoch)return;
  if(!j.connected){let message=j.error?`UART 오류 · ${j.error}`:'보드 연결 끊김';setDisconnected(message);toast(message);return}
  if(ila.data?.datasets?.vivado_ila)j.data.datasets.vivado_ila=ila.data.datasets.vivado_ila;
  let terminalText=j.transcript_tail||'보드 응답 대기 중…';
  if(activeAnalyzer==='vivado_ila'&&ila.output_tail)terminalText+=`\n\n--- VIVADO ILA ---\n${ila.output_tail}`;
  $('term').textContent=terminalText;$('term').scrollTop=$('term').scrollHeight;
  let detected=analyzerKeys.includes(j.data.active_analyzer)?j.data.active_analyzer:null;
  if(detected&&detected!==liveDetectedAnalyzer){
   let firstDetection=!liveDetectedAnalyzer;liveDetectedAnalyzer=detected;clearTimeout(connectionProbeTimer);$('dot').className='dot live';$('connect').textContent='연결 해제';
   if(firstDetection)selectAnalyzer(detected,false);syncCommandButtons();toast(`${analyzerLabel(detected)} 응답 확인`)
  }
  rootData=j.data;render(j.data);completePending(j.data);
  if(ila.status==='arming'||ila.status==='capturing')$('status').textContent=`LIVE · C · ${ila.status==='arming'?'ILA ARMING':'CAPTURING'} · ${j.port||''}`;
  else if(commandPending)$('status').textContent=`LIVE · ${analyzerLabel(commandPending.analyzer)} · ${commandPending.label} 진행 중`;
  else if(detected)$('status').textContent=`LIVE · ${analyzerLabel(detected)} · ${j.port||''}`;
  if(ila.status==='complete'&&lastIlaStatus!=='complete'){
   if(commandPending?.kind==='ila'){commandPending=null;syncCommandButtons()}
   $('status').textContent=`LIVE · C · MEASURED CSV · ${j.port||''}`;toast('Vivado ILA 캡처 완료')
  }
  if(ila.status==='error'&&ila.error!==lastIlaError){
   if(commandPending?.kind==='ila'){commandPending=null;syncCommandButtons()}
   lastIlaError=ila.error;$('status').textContent='C · ILA ERROR';toast(ila.error)
  }
  lastIlaStatus=ila.status
 }catch(e){if(live&&epoch===pollEpoch)toast(e.message)}
 finally{pollBusy=false}
}
document.querySelectorAll('[data-analyzer]').forEach(b=>b.onclick=()=>selectAnalyzer(b.dataset.analyzer));
document.querySelectorAll('[data-cmd]').forEach(b=>b.onclick=async()=>{
 let cmd=b.dataset.cmd,map={r:'RISING',f:'FALLING',p:'PATTERN',h:'PATTERN'},wanted=cmd==='h'?'PATTERN HOLD':map[cmd];
 if(sourceMode==='file'){
  let d=selected(rootData);
  if(wanted&&d?.captures?.some(c=>c.mode===wanted)){render(rootData,wanted);toast(wanted+' 파일 캡처 표시')}
  else toast('불러온 파일에 해당 결과가 없습니다');
  return
 }
 if(sourceMode==='live'){
  if(!live)return toast('보드를 다시 연결하세요');
  if(!liveDetectedAnalyzer){
   if(cmd!=='b')return toast('먼저 보드 응답 확인을 기다리세요');
   try{await api('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command:'b'})});armProbeTimer($('ports').value,pollEpoch);toast('보드 응답을 다시 확인합니다')}catch(e){toast(e.message)}
   return
  }
  let target=liveDetectedAnalyzer;if(activeAnalyzer!==target)selectAnalyzer(target);
  try{
   if(target==='vivado_ila'&&wanted){
   await api('/api/ila/capture',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({mode:wanted,program:false})});
    commandPending={analyzer:target,kind:'ila',before:0,label:`${wanted} ILA 캡처`,started:Date.now(),timeout:120000};syncCommandButtons();
    lastIlaStatus='arming';lastIlaError=null;$('status').textContent='LIVE · C · ILA ARMING';toast(`C ${wanted} 캡처 준비`)
   }else if(target==='vivado_ila'){
    if(cmd==='b'){render(rootData);toast('C sample clock: 100.00 MS/s')}
    else toast('C Pulse/Zero-mask 자동 실측은 전용 ILA re-arm flow가 필요합니다')
   }else{
    let d=selected(rootData,target),kind=wanted?'capture':cmd==='b'?'benchmark':cmd==='s'?'pulse':'zero';
    let before=kind==='capture'?d.captures.length:kind==='benchmark'?d.benchmarks.length:kind==='pulse'?d.pulses.length:d.zero_mask_tests;
    commandPending={analyzer:target,kind,before,label:wanted?`${wanted} 캡처`:cmd==='b'?'Benchmark':cmd==='s'?'Pulse Stress':'Zero Mask',started:Date.now(),timeout:kind==='capture'?30000:kind==='pulse'?120000:15000};
    syncCommandButtons();
    try{await api('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command:cmd})})}
    catch(e){commandPending=null;syncCommandButtons();throw e}
    $('status').textContent=`LIVE · ${analyzerLabel(target)} · ${commandPending.label} 진행 중`;
    toast(wanted?'캡처 수신에는 약 12초가 걸립니다':'명령 전송: '+cmd.toUpperCase())
   }
  }catch(e){toast(e.message)}
  return
 }
 let d=selected(demoData);render(demoData,wanted);toast(cmd==='b'?'벤치마크 결과 표시':cmd==='s'?'Pulse Stress 결과 표시':cmd==='z'?(d.zero_mask_pass?'Zero Mask: PASS':'결과 없음'):(wanted+' 캡처 표시'))
});
function currentCapture(){return selected(rootData)?.captures?.[captureIndices[activeAnalyzer]||0]||null}
function exportName(c,extension){
 let stamp=new Date().toISOString().replace(/[:.]/g,'-');
 return `${activeAnalyzer}_${c.mode.toLowerCase().replace(/\s+/g,'_')}_${stamp}.${extension}`
}
function saveBlob(name,mime,text){
 let link=document.createElement('a'),url=URL.createObjectURL(new Blob([text],{type:mime}));
 link.download=name;link.href=url;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000)
}
/* Section 2.3 preset: send the byte the firmware really accepts, then let
   section 2.4 validate whatever the board actually did. */
async function runPreset(key){
 let p=profiles[key];if(!p)return;
 activePreset=key;renderPresets();
 if(!p.firmware_supported&&p.note)toast(p.note);
 let button=document.querySelector(`[data-cmd="${p.command}"]`);
 if(!button)return toast('해당 캡처 명령을 찾을 수 없습니다');
 button.click()
}
$('savePng').onclick=()=>{
 let c=currentCapture();if(!c)return toast('저장할 캡처가 없습니다');
 let link=document.createElement('a');
 link.download=exportName(c,'png');link.href=$('wave').toDataURL('image/png');link.click();toast('파형 PNG 저장')
};
/* Same column order as the importer, so an export round-trips back into the GUI. */
$('saveCsv').onclick=()=>{
 let c=currentCapture();if(!c)return toast('저장할 캡처가 없습니다');
 let lines=['index,ch7,ch6,ch5,ch4,ch3,ch2,ch1,ch0'];
 c.samples.forEach((v,i)=>{lines.push(i+','+[7,6,5,4,3,2,1,0].map(ch=>(v>>ch)&1).join(','))});
 saveBlob(exportName(c,'csv'),'text/csv;charset=utf-8',lines.join('\n')+'\n');
 toast(`${fmt(c.samples.length)} Sample CSV 저장`)
};
$('zoomTrigger').onclick=()=>{
 let c=currentCapture();if(!c)return toast('표시할 캡처가 없습니다');
 zoomed=!zoomed;$('zoomTrigger').classList.toggle('on',zoomed);
 $('zoomTrigger').textContent=zoomed?'전체 보기':'Trigger 확대';
 draw(c);toast(zoomed?`Trigger 확대 [${ZOOM_SPAN[0]},${ZOOM_SPAN[1]})`:'전체 캡처 표시')
};
$('captureFile').onchange=async event=>{
 let file=event.target.files[0];if(!file)return;
 try{
  if(live)await disconnectBoard(false);else stopPolling();
  let epoch=pollEpoch,text=await file.text(),j=await api('/api/parse',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})});
  if(epoch!==pollEpoch)return;
  sourceMode='file';live=false;liveDetectedAnalyzer=null;commandPending=null;$('dot').className='dot';$('connect').textContent='보드 연결';syncCommandButtons();
  $('term').textContent=text.slice(-12000);let detected=analyzerKeys.includes(j.data.active_analyzer)?j.data.active_analyzer:'edgescope_lite';selectAnalyzer(detected,false);render(j.data);$('status').textContent='FILE · '+file.name;toast('캡처 파일을 불러왔습니다')
 }catch(e){toast(e.message)}
 event.target.value=''
};
$('refresh').onclick=refreshPorts;$('connect').onclick=connect;$('demo').onclick=async()=>{if(live)await disconnectBoard(false);await loadDemo()};
window.onresize=()=>{let d=selected(rootData),c=d?.captures?.[captureIndices[activeAnalyzer]||0];c?draw(c):clearWave()};
async function loadProfiles(){
 try{
  let j=await api('/api/profiles');profiles=j.profiles||{};frozenSpec=j.frozen||frozenSpec;renderPresets()
 }catch(e){$('presets').innerHTML=`<div class="hint">Demo Profile을 불러오지 못했습니다: ${esc(e.message)}</div>`}
}
async function initialize(){
 await Promise.all([refreshPorts(),loadImplementation(),loadProfiles()]);
 try{
  let j=await api('/api/state');
  if(j.connected){
   stopPolling();let epoch=pollEpoch;sourceMode='live';live=true;liveDetectedAnalyzer=analyzerKeys.includes(j.data.active_analyzer)?j.data.active_analyzer:null;
   $('connect').textContent=liveDetectedAnalyzer?'연결 해제':'연결 취소';$('dot').className=liveDetectedAnalyzer?'dot live':'dot';
   let detected=liveDetectedAnalyzer||requestedAnalyzer||'edgescope_lite';
   $('status').textContent=liveDetectedAnalyzer?`LIVE · ${analyzerLabel(detected)} · ${j.port||''}`:`UART 연결됨 · 보드 응답 확인 중 · ${j.port||''}`;
   $('term').textContent=j.transcript_tail||'보드 응답 대기 중…';
   rootData=j.data;selectAnalyzer(detected,false);render(j.data);syncCommandButtons();poller=setInterval(()=>poll(epoch),500);
   if(!liveDetectedAnalyzer){
    armProbeTimer(j.port||'',epoch);
    try{await api('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command:'b'})})}catch(e){setDisconnected('보드 응답 확인 실패');toast(e.message);return}
   }
   poll(epoch);return
  }
 }catch(e){}
 await loadDemo()
}
initialize();
</script></body></html>"""


class AppHandler(BaseHTTPRequestHandler):
    demo_text = ""
    serial_manager = SerialManager()
    ila_manager = IlaCaptureManager(serial_manager)

    def log_message(self, format: str, *args) -> None:
        return

    def _json(self, value: dict, status: int = 200) -> None:
        body = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/":
            body = HTML.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
        elif path == "/api/demo":
            self._json({"data": demo_payload(self.demo_text)})
        elif path == "/api/ports":
            self._json({"ports": self.serial_manager.ports()})
        elif path == "/api/state":
            self._json(self.serial_manager.state())
        elif path == "/api/implementation":
            self._json(implementation_payload())
        elif path == "/api/profiles":
            self._json({
                "profiles": DEMO_PROFILES,
                "frozen": {
                    "depth": FROZEN_CAPTURE_DEPTH,
                    "trigger_index": FROZEN_TRIGGER_INDEX,
                    "system_clock_hz": SYSTEM_CLOCK_HZ,
                },
            })
        elif path == "/api/ila/status":
            self._json(self.ila_manager.state())
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self) -> None:
        try:
            length = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length) or b"{}")
            if self.path == "/api/connect":
                self.serial_manager.connect(str(payload["port"]))
                self._json({"ok": True})
            elif self.path == "/api/disconnect":
                self.ila_manager.stop()
                self.serial_manager.disconnect()
                self._json({"ok": True})
            elif self.path == "/api/command":
                self.serial_manager.command(str(payload["command"]).lower())
                self._json({"ok": True})
            elif self.path == "/api/ila/capture":
                program = payload.get("program", False)
                if not isinstance(program, bool):
                    raise ValueError("program은 JSON boolean이어야 합니다.")
                state = self.ila_manager.start(
                    str(payload.get("mode", "")),
                    program,
                )
                self._json(state, 202)
            elif self.path == "/api/parse":
                text = str(payload.get("text", ""))
                if len(text) > 2_000_000:
                    raise ValueError("파일이 2 MB 제한을 초과했습니다.")
                data = parse_uart(text)
                useful = False
                for key, dataset in data["datasets"].items():
                    if (
                        dataset["ready"]
                        or dataset["captures"]
                        or dataset["benchmarks"]
                        or dataset["pulses"]
                        or dataset["zero_mask_pass"]
                        or dataset["warnings"]
                    ):
                        dataset["evidence"] = (
                            "IMPORTED · VIVADO ILA CSV"
                            if key == "vivado_ila"
                            else "IMPORTED FILE"
                        )
                        useful = True
                if not useful:
                    raise ValueError("지원하는 UART/CSV 캡처를 찾지 못했습니다.")
                self._json({"data": data})
            else:
                self._json({"error": "not found"}, 404)
        except Exception as exc:
            self._json({"error": str(exc)}, 400)


def main() -> None:
    parser = argparse.ArgumentParser(description="EdgeScope-Lite A/B/C analyzer GUI")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--log", type=Path, default=DEFAULT_LOG)
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument(
        "--analyzer",
        choices=sorted(ANALYZERS),
        help="Tab to preselect on open.  Use edgescope_lite when recording the "
             "standalone GUI demo so no tab switch is filmed.",
    )
    args = parser.parse_args()
    AppHandler.demo_text = args.log.read_text(encoding="utf-8", errors="replace")
    server = ThreadingHTTPServer((args.host, args.port), AppHandler)
    url = f"http://{args.host}:{args.port}"
    if args.analyzer:
        url += f"/?analyzer={args.analyzer}"
    print(f"EdgeScope-Lite GUI: {url}")
    print("종료: Ctrl+C")
    if not args.no_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        AppHandler.ila_manager.stop()
        AppHandler.serial_manager.disconnect()
        server.server_close()


if __name__ == "__main__":
    main()
