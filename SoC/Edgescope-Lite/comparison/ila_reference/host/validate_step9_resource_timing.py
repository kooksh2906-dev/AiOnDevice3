#!/usr/bin/env python3
"""Extract and validate the Step 9 routed resource/timing comparison.

The official comparison unit is a *whole routed SoC*.  Every method is checked
against the same Vivado version, FPGA part, top, design state, and 100 MHz
``sys_clock`` constraint before its numbers are admitted to the output tables.

Resource totals and deltas from the clean COMMON_BASE_PLUS_GENERATOR baseline
are intentionally separate rows.  CPU Polling is kept as a reference method;
it is never used to calculate the official Custom-vs-ILA resource saving.
Likewise, WNS is reported as slack and is never converted into an inferred
Fmax.
"""

from __future__ import annotations

import argparse
import csv
import dataclasses
import datetime as dt
import hashlib
import io
import os
import re
import sys
from pathlib import Path
from typing import Iterable, Mapping, Sequence


REQUIRED_VIVADO = "2024.2"
REQUIRED_PART = "xc7a35tcpg236-1"
REQUIRED_TOP = "base_soc_wrapper"
REQUIRED_CLOCK_NAME = "sys_clock"
REQUIRED_CLOCK_PERIOD_NS = 10.000
REQUIRED_CLOCK_FREQUENCY_MHZ = 100.000
REQUIRED_BOARD_PART = "digilentinc.com:basys3:part0:1.2"
REQUIRED_CHECK_TIMING_COUNTS: tuple[tuple[str, int], ...] = (
    ("no_clock", 0),
    ("constant_clock", 0),
    ("pulse_width_clock", 0),
    ("unconstrained_internal_endpoints", 0),
    ("no_input_delay", 2),
    ("no_output_delay", 1),
    ("multiple_clock", 0),
    ("generated_clocks", 0),
    ("loops", 0),
    ("partial_input_delay", 0),
    ("partial_output_delay", 0),
    ("latch_loops", 0),
)

STATUS_VERIFIED = "VERIFIED"
STATUS_NOT_RECEIVED = "NOT_RECEIVED"
STATUS_BUILD_IN_PROGRESS = "BUILD_IN_PROGRESS"
STATUS_INCOMPLETE = "INCOMPLETE"
STATUS_INVALID = "INVALID"
STATUS_SUMMARY_ONLY = "SUMMARY_ONLY"
STATUS_NOT_APPLICABLE = "NOT_APPLICABLE"

SHA256_PATTERN = re.compile(r"^[0-9a-fA-F]{64}$")
GIT_COMMIT_PATTERN = re.compile(r"^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$")

CUSTOM_COMPONENT_ALIASES: Mapping[str, tuple[str, ...]] = {
    "probe_sampler": (
        "probe_sampler_axi_0",
        "probe_sampler_0",
    ),
    "trigger_engine": (
        "basic_trigger_engine_0",
        "basic_trigger_engine_axi_0",
        "trigger_engine_0",
    ),
    "circular_trace_buffer": (
        "circular_trace_buffer_0",
    ),
    "axi_bram_controller": (
        "axi_bram_ctrl_0",
        "axi_bram_controller_0",
        "capture_axi_bram_ctrl_0",
    ),
    "capture_bram": (
        "circular_trace_buffer_0_bram",
        "capture_bram_0",
        "trace_capture_bram_0",
        "blk_mem_gen_capture_0",
    ),
}

CUSTOM_REQUIRED_COMMON_HIERARCHIES: Mapping[str, tuple[str, ...]] = {
    "base_soc_i": ("base_soc",),
    "axi_gpio_test_ctrl": ("base_soc_axi_gpio_test_ctrl_0",),
    "axi_timer_0": ("base_soc_axi_timer_0_0",),
    "axi_uartlite_0": ("base_soc_axi_uartlite_0_0",),
    "clk_wiz": ("base_soc_clk_wiz_0",),
    "mdm_1": ("base_soc_mdm_1_0",),
    "microblaze_riscv_0": ("base_soc_microblaze_riscv_0_0",),
    "microblaze_riscv_0_axi_intc": (
        "base_soc_microblaze_riscv_0_axi_intc_0",
    ),
    "microblaze_riscv_0_axi_periph": (
        "base_soc_microblaze_riscv_0_axi_periph_0",
    ),
    "microblaze_riscv_0_local_memory": (),
    "microblaze_riscv_0_xlconcat": (
        "base_soc_microblaze_riscv_0_xlconcat_0",
    ),
    "rst_clk_wiz_100M": ("base_soc_rst_clk_wiz_100M_0",),
    "test_pattern_generator_gpio_adapter_0": (
        "base_soc_test_pattern_generator_gpio_adapter_0_0",
    ),
}

CUSTOM_COMPONENT_COUNT_KEYS: Mapping[str, tuple[str, ...]] = {
    "probe_sampler": (
        "CUSTOM_PROBE_SAMPLER_COUNT",
        "PROBE_SAMPLER_COUNT",
    ),
    "trigger_engine": (
        "CUSTOM_TRIGGER_ENGINE_COUNT",
        "BASIC_TRIGGER_ENGINE_COUNT",
        "TRIGGER_ENGINE_COUNT",
    ),
    "circular_trace_buffer": (
        "CUSTOM_CIRCULAR_TRACE_BUFFER_COUNT",
        "CIRCULAR_TRACE_BUFFER_COUNT",
    ),
    "axi_bram_controller": (
        "CUSTOM_AXI_BRAM_CONTROLLER_COUNT",
        "AXI_BRAM_CONTROLLER_COUNT",
        "AXI_BRAM_CTRL_COUNT",
    ),
    "capture_bram": (
        "CUSTOM_CAPTURE_BRAM_COUNT",
        "CAPTURE_BRAM_COUNT",
    ),
}

CUSTOM_SOURCE_HASH_KEYS: Mapping[str, tuple[str, ...]] = {
    "probe_sampler": (
        "PROBE_SAMPLER_SOURCE_SHA256",
        "PROBE_SAMPLER_RTL_SHA256",
    ),
    "trigger_engine": (
        "TRIGGER_ENGINE_SOURCE_SHA256",
        "BASIC_TRIGGER_ENGINE_RTL_SHA256",
        "TRIGGER_ENGINE_RTL_SHA256",
    ),
    "circular_trace_buffer": (
        "CIRCULAR_TRACE_BUFFER_SOURCE_SHA256",
        "CIRCULAR_TRACE_BUFFER_RTL_SHA256",
    ),
    "capture_bram": (
        "CAPTURE_BRAM_SOURCE_SHA256",
        "CAPTURE_BRAM_CONFIG_SHA256",
        "CAPTURE_BRAM_TCL_SHA256",
    ),
}


class ReportError(ValueError):
    """Raised when a Vivado report is missing a required, unambiguous value."""


@dataclasses.dataclass(frozen=True)
class ReportMetadata:
    tool_version: str
    vivado_version: str
    design: str
    device: str
    speed_file: str
    design_state: str


@dataclasses.dataclass(frozen=True)
class ResourceMetrics:
    slice_luts: int
    lut_as_logic: int
    lut_as_memory: int
    slice_registers: int
    ramb36: int
    ramb18: int
    dsp48e1: int

    @property
    def bram_tile_equiv(self) -> float:
        return self.ramb36 + (0.5 * self.ramb18)

    def subtract(self, baseline: "ResourceMetrics") -> "ResourceMetrics":
        """Return a signed delta; negative values are never clamped."""

        return ResourceMetrics(
            slice_luts=self.slice_luts - baseline.slice_luts,
            lut_as_logic=self.lut_as_logic - baseline.lut_as_logic,
            lut_as_memory=self.lut_as_memory - baseline.lut_as_memory,
            slice_registers=self.slice_registers - baseline.slice_registers,
            ramb36=self.ramb36 - baseline.ramb36,
            ramb18=self.ramb18 - baseline.ramb18,
            dsp48e1=self.dsp48e1 - baseline.dsp48e1,
        )


@dataclasses.dataclass(frozen=True)
class TimingMetrics:
    wns_ns: float
    tns_ns: float
    whs_ns: float
    ths_ns: float
    wpws_ns: float
    tpws_ns: float
    clock_period_ns: float
    clock_frequency_mhz: float
    internal_unconstrained_endpoints: int
    constraints_met: bool
    check_timing_counts: tuple[tuple[str, int], ...]


@dataclasses.dataclass(frozen=True)
class HierarchyMetrics:
    instance: str
    module: str
    total_luts: int
    logic_luts: int
    lutrams: int
    srls: int
    ffs: int
    ramb36: int
    ramb18: int
    dsp_blocks: int

    def as_resource_metrics(self) -> ResourceMetrics:
        return ResourceMetrics(
            slice_luts=self.total_luts,
            lut_as_logic=self.logic_luts,
            lut_as_memory=self.lutrams + self.srls,
            slice_registers=self.ffs,
            ramb36=self.ramb36,
            ramb18=self.ramb18,
            dsp48e1=self.dsp_blocks,
        )


@dataclasses.dataclass(frozen=True)
class RouteMetrics:
    routable_nets: int
    fully_routed_nets: int
    routing_errors: int

    @property
    def fully_routed(self) -> bool:
        return (
            self.routable_nets > 0
            and self.fully_routed_nets == self.routable_nets
            and self.routing_errors == 0
        )


@dataclasses.dataclass(frozen=True)
class DrcMetrics:
    checks_found: int
    errors: int
    critical_warnings: int
    warnings: int
    entire_design: bool = False
    ruledecks: tuple[str, ...] = ()
    max_checks_unlimited: bool = False
    no_waivers: bool = False
    command_is_report_drc: bool = False
    command_ruledecks: tuple[str, ...] = ()
    scope_filter_absent: bool = False

    @property
    def full_scope_contract(self) -> bool:
        return (
            self.entire_design
            and set(self.ruledecks) == {"bitstream_checks", "default"}
            and self.max_checks_unlimited
            and self.no_waivers
            and self.command_is_report_drc
            and set(self.command_ruledecks)
            == {"bitstream_checks", "default"}
            and self.scope_filter_absent
        )


@dataclasses.dataclass(frozen=True)
class MethodPaths:
    utilization: Path
    hierarchy: Path
    timing: Path
    drc: Path
    route: Path | None = None
    routed_dcp: Path | None = None
    check_timing: Path | None = None
    manifest: Path | None = None
    checksum_index: Path | None = None
    completion_log: Path | None = None
    provenance: Path | None = None

    def core_reports(self) -> tuple[Path, ...]:
        reports = [self.utilization, self.hierarchy, self.timing, self.drc]
        if self.route is not None:
            reports.append(self.route)
        if self.routed_dcp is not None:
            reports.append(self.routed_dcp)
        if self.check_timing is not None:
            reports.append(self.check_timing)
        return tuple(reports)


@dataclasses.dataclass
class MethodResult:
    key: str
    label: str
    scope: str
    paths: MethodPaths
    status: str
    detail: str
    resources: ResourceMetrics | None = None
    timing: TimingMetrics | None = None
    hierarchy_rows: list[HierarchyMetrics] = dataclasses.field(
        default_factory=list
    )
    route: RouteMetrics | None = None
    drc: DrcMetrics | None = None
    metadata: ReportMetadata | None = None
    assertions: list[tuple[str, str, str]] = dataclasses.field(
        default_factory=list
    )

    def add_assertion(self, name: str, passed: bool, detail: str) -> None:
        self.assertions.append((name, "PASS" if passed else "FAIL", detail))
        if not passed:
            self.status = STATUS_INVALID

    @property
    def verified(self) -> bool:
        return self.status == STATUS_VERIFIED


@dataclasses.dataclass(frozen=True)
class MethodSpec:
    key: str
    label: str
    scope: str
    paths: MethodPaths
    require_route: bool
    expected_resources: ResourceMetrics | None = None
    expected_timing: tuple[float, float, float, float, float, float] | None = None


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise ReportError(f"cannot read {path}: {exc}") from exc


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as channel:
        for block in iter(lambda: channel.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _header_value(text: str, key: str) -> str:
    match = re.search(
        rf"^\|\s*{re.escape(key)}\s*:\s*(.*?)\s*$",
        text,
        flags=re.MULTILINE,
    )
    if match is None:
        raise ReportError(f"missing report header field: {key}")
    return match.group(1).strip()


def parse_report_metadata(text: str) -> ReportMetadata:
    tool_version = _header_value(text, "Tool Version")
    version_match = re.search(r"Vivado\s+v\.?([0-9]+(?:\.[0-9]+)+)", tool_version)
    if version_match is None:
        raise ReportError(f"cannot parse Vivado version from: {tool_version}")
    return ReportMetadata(
        tool_version=tool_version,
        vivado_version=version_match.group(1),
        design=_header_value(text, "Design"),
        device=_header_value(text, "Device"),
        speed_file=_header_value(text, "Speed File"),
        design_state=_header_value(text, "Design State"),
    )


def _pipe_columns(line: str) -> list[str]:
    if not line.lstrip().startswith("|"):
        return []
    return [column.strip() for column in line.strip().strip("|").split("|")]


def _parse_int(value: str, label: str) -> int:
    cleaned = value.strip().replace(",", "")
    if not re.fullmatch(r"[-+]?\d+", cleaned):
        raise ReportError(f"{label} is not an integer: {value!r}")
    return int(cleaned)


def _first_table_number(
    text: str, labels: Sequence[str], *, integer: bool = True
) -> int | float:
    accepted = set(labels)
    for line in text.splitlines():
        columns = _pipe_columns(line)
        if len(columns) < 2 or columns[0] not in accepted:
            continue
        raw = columns[1].replace(",", "")
        try:
            return int(raw) if integer else float(raw)
        except ValueError as exc:
            raise ReportError(
                f"invalid Used value for {columns[0]}: {columns[1]!r}"
            ) from exc
    raise ReportError(f"missing utilization row: {' or '.join(labels)}")


def parse_utilization_text(
    text: str,
) -> tuple[ReportMetadata, ResourceMetrics]:
    metadata = parse_report_metadata(text)
    metrics = ResourceMetrics(
        slice_luts=int(_first_table_number(text, ("Slice LUTs",))),
        lut_as_logic=int(_first_table_number(text, ("LUT as Logic",))),
        lut_as_memory=int(_first_table_number(text, ("LUT as Memory",))),
        slice_registers=int(
            _first_table_number(text, ("Slice Registers",))
        ),
        ramb36=int(_first_table_number(text, ("RAMB36/FIFO*", "RAMB36"))),
        ramb18=int(_first_table_number(text, ("RAMB18",))),
        dsp48e1=int(_first_table_number(text, ("DSPs", "DSP48E1"))),
    )
    if metrics.lut_as_logic + metrics.lut_as_memory != metrics.slice_luts:
        raise ReportError(
            "Slice LUT decomposition mismatch: "
            f"{metrics.lut_as_logic}+{metrics.lut_as_memory}"
            f"!={metrics.slice_luts}"
        )
    return metadata, metrics


def parse_timing_text(
    text: str,
) -> tuple[ReportMetadata, TimingMetrics]:
    metadata = parse_report_metadata(text)
    summary_start = text.find("| Design Timing Summary")
    if summary_start < 0:
        raise ReportError("missing Design Timing Summary")
    summary_text = text[summary_start:]
    summary_match = re.search(
        r"^\s*([-+]?\d+(?:\.\d+)?)\s+"
        r"([-+]?\d+(?:\.\d+)?)\s+\d+\s+\d+\s+"
        r"([-+]?\d+(?:\.\d+)?)\s+"
        r"([-+]?\d+(?:\.\d+)?)\s+\d+\s+\d+\s+"
        r"([-+]?\d+(?:\.\d+)?)\s+"
        r"([-+]?\d+(?:\.\d+)?)\s+\d+\s+\d+\s*$",
        summary_text,
        flags=re.MULTILINE,
    )
    if summary_match is None:
        raise ReportError("cannot parse Design Timing Summary values")

    clock_match = re.search(
        rf"^\s*{re.escape(REQUIRED_CLOCK_NAME)}\s+"
        r"\{[^}]+\}\s+([-+]?\d+(?:\.\d+)?)\s+"
        r"([-+]?\d+(?:\.\d+)?)\s*$",
        text,
        flags=re.MULTILINE,
    )
    if clock_match is None:
        raise ReportError(f"missing exact clock row: {REQUIRED_CLOCK_NAME}")

    all_check_matches = re.findall(
        r"^\s*\d+\.\s+checking\s+([a-z0-9_]+)\s+\((\d+)\)\s*$",
        text,
        flags=re.MULTILINE,
    )
    parsed_checks = tuple(
        (name, int(raw_count))
        for name, raw_count in all_check_matches
    )
    group_size = len(REQUIRED_CHECK_TIMING_COUNTS)
    check_groups = tuple(
        parsed_checks[index : index + group_size]
        for index in range(0, len(parsed_checks), group_size)
    )
    if (
        not parsed_checks
        or len(parsed_checks) % group_size != 0
        or any(
            group != REQUIRED_CHECK_TIMING_COUNTS
            for group in check_groups
        )
    ):
        raise ReportError(
            "check_timing summary/detail mismatch: "
            f"groups={check_groups!r}, "
            f"expected={REQUIRED_CHECK_TIMING_COUNTS!r}"
        )
    check_timing_counts = check_groups[0]
    check_timing_map = dict(check_timing_counts)

    values = [float(value) for value in summary_match.groups()]
    return metadata, TimingMetrics(
        wns_ns=values[0],
        tns_ns=values[1],
        whs_ns=values[2],
        ths_ns=values[3],
        wpws_ns=values[4],
        tpws_ns=values[5],
        clock_period_ns=float(clock_match.group(1)),
        clock_frequency_mhz=float(clock_match.group(2)),
        internal_unconstrained_endpoints=check_timing_map[
            "unconstrained_internal_endpoints"
        ],
        constraints_met=(
            "All user specified timing constraints are met." in text
        ),
        check_timing_counts=check_timing_counts,
    )


def parse_hierarchy_text(
    text: str,
) -> tuple[ReportMetadata, list[HierarchyMetrics]]:
    metadata = parse_report_metadata(text)
    rows: list[HierarchyMetrics] = []
    for line in text.splitlines():
        columns = _pipe_columns(line)
        if len(columns) != 10:
            continue
        if columns[0] in {"Instance", ""} or columns[2] == "Total LUTs":
            continue
        try:
            numbers = [
                _parse_int(value, f"hierarchy {columns[0]}")
                for value in columns[2:]
            ]
        except ReportError:
            continue
        rows.append(
            HierarchyMetrics(
                instance=columns[0],
                module=columns[1],
                total_luts=numbers[0],
                logic_luts=numbers[1],
                lutrams=numbers[2],
                srls=numbers[3],
                ffs=numbers[4],
                ramb36=numbers[5],
                ramb18=numbers[6],
                dsp_blocks=numbers[7],
            )
        )
    if not rows:
        raise ReportError("no hierarchy utilization rows found")
    return metadata, rows


def find_hierarchy_row(
    rows: Sequence[HierarchyMetrics],
    aliases: Sequence[str],
) -> HierarchyMetrics | None:
    matches = find_hierarchy_rows(rows, aliases)
    return None if not matches else matches[0]


def find_hierarchy_rows(
    rows: Sequence[HierarchyMetrics],
    aliases: Sequence[str],
) -> list[HierarchyMetrics]:
    accepted = set(aliases)
    return [row for row in rows if row.instance in accepted]


def parse_route_text(text: str) -> RouteMetrics:
    def value(label: str) -> int:
        match = re.search(
            rf"^\s*# of {re.escape(label)}[. ]*:\s*(\d+)\s*:",
            text,
            flags=re.MULTILINE,
        )
        if match is None:
            raise ReportError(f"missing route status value: {label}")
        return int(match.group(1))

    return RouteMetrics(
        routable_nets=value("routable nets"),
        fully_routed_nets=value("fully routed nets"),
        routing_errors=value("nets with routing errors"),
    )


def parse_drc_text(text: str) -> tuple[ReportMetadata, DrcMetrics]:
    metadata = parse_report_metadata(text)
    summary_start = re.search(
        r"^1\. REPORT SUMMARY\s*\n-+\s*$",
        text,
        flags=re.MULTILINE,
    )
    details_start = re.search(
        r"^2\. REPORT DETAILS\s*\n-+\s*$",
        text,
        flags=re.MULTILINE,
    )
    if summary_start is None or details_start is None:
        raise ReportError("missing DRC report summary/details section")
    if details_start.start() <= summary_start.end():
        raise ReportError("DRC report sections are out of order")

    summary = text[summary_start.end() : details_start.start()]
    found_match = re.search(r"Checks found:\s*(\d+)", summary)
    if found_match is None:
        raise ReportError("missing DRC Checks found in report summary")
    checks_found = int(found_match.group(1))

    severity_totals = {
        "error": 0,
        "critical warning": 0,
        "warning": 0,
    }
    parsed_checks = 0
    for line in summary.splitlines():
        columns = _pipe_columns(line)
        if len(columns) != 4 or columns[0] in {"Rule", ""}:
            continue
        check_count = _parse_int(columns[3], "DRC Checks")
        parsed_checks += check_count
        severity = columns[1].strip().lower()
        if severity not in severity_totals:
            raise ReportError(
                f"unsupported DRC severity {columns[1]!r} "
                f"for rule {columns[0]!r}"
            )
        severity_totals[severity] += check_count
    if parsed_checks != checks_found:
        raise ReportError(
            "DRC summary count mismatch: "
            f"table={parsed_checks}, Checks found={checks_found}"
        )

    def summary_value(label: str) -> str | None:
        match = re.search(
            rf"^\s*{re.escape(label)}\s*:\s*(.*?)\s*$",
            summary,
            flags=re.MULTILINE,
        )
        return None if match is None else match.group(1).strip()

    design_limits = summary_value("Design limits")
    ruledeck_value = summary_value("Ruledeck")
    ruledecks = tuple(
        sorted(
            token.lower()
            for token in re.split(r"[\s,]+", ruledeck_value or "")
            if token
        )
    )
    max_checks = summary_value("Max checks")
    command_match = re.search(
        r"^\|\s*Command\s*:\s*(.*?)\s*$",
        text,
        flags=re.MULTILINE,
    )
    command = "" if command_match is None else command_match.group(1)
    command_ruledeck_match = re.search(
        r"(?:^|\s)-ruledecks\s+(?:\{([^}]*)\}|(\S+))",
        command,
    )
    command_ruledeck_value = (
        ""
        if command_ruledeck_match is None
        else (
            command_ruledeck_match.group(1)
            or command_ruledeck_match.group(2)
        )
    )
    command_ruledecks = tuple(
        sorted(
            token.lower()
            for token in re.split(r"[\s,]+", command_ruledeck_value)
            if token
        )
    )
    return metadata, DrcMetrics(
        checks_found=checks_found,
        errors=severity_totals["error"],
        critical_warnings=severity_totals["critical warning"],
        warnings=severity_totals["warning"],
        entire_design=design_limits == "<entire design considered>",
        ruledecks=ruledecks,
        max_checks_unlimited=max_checks == "<unlimited>",
        no_waivers=bool(
            re.search(r"(?:^|\s)-no_waivers(?:\s|$)", command)
        ),
        command_is_report_drc=bool(
            re.match(r"^\s*report_drc(?:\s|$)", command)
        ),
        command_ruledecks=command_ruledecks,
        scope_filter_absent=not bool(
            re.search(r"(?:^|\s)-(?:checks|filter)(?:\s|$)", command)
        ),
    )


def parse_key_value_manifest(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", maxsplit=1)
        clean_key = key.strip()
        if clean_key in result:
            raise ReportError(
                f"duplicate key in key=value manifest: {clean_key}"
            )
        result[clean_key] = value.strip()
    return result


def parse_colon_manifest(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", maxsplit=1)
        clean_key = key.strip()
        if clean_key in result:
            raise ReportError(
                f"duplicate key in colon manifest: {clean_key}"
            )
        result[clean_key] = value.strip()
    return result


def parse_checksum_index(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in text.splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]{64})\s+\*?(.+)", line.strip())
        if match is not None:
            result[match.group(2)] = match.group(1).lower()
    return result


def _metadata_compatible(actual: ReportMetadata) -> list[str]:
    errors: list[str] = []
    if actual.vivado_version != REQUIRED_VIVADO:
        errors.append(
            f"Vivado={actual.vivado_version}, required={REQUIRED_VIVADO}"
        )
    if actual.design != REQUIRED_TOP:
        errors.append(f"top={actual.design}, required={REQUIRED_TOP}")
    state = " ".join(actual.design_state.lower().split())
    if state not in {"routed", "fully routed"}:
        errors.append(f"design_state={actual.design_state}, expected Routed")
    lowered_device = actual.device.lower()
    compact_device = re.sub(r"[^a-z0-9]", "", lowered_device)
    if lowered_device.startswith("xc"):
        device_matches = lowered_device == REQUIRED_PART
    else:
        # Timing reports abbreviate the device and carry the speed grade in
        # the adjacent Speed File header.
        device_matches = (
            "7a35t" in compact_device and "cpg236" in compact_device
        )
    if not device_matches:
        errors.append(f"device={actual.device}, required={REQUIRED_PART}")
    if actual.speed_file.split(maxsplit=1)[0] != "-1":
        errors.append(f"speed_file={actual.speed_file}, required=-1")
    return errors


def _same_report_identity(
    left: ReportMetadata, right: ReportMetadata
) -> bool:
    return (
        left.vivado_version == right.vivado_version
        and left.design == right.design
        and left.speed_file.split(maxsplit=1)[0]
        == right.speed_file.split(maxsplit=1)[0]
        and "7a35t" in re.sub(r"[^a-z0-9]", "", right.device.lower())
        and "cpg236" in re.sub(r"[^a-z0-9]", "", right.device.lower())
        and " ".join(right.design_state.lower().split())
        in {"routed", "fully routed"}
    )


def _float_equal(left: float, right: float, tolerance: float = 0.0005) -> bool:
    return abs(left - right) <= tolerance


def _bounded_hierarchy_pattern(name: str) -> re.Pattern[str]:
    """Match an IP token without treating an ordinary substring as an IP."""

    return re.compile(
        rf"(?<![a-z0-9]){name}(?![a-z0-9])",
        flags=re.IGNORECASE,
    )


FORBIDDEN_DEBUG_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("ila_reference", _bounded_hierarchy_pattern(r"ila_reference(?:_[0-9]+)?")),
    ("ila", _bounded_hierarchy_pattern(r"ila_[0-9]+")),
    ("ila_v6", _bounded_hierarchy_pattern(r"ila_v6(?:_[a-z0-9]+)*")),
    ("system_ila", _bounded_hierarchy_pattern(r"system_ila(?:_[a-z0-9]+)*")),
    ("vio", _bounded_hierarchy_pattern(r"vio(?:_[a-z0-9]+)*")),
    ("dbg_hub", _bounded_hierarchy_pattern(r"dbg_hub(?:_[a-z0-9]+)*")),
)


def _detect_forbidden_debug_cores(
    rows: Sequence[HierarchyMetrics],
) -> list[str]:
    found: set[str] = set()
    for row in rows:
        haystack = f"{row.instance} {row.module}"
        for label, pattern in FORBIDDEN_DEBUG_PATTERNS:
            if pattern.search(haystack):
                found.add(label)
    return sorted(found)


def _detect_forbidden_analyzers(
    rows: Sequence[HierarchyMetrics],
) -> list[str]:
    found = set(_detect_forbidden_debug_cores(rows))
    custom_patterns = (
        ("circular_trace_buffer", "circular_trace_buffer"),
        ("probe_sampler", "probe_sampler"),
        ("basic_trigger_engine", "basic_trigger_engine"),
        ("trigger_engine", "trigger_engine"),
    )
    for row in rows:
        haystack = f"{row.instance} {row.module}".lower()
        for label, pattern in custom_patterns:
            if _bounded_hierarchy_pattern(pattern).search(haystack):
                found.add(label)
    return sorted(found)


def _generator_row(
    rows: Sequence[HierarchyMetrics],
) -> HierarchyMetrics | None:
    return find_hierarchy_row(
        rows,
        (
            "test_pattern_generator_gpio_adapter_0",
            "test_pattern_generator_0",
        ),
    )


def _custom_component_rows(
    rows: Sequence[HierarchyMetrics],
) -> dict[str, HierarchyMetrics | None]:
    return {
        role: find_hierarchy_row(rows, aliases)
        for role, aliases in CUSTOM_COMPONENT_ALIASES.items()
    }


def _component_rows(
    key: str, rows: Sequence[HierarchyMetrics]
) -> list[tuple[str, HierarchyMetrics, str]]:
    components: list[tuple[str, HierarchyMetrics, str]] = []
    generator = _generator_row(rows)
    if generator is not None:
        components.append(
            (
                "COMMON_TEST_PATTERN_GENERATOR",
                generator,
                "공통 Generator 계층; 방법별 동일성 교차 검증",
            )
        )
    if key == "cpu_polling":
        row = find_hierarchy_row(rows, ("axi_gpio_probe",))
        if row is not None:
            components.append(
                (
                    "CPU_POLLING_PROBE_INTERFACE",
                    row,
                    "AXI GPIO probe 계층; CPU Polling 총량의 부분 계층값",
                )
            )
    elif key == "ila_reference":
        ila = find_hierarchy_row(rows, ("ila_reference_0",))
        if ila is not None:
            components.append(
                (
                    "VIVADO_ILA_CORE",
                    ila,
                    "공식 ILA 계층값; 전체 SoC 증분값과 동일하지 않음",
                )
            )
        hub = find_hierarchy_row(rows, ("dbg_hub",))
        if hub is not None:
            components.append(
                (
                    "VIVADO_DEBUG_HUB",
                    hub,
                    "ILA에 필요한 Debug Hub 계층값; ILA Core와 별도 표시",
                )
            )
    elif key == "custom":
        output_roles = {
            "probe_sampler": "CUSTOM_PROBE_SAMPLER",
            "trigger_engine": "CUSTOM_TRIGGER_ENGINE",
            "circular_trace_buffer": "CUSTOM_CIRCULAR_TRACE_BUFFER",
            "axi_bram_controller": "CUSTOM_AXI_BRAM_CONTROLLER",
            "capture_bram": "CUSTOM_CAPTURE_BRAM",
        }
        for component, row in _custom_component_rows(rows).items():
            if row is not None:
                components.append(
                    (
                        output_roles[component],
                        row,
                        "Custom IP 계층값; 공식 증분은 전체 SoC-기준선으로 계산",
                    )
                )
    return components


def _path_state(spec: MethodSpec) -> tuple[str, str]:
    required_paths = list(spec.paths.core_reports())
    if spec.paths.manifest is not None:
        required_paths.append(spec.paths.manifest)
    missing = [path for path in required_paths if not path.is_file()]

    if spec.key == "common_baseline":
        log = spec.paths.completion_log
        if log is not None and log.is_file():
            log_text = _read_text(log)
            if re.search(
                r"^STEP9_BASELINE_LAUNCH\|result=FAIL\|exit_code=\d+\s*$",
                log_text,
                flags=re.MULTILINE,
            ):
                return (
                    STATUS_INVALID,
                    "clean baseline runner recorded BUILD_FAILED",
                )
            if not re.search(
                r"^STEP9_BASELINE_LAUNCH\|result=PASS\|exit_code=0\s*$",
                log_text,
                flags=re.MULTILINE,
            ):
                return (
                    STATUS_BUILD_IN_PROGRESS,
                    "clean baseline runner has no final PASS/FAIL marker",
                )
            if missing:
                return (
                    STATUS_INCOMPLETE,
                    "baseline runner passed but output set is incomplete: "
                    + ", ".join(path.name for path in missing),
                )
        elif log is not None and not log.is_file() and any(
            path.exists()
            for path in (
                *spec.paths.core_reports(),
                spec.paths.manifest,
            )
            if path is not None
        ):
            return (
                STATUS_BUILD_IN_PROGRESS,
                "clean baseline runner has no completion log/final marker",
            )
        elif missing and any(
            path.exists() for path in spec.paths.core_reports()
        ):
            return (
                STATUS_INCOMPLETE,
                "clean baseline output set is incomplete: "
                + ", ".join(path.name for path in missing),
            )
    if not missing:
        return STATUS_VERIFIED, "all required reports are present"
    if any(path.is_file() for path in required_paths):
        return (
            STATUS_INCOMPLETE,
            "partial input set; missing: "
            + ", ".join(path.name for path in missing),
        )
    return (
        STATUS_NOT_RECEIVED,
        "missing: " + ", ".join(path.name for path in missing),
    )


def _common_source_paths(root: Path) -> Mapping[str, Path]:
    common = root.parent / "common"
    return {
        "BASE_SOC_TCL_SHA256": common / "base_soc.tcl",
        "GENERATOR_INTEGRATION_TCL_SHA256": (
            common / "add_test_pattern_generator.tcl"
        ),
        "GENERATOR_RTL_SHA256": (
            common / "rtl/test_pattern_generator.sv"
        ),
        "GENERATOR_ADAPTER_SHA256": (
            common / "rtl/test_pattern_generator_gpio_adapter.v"
        ),
    }


def _verify_canonical_common_source_hashes(
    result: MethodResult,
    manifest: Mapping[str, str],
    root: Path,
    assertion_prefix: str,
) -> None:
    for key, source_path in _common_source_paths(root).items():
        claimed = manifest.get(key)
        source_exists = source_path.is_file()
        actual = _sha256(source_path) if source_exists else None
        result.add_assertion(
            f"{assertion_prefix}.{key}",
            source_exists
            and _is_sha256(claimed)
            and claimed.lower() == actual,
            (
                f"source={source_path}, local={actual or 'MISSING'}, "
                f"manifest={claimed or 'MISSING'}"
            ),
        )


def _verify_baseline_drc_manifest_counts(
    result: MethodResult, manifest: Mapping[str, str]
) -> None:
    """Bind build-time DRC counts to the parsed routed DRC report."""

    if result.drc is None:
        result.add_assertion(
            "baseline_manifest.DRC_COUNTS",
            False,
            "parsed baseline DRC metrics are unavailable",
        )
        return
    expected_drc_counts = {
        "DRC_ERROR_COUNT": str(result.drc.errors),
        "DRC_CRITICAL_WARNING_COUNT": str(result.drc.critical_warnings),
        "DRC_WARNING_COUNT": str(result.drc.warnings),
        "DRC_OTHER_COUNT": "0",
    }
    for key, required in expected_drc_counts.items():
        actual = manifest.get(key)
        result.add_assertion(
            f"baseline_manifest.{key}",
            actual == required,
            f"actual={actual!r}, expected={required!r}",
        )


def _verify_baseline_manifest(
    result: MethodResult, manifest: Mapping[str, str], root: Path
) -> None:
    expected = {
        "STEP": "9",
        "BUILD_SCOPE": "COMMON_BASE_PLUS_GENERATOR",
        "OVERALL": "PASS",
        "VIVADO_VERSION": REQUIRED_VIVADO,
        "FPGA_PART": REQUIRED_PART,
        "BOARD_PART": REQUIRED_BOARD_PART,
        "TOP": REQUIRED_TOP,
        "DESIGN_STATE": "ROUTED",
        "CLOCK_HZ": "100000000",
        "CLOCK_PERIOD_NS": "10.000",
        "SYNTHESIS_STRATEGY": "Vivado Synthesis Defaults",
        "IMPLEMENTATION_STRATEGY": "Vivado Implementation Defaults",
        "VIVADO_ILA_COUNT": "0",
        "VIO_COUNT": "0",
        "CUSTOM_ANALYZER_COUNT": "0",
        "DEBUG_CORE_COUNT": "0",
        "GENERATOR_HIERARCHY_COUNT": "1",
    }
    for key, required in expected.items():
        actual = manifest.get(key)
        result.add_assertion(
            f"baseline_manifest.{key}",
            actual == required,
            f"actual={actual!r}, expected={required!r}",
        )

    _verify_baseline_drc_manifest_counts(result, manifest)

    _verify_canonical_common_source_hashes(
        result, manifest, root, "baseline_manifest"
    )

    git_commit = manifest.get("GIT_COMMIT")
    result.add_assertion(
        "baseline_manifest.GIT_COMMIT",
        git_commit is not None
        and GIT_COMMIT_PATTERN.fullmatch(git_commit) is not None,
        f"actual={git_commit!r}; expected 40- or 64-hex Git object id",
    )
    git_dirty = manifest.get("GIT_WORKTREE_DIRTY")
    result.add_assertion(
        "baseline_manifest.GIT_WORKTREE_DIRTY",
        git_dirty is not None
        and git_dirty.strip().lower() in {"0", "1", "true", "false"},
        f"actual={git_dirty!r}; expected explicit 0/1/true/false",
    )
    local_provenance = {
        "BASE_BUILD_TCL_SHA256": (
            root.parent / "common/build_base_with_generator.tcl"
        ),
        "BASELINE_CONSTRAINT_SHA256": (
            root / "constraints/step9_baseline_common.xdc"
        ),
        "BASELINE_TCL_SHA256": root / "build_step9_common_baseline.tcl",
        "BASELINE_RUNNER_SHA256": root / "run_step9_common_baseline.sh",
    }
    for key, local_path in local_provenance.items():
        claimed = manifest.get(key)
        actual = _sha256(local_path) if local_path.is_file() else None
        result.add_assertion(
            f"baseline_manifest.{key}",
            actual is not None
            and _is_sha256(claimed)
            and claimed.lower() == actual,
            (
                f"source={local_path}, local={actual or 'MISSING'}, "
                f"manifest={claimed or 'MISSING'}"
            ),
        )
    routed_dcp_hash = manifest.get("ROUTED_DCP_SHA256")
    actual_routed_dcp_hash = (
        _sha256(result.paths.routed_dcp)
        if result.paths.routed_dcp is not None
        and result.paths.routed_dcp.is_file()
        else None
    )
    result.add_assertion(
        "baseline_manifest.ROUTED_DCP_SHA256",
        _is_sha256(routed_dcp_hash)
        and actual_routed_dcp_hash is not None
        and routed_dcp_hash.lower() == actual_routed_dcp_hash,
        (
            f"dcp={result.paths.routed_dcp}, "
            f"local={actual_routed_dcp_hash or 'MISSING'}, "
            f"manifest={routed_dcp_hash or 'MISSING'}"
        ),
    )

    hashes = {
        "UTILIZATION_REPORT_SHA256": result.paths.utilization,
        "HIERARCHICAL_REPORT_SHA256": result.paths.hierarchy,
        "TIMING_REPORT_SHA256": result.paths.timing,
        "DRC_REPORT_SHA256": result.paths.drc,
    }
    if result.paths.route is not None:
        hashes["ROUTE_REPORT_SHA256"] = result.paths.route
    if result.paths.check_timing is not None:
        hashes["CHECK_TIMING_REPORT_SHA256"] = result.paths.check_timing
    for key, path in hashes.items():
        expected_hash = manifest.get(key, "").lower()
        actual_hash = _sha256(path)
        result.add_assertion(
            f"baseline_manifest.{key}",
            expected_hash == actual_hash,
            f"actual={actual_hash}, manifest={expected_hash or 'MISSING'}",
        )


def _verify_ila_checksums(result: MethodResult, root: Path) -> None:
    index_path = result.paths.checksum_index
    if index_path is None or not index_path.is_file():
        result.add_assertion(
            "ila_checksum_index", False, "Step 5 checksum index is missing"
        )
        return
    index = parse_checksum_index(_read_text(index_path))
    for path in (
        result.paths.utilization,
        result.paths.hierarchy,
        result.paths.timing,
        result.paths.drc,
        result.paths.route,
        result.paths.routed_dcp,
        result.paths.manifest,
    ):
        if path is None:
            continue
        try:
            relative = path.relative_to(root).as_posix()
        except ValueError:
            relative = path.as_posix()
        expected = index.get(relative)
        actual = _sha256(path)
        result.add_assertion(
            f"ila_checksum.{relative}",
            expected == actual,
            f"actual={actual}, index={expected or 'MISSING'}",
        )


def _verify_ila_build_manifest(result: MethodResult) -> None:
    path = result.paths.manifest
    if path is None or not path.is_file():
        result.add_assertion(
            "ila_build_manifest", False, "Step 5 build manifest is missing"
        )
        return
    manifest = parse_colon_manifest(_read_text(path))
    exact_expected = {
        "FPGA Part": REQUIRED_PART,
        "Board Part": REQUIRED_BOARD_PART,
        "Top": REQUIRED_TOP,
        "Synthesis Strategy": "Vivado Synthesis Defaults",
        "Implementation Strategy": "Vivado Implementation Defaults",
        "Synthesis Status": "synth_design Complete!",
        "Implementation Status": "route_design Complete!",
        "sys_clock Period (ns)": "10.000",
        "Internal Unconstrained": "0",
        "Fully Placed": "PASS",
        "Fully Routed": "PASS",
        "Route Errors": "0",
        "DRC Errors": "0",
        "DRC Critical Warnings": "0",
    }
    for key, expected in exact_expected.items():
        actual = manifest.get(key)
        result.add_assertion(
            f"ila_manifest.{key}",
            actual == expected,
            f"actual={actual!r}, expected={expected!r}",
        )
    vivado = manifest.get("Vivado", "")
    result.add_assertion(
        "ila_manifest.Vivado",
        f"v{REQUIRED_VIVADO}" in vivado,
        f"actual={vivado!r}",
    )
    routed_dcp_hash = manifest.get("Routed DCP SHA-256")
    actual_routed_dcp_hash = (
        _sha256(result.paths.routed_dcp)
        if result.paths.routed_dcp is not None
        and result.paths.routed_dcp.is_file()
        else None
    )
    result.add_assertion(
        "ila_manifest.Routed_DCP_SHA256",
        _is_sha256(routed_dcp_hash)
        and actual_routed_dcp_hash is not None
        and routed_dcp_hash.lower() == actual_routed_dcp_hash,
        (
            f"dcp={result.paths.routed_dcp}, "
            f"local={actual_routed_dcp_hash or 'MISSING'}, "
            f"manifest={routed_dcp_hash or 'MISSING'}"
        ),
    )


def _manifest_alias_value(
    manifest: Mapping[str, str], aliases: Sequence[str]
) -> tuple[str | None, str]:
    found = [(key, manifest[key]) for key in aliases if key in manifest]
    if not found:
        return None, f"missing; accepted keys={list(aliases)!r}"
    distinct = {value for _, value in found}
    if len(distinct) != 1:
        return None, f"conflicting aliases={found!r}"
    value = found[0][1]
    return value, f"{','.join(key for key, _ in found)}={value!r}"


def _is_sha256(value: str | None) -> bool:
    return value is not None and SHA256_PATTERN.fullmatch(value) is not None


def _verify_custom_build_manifest(
    result: MethodResult, root: Path
) -> None:
    """Require evidence needed before a Custom report enters official savings."""

    path = result.paths.manifest
    if path is None or not path.is_file():
        result.add_assertion(
            "custom_build_manifest",
            False,
            "Custom build manifest is required for official comparison",
        )
        return
    manifest = parse_key_value_manifest(_read_text(path))
    exact_expected = {
        "OVERALL": "PASS",
        "VIVADO_VERSION": REQUIRED_VIVADO,
        "FPGA_PART": REQUIRED_PART,
        "BOARD_PART": REQUIRED_BOARD_PART,
        "TOP": REQUIRED_TOP,
        "DESIGN_STATE": "ROUTED",
        "CLOCK_HZ": "100000000",
        "CLOCK_PERIOD_NS": "10.000",
        "SYNTHESIS_STRATEGY": "Vivado Synthesis Defaults",
        "IMPLEMENTATION_STRATEGY": "Vivado Implementation Defaults",
        "VIVADO_ILA_COUNT": "0",
        "VIO_COUNT": "0",
        "DEBUG_CORE_COUNT": "0",
        "GENERATOR_HIERARCHY_COUNT": "1",
    }
    for key, expected in exact_expected.items():
        actual = manifest.get(key)
        result.add_assertion(
            f"custom_manifest.{key}",
            actual == expected,
            f"actual={actual!r}, expected={expected!r}",
        )
    allowed_scopes = {
        "CUSTOM_WHOLE_ROUTED_SOC",
        "CUSTOM_FULL_SYSTEM",
        "WHOLE_ROUTED_SOC_CUSTOM",
    }
    actual_scope = manifest.get("BUILD_SCOPE")
    result.add_assertion(
        "custom_manifest.BUILD_SCOPE",
        actual_scope in allowed_scopes,
        f"actual={actual_scope!r}, allowed={sorted(allowed_scopes)!r}",
    )

    git_commit = manifest.get("GIT_COMMIT")
    result.add_assertion(
        "custom_manifest.GIT_COMMIT",
        git_commit is not None
        and GIT_COMMIT_PATTERN.fullmatch(git_commit) is not None,
        f"actual={git_commit!r}; expected 40- or 64-hex Git object id",
    )
    git_dirty = manifest.get("GIT_WORKTREE_DIRTY")
    result.add_assertion(
        "custom_manifest.GIT_WORKTREE_DIRTY",
        git_dirty is not None
        and git_dirty.strip().lower() in {"0", "1", "true", "false"},
        f"actual={git_dirty!r}; expected explicit 0/1/true/false",
    )

    _verify_canonical_common_source_hashes(
        result, manifest, root, "custom_manifest"
    )

    for component, aliases in CUSTOM_COMPONENT_COUNT_KEYS.items():
        actual, detail = _manifest_alias_value(manifest, aliases)
        result.add_assertion(
            f"custom_manifest.component_count.{component}",
            actual == "1",
            f"{detail}; expected exactly one",
        )
    capture_included, capture_detail = _manifest_alias_value(
        manifest,
        ("CAPTURE_BRAM_INCLUDED", "CUSTOM_CAPTURE_BRAM_INCLUDED"),
    )
    result.add_assertion(
        "custom_manifest.CAPTURE_BRAM_INCLUDED",
        capture_included is not None
        and capture_included.strip().lower() in {"1", "true", "yes"},
        f"{capture_detail}; expected explicit 1/true/yes",
    )

    for component, aliases in CUSTOM_SOURCE_HASH_KEYS.items():
        source_hash, detail = _manifest_alias_value(manifest, aliases)
        result.add_assertion(
            f"custom_manifest.source_hash.{component}",
            _is_sha256(source_hash),
            f"{detail}; expected non-empty 64-hex SHA-256",
        )

    routed_dcp_hash = manifest.get("ROUTED_DCP_SHA256")
    actual_routed_dcp_hash = (
        _sha256(result.paths.routed_dcp)
        if result.paths.routed_dcp is not None
        and result.paths.routed_dcp.is_file()
        else None
    )
    result.add_assertion(
        "custom_manifest.ROUTED_DCP_SHA256",
        _is_sha256(routed_dcp_hash)
        and actual_routed_dcp_hash is not None
        and routed_dcp_hash.lower() == actual_routed_dcp_hash,
        (
            f"dcp={result.paths.routed_dcp}, "
            f"local={actual_routed_dcp_hash or 'MISSING'}, "
            f"manifest={routed_dcp_hash or 'MISSING'}"
        ),
    )

    hashes = {
        "UTILIZATION_REPORT_SHA256": result.paths.utilization,
        "HIERARCHICAL_REPORT_SHA256": result.paths.hierarchy,
        "TIMING_REPORT_SHA256": result.paths.timing,
        "DRC_REPORT_SHA256": result.paths.drc,
    }
    if result.paths.route is not None:
        hashes["ROUTE_REPORT_SHA256"] = result.paths.route
    else:
        result.add_assertion(
            "custom_manifest.ROUTE_REPORT_SHA256",
            False,
            "Custom route report path is required",
        )
    for key, report_path in hashes.items():
        expected_hash = manifest.get(key, "").lower()
        actual_hash = _sha256(report_path)
        result.add_assertion(
            f"custom_manifest.{key}",
            _is_sha256(expected_hash) and expected_hash == actual_hash,
            f"actual={actual_hash}, manifest={expected_hash or 'MISSING'}",
        )


def _verify_cpu_provenance(result: MethodResult) -> None:
    provenance_path = result.paths.provenance
    if provenance_path is None or not provenance_path.is_file():
        result.add_assertion(
            "cpu_drive_provenance",
            False,
            "Drive source manifest is missing",
        )
        return
    provenance = parse_key_value_manifest(_read_text(provenance_path))
    result.add_assertion(
        "cpu_drive_fetch_mode",
        provenance.get("FETCH_MODE") == "GOOGLE_DRIVE_READ_ONLY",
        f"FETCH_MODE={provenance.get('FETCH_MODE')!r}",
    )
    for name, path in (
        ("utilization.rpt", result.paths.utilization),
        ("hierarchical_utilization.rpt", result.paths.hierarchy),
        ("timing_summary.rpt", result.paths.timing),
        ("drc.rpt", result.paths.drc),
    ):
        id_key = f"FILE.{name}.ID"
        size_key = f"FILE.{name}.SIZE_BYTES"
        expected_size = provenance.get(size_key)
        result.add_assertion(
            f"cpu_drive_id.{name}",
            bool(provenance.get(id_key)),
            f"{id_key}={provenance.get(id_key)!r}",
        )
        result.add_assertion(
            f"cpu_drive_size.{name}",
            expected_size is not None
            and expected_size.isdigit()
            and int(expected_size) == path.stat().st_size,
            f"local={path.stat().st_size}, manifest={expected_size!r}",
        )


def _verify_custom_hierarchy(result: MethodResult) -> None:
    component_matches = {
        component: find_hierarchy_rows(result.hierarchy_rows, aliases)
        for component, aliases in CUSTOM_COMPONENT_ALIASES.items()
    }
    custom_components = {
        component: matches[0] if len(matches) == 1 else None
        for component, matches in component_matches.items()
    }
    for component, matches in component_matches.items():
        result.add_assertion(
            f"custom_component_exactly_one.{component}",
            len(matches) == 1,
            (
                f"instance={matches[0].instance!r}"
                if len(matches) == 1
                else (
                    f"matched_instances="
                    f"{[row.instance for row in matches]!r}; "
                    "accepted aliases="
                    f"{CUSTOM_COMPONENT_ALIASES[component]!r}; "
                    "expected exactly one"
                )
            ),
        )
    found_instances = [
        row.instance for row in custom_components.values() if row is not None
    ]
    result.add_assertion(
        "custom_components_are_separate_hierarchies",
        len(found_instances) == len(CUSTOM_COMPONENT_ALIASES)
        and len(set(found_instances)) == len(CUSTOM_COMPONENT_ALIASES),
        f"matched_instances={found_instances!r}",
    )
    capture_bram = custom_components["capture_bram"]
    result.add_assertion(
        "custom_capture_bram_exact_primitive_count",
        capture_bram is not None
        and capture_bram.ramb36 == 1
        and capture_bram.ramb18 == 0,
        (
            "capture BRAM missing"
            if capture_bram is None
            else (
                f"instance={capture_bram.instance}, "
                f"RAMB36={capture_bram.ramb36}, "
                f"RAMB18={capture_bram.ramb18}; expected 1/0"
            )
        ),
    )

    for instance, allowed_modules in (
        CUSTOM_REQUIRED_COMMON_HIERARCHIES.items()
    ):
        instance_matches = find_hierarchy_rows(
            result.hierarchy_rows, (instance,)
        )
        if instance == "microblaze_riscv_0_local_memory":
            matches = [
                row
                for row in instance_matches
                if re.fullmatch(
                    r"microblaze_riscv_0_local_memory_imp_[A-Za-z0-9]+",
                    row.module,
                )
            ]
            module_contract = (
                "microblaze_riscv_0_local_memory_imp_<alphanumeric>"
            )
        else:
            matches = [
                row
                for row in instance_matches
                if row.module in allowed_modules
            ]
            module_contract = repr(allowed_modules)
        result.add_assertion(
            f"custom_common_base_exactly_one.{instance}",
            len(instance_matches) == 1 and len(matches) == 1,
            (
                f"matching_instance_module_rows={len(matches)}, "
                "actual="
                f"{[(row.instance, row.module) for row in instance_matches]!r}, "
                f"required_module={module_contract}"
            ),
        )
    local_memory = find_hierarchy_rows(
        result.hierarchy_rows,
        ("microblaze_riscv_0_local_memory",),
    )
    result.add_assertion(
        "custom_common_local_memory_128kib_bram",
        len(local_memory) == 1
        and local_memory[0].ramb36 == 32
        and local_memory[0].ramb18 == 0,
        (
            "local memory missing/duplicated"
            if len(local_memory) != 1
            else (
                f"RAMB36={local_memory[0].ramb36}, "
                f"RAMB18={local_memory[0].ramb18}; expected 32/0"
            )
        ),
    )
    forbidden_debug = _detect_forbidden_debug_cores(
        result.hierarchy_rows
    )
    result.add_assertion(
        "custom_has_no_ila_vio_or_debug_hub",
        not forbidden_debug,
        "none" if not forbidden_debug else ", ".join(forbidden_debug),
    )


def load_and_validate_method(spec: MethodSpec, root: Path) -> MethodResult:
    initial_status, detail = _path_state(spec)
    result = MethodResult(
        key=spec.key,
        label=spec.label,
        scope=spec.scope,
        paths=spec.paths,
        status=initial_status,
        detail=detail,
    )
    if initial_status != STATUS_VERIFIED:
        return result

    try:
        utilization_text = _read_text(spec.paths.utilization)
        hierarchy_text = _read_text(spec.paths.hierarchy)
        timing_text = _read_text(spec.paths.timing)
        drc_text = _read_text(spec.paths.drc)
        util_metadata, result.resources = parse_utilization_text(
            utilization_text
        )
        hierarchy_metadata, result.hierarchy_rows = parse_hierarchy_text(
            hierarchy_text
        )
        timing_metadata, result.timing = parse_timing_text(timing_text)
        drc_metadata, result.drc = parse_drc_text(drc_text)
        result.metadata = util_metadata
        if spec.paths.route is not None:
            result.route = parse_route_text(_read_text(spec.paths.route))
    except (OSError, ReportError) as exc:
        result.status = STATUS_INVALID
        result.detail = str(exc)
        result.assertions.append(("report_parse", "FAIL", str(exc)))
        return result

    for label, metadata in (
        ("utilization", util_metadata),
        ("hierarchy", hierarchy_metadata),
        ("timing", timing_metadata),
        ("drc", drc_metadata),
    ):
        errors = _metadata_compatible(metadata)
        result.add_assertion(
            f"{label}_metadata",
            not errors,
            "compatible" if not errors else "; ".join(errors),
        )
        result.add_assertion(
            f"{label}_identity",
            _same_report_identity(util_metadata, metadata),
            (
                f"reference={util_metadata.design}/"
                f"{util_metadata.vivado_version}, "
                f"actual={metadata.design}/{metadata.vivado_version}"
            ),
        )

    assert result.timing is not None
    timing = result.timing
    result.add_assertion(
        "clock_period",
        _float_equal(timing.clock_period_ns, REQUIRED_CLOCK_PERIOD_NS),
        (
            f"actual={timing.clock_period_ns:.3f} ns, "
            f"expected={REQUIRED_CLOCK_PERIOD_NS:.3f} ns"
        ),
    )
    result.add_assertion(
        "clock_frequency",
        _float_equal(
            timing.clock_frequency_mhz, REQUIRED_CLOCK_FREQUENCY_MHZ
        ),
        (
            f"actual={timing.clock_frequency_mhz:.3f} MHz, "
            f"expected={REQUIRED_CLOCK_FREQUENCY_MHZ:.3f} MHz"
        ),
    )
    result.add_assertion(
        "setup_timing",
        timing.constraints_met and timing.wns_ns >= 0.0 and timing.tns_ns == 0.0,
        f"WNS={timing.wns_ns:.3f}, TNS={timing.tns_ns:.3f}",
    )
    result.add_assertion(
        "hold_timing",
        timing.whs_ns >= 0.0 and timing.ths_ns == 0.0,
        f"WHS={timing.whs_ns:.3f}, THS={timing.ths_ns:.3f}",
    )
    result.add_assertion(
        "pulse_width_timing",
        timing.wpws_ns >= 0.0 and timing.tpws_ns == 0.0,
        f"WPWS={timing.wpws_ns:.3f}, TPWS={timing.tpws_ns:.3f}",
    )
    result.add_assertion(
        "internal_unconstrained_endpoints",
        timing.internal_unconstrained_endpoints == 0,
        f"count={timing.internal_unconstrained_endpoints}",
    )

    assert result.drc is not None
    result.add_assertion(
        "drc_no_errors",
        result.drc.errors == 0 and result.drc.critical_warnings == 0,
        (
            f"errors={result.drc.errors}, "
            f"critical_warnings={result.drc.critical_warnings}, "
            f"warnings={result.drc.warnings}"
        ),
    )
    if spec.key in {"common_baseline", "ila_reference", "custom"}:
        result.add_assertion(
            "drc_full_design_default_bitstream_no_waivers",
            result.drc.full_scope_contract,
            (
                f"entire_design={result.drc.entire_design}, "
                f"ruledecks={result.drc.ruledecks!r}, "
                "max_checks_unlimited="
                f"{result.drc.max_checks_unlimited}, "
                f"no_waivers={result.drc.no_waivers}, "
                f"command_is_report_drc="
                f"{result.drc.command_is_report_drc}, "
                f"command_ruledecks={result.drc.command_ruledecks!r}, "
                f"scope_filter_absent="
                f"{result.drc.scope_filter_absent}"
            ),
        )
    if spec.require_route:
        result.add_assertion(
            "fully_routed_zero_errors",
            result.route is not None and result.route.fully_routed,
            (
                "route report unavailable"
                if result.route is None
                else (
                    f"routable={result.route.routable_nets}, "
                    f"fully_routed={result.route.fully_routed_nets}, "
                    f"errors={result.route.routing_errors}"
                )
            ),
        )

    top_row = find_hierarchy_row(result.hierarchy_rows, (REQUIRED_TOP,))
    result.add_assertion(
        "hierarchy_top_matches_total",
        top_row is not None
        and top_row.as_resource_metrics() == result.resources,
        (
            "top hierarchy row missing"
            if top_row is None
            else (
                f"hierarchy={top_row.as_resource_metrics()}, "
                f"total={result.resources}"
            )
        ),
    )
    generator = _generator_row(result.hierarchy_rows)
    result.add_assertion(
        "common_generator_present",
        generator is not None,
        "found" if generator is not None else "missing",
    )
    if generator is not None:
        expected_generator = ResourceMetrics(110, 110, 0, 65, 0, 0, 0)
        result.add_assertion(
            "common_generator_frozen_hierarchy",
            generator.as_resource_metrics() == expected_generator,
            (
                f"actual={generator.as_resource_metrics()}, "
                f"expected={expected_generator}"
            ),
        )

    if spec.key in {"common_baseline", "cpu_polling"}:
        forbidden = _detect_forbidden_analyzers(result.hierarchy_rows)
        result.add_assertion(
            "no_analyzer_debug_hierarchy",
            not forbidden,
            "none" if not forbidden else ", ".join(forbidden),
        )
    elif spec.key == "ila_reference":
        result.add_assertion(
            "official_ila_present",
            find_hierarchy_row(
                result.hierarchy_rows, ("ila_reference_0",)
            )
            is not None,
            "expected exact instance ila_reference_0",
        )
        result.add_assertion(
            "required_debug_hub_present",
            find_hierarchy_row(result.hierarchy_rows, ("dbg_hub",))
            is not None,
            "expected exact instance dbg_hub",
        )
    elif spec.key == "custom":
        _verify_custom_hierarchy(result)

    if spec.expected_resources is not None:
        result.add_assertion(
            "frozen_resource_snapshot",
            result.resources == spec.expected_resources,
            (
                f"actual={result.resources}, "
                f"expected={spec.expected_resources}"
            ),
        )
    if spec.expected_timing is not None:
        actual_timing = (
            timing.wns_ns,
            timing.tns_ns,
            timing.whs_ns,
            timing.ths_ns,
            timing.wpws_ns,
            timing.tpws_ns,
        )
        result.add_assertion(
            "frozen_timing_snapshot",
            all(
                _float_equal(actual, expected)
                for actual, expected in zip(
                    actual_timing, spec.expected_timing, strict=True
                )
            ),
            f"actual={actual_timing}, expected={spec.expected_timing}",
        )

    try:
        if spec.key == "common_baseline" and spec.paths.manifest is not None:
            _verify_baseline_manifest(
                result,
                parse_key_value_manifest(_read_text(spec.paths.manifest)),
                root,
            )
        elif spec.key == "ila_reference":
            _verify_ila_build_manifest(result)
            _verify_ila_checksums(result, root)
        elif spec.key == "cpu_polling":
            _verify_cpu_provenance(result)
        elif spec.key == "custom":
            _verify_custom_build_manifest(result, root)
    except (OSError, ReportError) as exc:
        result.add_assertion(
            "manifest_or_provenance_parse",
            False,
            str(exc),
        )

    if result.status == STATUS_VERIFIED:
        result.detail = "whole routed SoC reports verified"
    else:
        result.detail = "one or more report assertions failed"
    return result


COMMON_SOURCE_MANIFEST_PAIRS: tuple[tuple[str, str], ...] = (
    ("BASE_SOC_TCL_SHA256", "Base SoC Tcl SHA-256"),
    (
        "GENERATOR_INTEGRATION_TCL_SHA256",
        "Generator Integration Tcl SHA-256",
    ),
    ("GENERATOR_RTL_SHA256", "Generator Core RTL SHA-256"),
    ("GENERATOR_ADAPTER_SHA256", "Generator Adapter RTL SHA-256"),
)


def _compare_common_source_hashes(
    baseline_manifest: Mapping[str, str],
    ila_manifest: Mapping[str, str],
) -> list[str]:
    mismatches: list[str] = []
    for baseline_key, ila_key in COMMON_SOURCE_MANIFEST_PAIRS:
        baseline_hash = baseline_manifest.get(baseline_key)
        ila_hash = ila_manifest.get(ila_key)
        if (
            not _is_sha256(baseline_hash)
            or not _is_sha256(ila_hash)
            or baseline_hash.lower() != ila_hash.lower()
        ):
            mismatches.append(
                f"{baseline_key}={baseline_hash!r}, {ila_key}={ila_hash!r}"
            )
    return mismatches


def _cross_validate(
    results: Mapping[str, MethodResult],
) -> list[tuple[str, str, str]]:
    assertions: list[tuple[str, str, str]] = []
    verified = [result for result in results.values() if result.verified]
    identities = {
        (
            result.metadata.vivado_version,
            result.metadata.design,
            REQUIRED_PART,
            result.timing.clock_period_ns,
        )
        for result in verified
        if result.metadata is not None and result.timing is not None
    }
    assertions.append(
        (
            "same_tool_part_top_clock",
            "PASS" if len(identities) <= 1 else "FAIL",
            repr(sorted(identities)),
        )
    )

    generator_rows = [
        _generator_row(result.hierarchy_rows)
        for result in verified
        if result.key in {
            "common_baseline",
            "cpu_polling",
            "ila_reference",
            "custom",
        }
    ]
    generator_metrics = {
        row.as_resource_metrics()
        for row in generator_rows
        if row is not None
    }
    assertions.append(
        (
            "same_common_generator_hierarchy",
            (
                "PASS"
                if generator_rows
                and all(row is not None for row in generator_rows)
                and len(generator_metrics) == 1
                else "FAIL"
            ),
            repr(sorted(map(str, generator_metrics))),
        )
    )

    baseline = results.get("common_baseline")
    ila = results.get("ila_reference")
    if (
        baseline is not None
        and baseline.verified
        and baseline.paths.manifest is not None
        and baseline.paths.manifest.is_file()
        and ila is not None
        and ila.verified
        and ila.paths.manifest is not None
        and ila.paths.manifest.is_file()
    ):
        baseline_manifest = parse_key_value_manifest(
            _read_text(baseline.paths.manifest)
        )
        ila_manifest = parse_colon_manifest(_read_text(ila.paths.manifest))
        source_mismatches = _compare_common_source_hashes(
            baseline_manifest, ila_manifest
        )
        assertions.append(
            (
                "same_common_base_generator_source_hashes",
                "PASS" if not source_mismatches else "FAIL",
                "matched" if not source_mismatches else "; ".join(source_mismatches),
            )
        )
    else:
        assertions.append(
            (
                "same_common_base_generator_source_hashes",
                "NOT_APPLICABLE",
                "requires verified baseline and ILA build manifests",
            )
        )
    return assertions


def _resolve_path(root: Path, value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else root / path


def build_specs(
    root: Path,
    baseline_dir: Path,
    ila_dir: Path,
    cpu_dir: Path,
    custom_dir: Path,
) -> list[MethodSpec]:
    return [
        MethodSpec(
            key="common_baseline",
            label="Common Base + Generator",
            scope="COMMON_BASE_PLUS_GENERATOR_WHOLE_ROUTED_SOC",
            paths=MethodPaths(
                utilization=baseline_dir / "baseline_utilization.rpt",
                hierarchy=baseline_dir
                / "baseline_hierarchical_utilization.rpt",
                timing=baseline_dir / "baseline_timing_summary.rpt",
                drc=baseline_dir / "baseline_drc.rpt",
                route=baseline_dir / "baseline_route_status.rpt",
                routed_dcp=root
                / "build/step9_common_baseline"
                / "common_base_plus_generator_routed.dcp",
                check_timing=baseline_dir / "baseline_check_timing.rpt",
                manifest=baseline_dir / "baseline_build_manifest.rpt",
                completion_log=baseline_dir / "baseline_build.log",
            ),
            require_route=True,
        ),
        MethodSpec(
            key="cpu_polling",
            label="CPU Polling",
            scope="CPU_POLLING_WHOLE_ROUTED_SOC_REFERENCE_ONLY",
            paths=MethodPaths(
                utilization=cpu_dir / "utilization.rpt",
                hierarchy=cpu_dir / "hierarchical_utilization.rpt",
                timing=cpu_dir / "timing_summary.rpt",
                drc=cpu_dir / "drc.rpt",
                provenance=cpu_dir / "drive_source_manifest.rpt",
            ),
            require_route=False,
            expected_resources=ResourceMetrics(
                2782, 2644, 138, 2560, 32, 0, 0
            ),
            expected_timing=(0.939, 0.000, 0.047, 0.000, 3.000, 0.000),
        ),
        MethodSpec(
            key="ila_reference",
            label="Vivado ILA",
            scope="VIVADO_ILA_WHOLE_ROUTED_SOC",
            paths=MethodPaths(
                utilization=ila_dir
                / "ila_reference_step5_utilization.rpt",
                hierarchy=ila_dir
                / "ila_reference_step5_hierarchical_utilization.rpt",
                timing=ila_dir
                / "ila_reference_step5_timing_summary.rpt",
                drc=ila_dir / "ila_reference_step5_drc.rpt",
                route=ila_dir / "ila_reference_step5_route_status.rpt",
                routed_dcp=root
                / "build/step5/edgescope_ila_reference_routed.dcp",
                manifest=ila_dir
                / "ila_reference_step5_build_manifest.rpt",
                checksum_index=ila_dir
                / "ila_reference_step5_SHA256SUMS",
            ),
            require_route=True,
            expected_resources=ResourceMetrics(
                3726, 3500, 226, 4230, 32, 1, 0
            ),
            expected_timing=(1.544, 0.000, 0.014, 0.000, 3.000, 0.000),
        ),
        MethodSpec(
            key="custom",
            label="EdgeScope Custom",
            scope="CUSTOM_WHOLE_ROUTED_SOC",
            paths=MethodPaths(
                utilization=custom_dir / "utilization.rpt",
                hierarchy=custom_dir / "hierarchical_utilization.rpt",
                timing=custom_dir / "timing_summary.rpt",
                drc=custom_dir / "drc.rpt",
                route=custom_dir / "route_status.rpt",
                routed_dcp=custom_dir / "routed_design.dcp",
                manifest=custom_dir / "build_manifest.rpt",
            ),
            require_route=True,
        ),
    ]


def _fmt_number(value: int | float | None, decimals: int = 3) -> str:
    if value is None:
        return "NA"
    if isinstance(value, int):
        return str(value)
    return f"{value:.{decimals}f}"


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def _csv_text(
    fieldnames: Sequence[str], rows: Iterable[Mapping[str, object]]
) -> str:
    output = io.StringIO(newline="")
    writer = csv.DictWriter(
        output, fieldnames=fieldnames, lineterminator="\n"
    )
    writer.writeheader()
    for row in rows:
        writer.writerow(row)
    return output.getvalue()


def _resource_row(
    result: MethodResult,
    view: str,
    metrics: ResourceMetrics | None,
    note: str,
) -> dict[str, object]:
    if metrics is not None:
        row_status = result.status
    elif result.verified:
        row_status = STATUS_NOT_APPLICABLE
    else:
        # Missing and invalid methods must stay visibly missing/invalid.  NA
        # values are not allowed to disguise NOT_RECEIVED as NOT_APPLICABLE.
        row_status = result.status
    return {
        "method": result.key,
        "method_label": result.label,
        "view": view,
        "status": row_status,
        "slice_luts": _fmt_number(
            None if metrics is None else metrics.slice_luts
        ),
        "lut_as_logic": _fmt_number(
            None if metrics is None else metrics.lut_as_logic
        ),
        "lut_as_memory": _fmt_number(
            None if metrics is None else metrics.lut_as_memory
        ),
        "slice_registers": _fmt_number(
            None if metrics is None else metrics.slice_registers
        ),
        "ramb36": _fmt_number(None if metrics is None else metrics.ramb36),
        "ramb18": _fmt_number(None if metrics is None else metrics.ramb18),
        "bram_tile_equiv": _fmt_number(
            None if metrics is None else metrics.bram_tile_equiv,
            decimals=1,
        ),
        "dsp48e1": _fmt_number(
            None if metrics is None else metrics.dsp48e1
        ),
        "note": note,
    }


def _official_savings_rows(
    results: Mapping[str, MethodResult],
    cross_assertions: Sequence[tuple[str, str, str]] = (),
) -> list[dict[str, object]]:
    fields = (
        ("slice_luts", "Slice LUTs"),
        ("lut_as_logic", "LUT as Logic"),
        ("lut_as_memory", "LUT as Memory"),
        ("slice_registers", "Slice Registers"),
        ("ramb36", "RAMB36"),
        ("ramb18", "RAMB18"),
        ("dsp48e1", "DSP48E1"),
    )
    baseline = results["common_baseline"]
    ila = results["ila_reference"]
    custom = results["custom"]
    cross_failed = any(
        status == "FAIL" for _, status, _ in cross_assertions
    )
    available = (
        baseline.verified
        and ila.verified
        and custom.verified
        and baseline.resources is not None
        and ila.resources is not None
        and custom.resources is not None
    )
    rows: list[dict[str, object]] = []
    if cross_failed or not available:
        reason = (
            "BLOCKED_CROSS_METHOD_VALIDATION"
            if cross_failed
            else (
                "PENDING_CUSTOM_FULL_SYSTEM_REPORT"
                if custom.status == STATUS_NOT_RECEIVED
                else "PENDING_VERIFIED_BASELINE_ILA_CUSTOM"
            )
        )
        for attribute, label in fields:
            rows.append(
                {
                    "metric": attribute,
                    "metric_label": label,
                    "status": reason,
                    "ila_delta": "NA",
                    "custom_delta": "NA",
                    "saved_absolute": "NA",
                    "saved_percent_of_ila_delta": "NA",
                    "note": (
                        "CPU Polling is excluded from official savings; "
                        "no value is imputed as zero."
                    ),
                }
            )
        return rows

    assert baseline.resources is not None
    assert ila.resources is not None
    assert custom.resources is not None
    ila_delta = ila.resources.subtract(baseline.resources)
    custom_delta = custom.resources.subtract(baseline.resources)
    for attribute, label in fields:
        ila_value = getattr(ila_delta, attribute)
        custom_value = getattr(custom_delta, attribute)
        saved = ila_value - custom_value
        percent = None if ila_value <= 0 else (100.0 * saved / ila_value)
        rows.append(
            {
                "metric": attribute,
                "metric_label": label,
                "status": (
                    STATUS_VERIFIED
                    if percent is not None
                    else STATUS_NOT_APPLICABLE
                ),
                "ila_delta": ila_value,
                "custom_delta": custom_value,
                "saved_absolute": saved,
                "saved_percent_of_ila_delta": (
                    "NA" if percent is None else f"{percent:.2f}"
                ),
                "note": (
                    "Official whole-routed-SoC delta comparison; CPU Polling "
                    "excluded."
                ),
            }
        )
    return rows


def _completion_status_fields(
    results: Mapping[str, MethodResult],
    cross_assertions: Sequence[tuple[str, str, str]] = (),
) -> dict[str, str]:
    """Gate public completion claims on every method and cross-check."""

    required_keys = (
        "common_baseline",
        "cpu_polling",
        "ila_reference",
        "custom",
    )
    unverified = [key for key in required_keys if not results[key].verified]
    cross_failed = any(
        status == "FAIL" for _, status, _ in cross_assertions
    )
    custom = results["custom"]
    other_unverified = [key for key in unverified if key != "custom"]
    if not unverified and not cross_failed:
        three_way = "COMPLETE"
        next_action = "STEP10_FINAL_PACKAGE"
    elif (
        custom.status == STATUS_NOT_RECEIVED
        and not other_unverified
        and not cross_failed
    ):
        three_way = "PARTIAL_AWAITING_CUSTOM"
        next_action = "RECEIVE_CUSTOM_FULL_SYSTEM_REPORTS"
    elif custom.status == STATUS_NOT_RECEIVED and other_unverified:
        methods = ",".join(other_unverified).upper()
        three_way = (
            "BLOCKED_CUSTOM_NOT_RECEIVED_AND_METHODS_"
            f"{methods}"
        )
        next_action = "RECEIVE_CUSTOM_AND_VERIFY_ALL_METHOD_REPORTS"
    elif custom.status != STATUS_NOT_RECEIVED and not custom.verified:
        three_way = f"BLOCKED_CUSTOM_{custom.status}"
        next_action = "FIX_CUSTOM_FULL_SYSTEM_INPUT"
    elif other_unverified:
        methods = ",".join(other_unverified).upper()
        three_way = f"BLOCKED_METHODS_{methods}"
        next_action = "VERIFY_ALL_METHOD_REPORTS"
    elif cross_failed:
        three_way = "BLOCKED_CROSS_METHOD_VALIDATION"
        next_action = "FIX_CROSS_METHOD_VALIDATION"
    else:
        three_way = "INCOMPLETE"
        next_action = "VERIFY_ALL_METHOD_REPORTS"

    savings_inputs_verified = all(
        results[key].verified
        for key in ("common_baseline", "ila_reference", "custom")
    )
    if cross_failed:
        savings = "BLOCKED_CROSS_METHOD_VALIDATION"
    elif savings_inputs_verified:
        savings = "VERIFIED"
    elif custom.status == STATUS_NOT_RECEIVED:
        savings = "PENDING_CUSTOM"
    elif not custom.verified:
        savings = f"BLOCKED_CUSTOM_{custom.status}"
    else:
        savings = "BLOCKED_UNVERIFIED_BASELINE_OR_ILA"

    return {
        "THREE_WAY_COMPARISON": three_way,
        "OFFICIAL_CUSTOM_VS_ILA_SAVINGS": savings,
        "NEXT_ACTION": next_action,
    }


def write_outputs(
    root: Path,
    output_dir: Path,
    specs: Sequence[MethodSpec],
    results: Mapping[str, MethodResult],
    cross_assertions: Sequence[tuple[str, str, str]],
) -> str:
    output_dir.mkdir(parents=True, exist_ok=True)
    baseline = results["common_baseline"]
    custom = results["custom"]
    ila = results["ila_reference"]
    cpu = results["cpu_polling"]

    repository_root = root
    for candidate in (root, *root.parents):
        if (candidate / ".git").exists():
            repository_root = candidate
            break

    def display_path(path: Path) -> str:
        try:
            return path.resolve().relative_to(repository_root.resolve()).as_posix()
        except ValueError:
            return path.resolve().as_posix()

    if baseline.status == STATUS_BUILD_IN_PROGRESS:
        overall = "BLOCKED_BASELINE_BUILD_IN_PROGRESS"
    elif baseline.status in {STATUS_NOT_RECEIVED, STATUS_INCOMPLETE}:
        overall = "BLOCKED_BASELINE_NOT_VERIFIED"
    elif any(
        result.status == STATUS_INVALID
        for result in (baseline, cpu, ila, custom)
    ) or any(status == "FAIL" for _, status, _ in cross_assertions):
        overall = "FAIL"
    elif baseline.verified and ila.verified and cpu.verified and custom.verified:
        overall = "PASS"
    elif baseline.verified and ila.verified and cpu.verified:
        overall = "PASS_WITH_TEAM_INPUT_PENDING"
    else:
        overall = "PARTIAL_AWAITING_REPORTS"

    method_rows = []
    for spec in specs:
        result = results[spec.key]
        method_rows.append(
            {
                "method": result.key,
                "method_label": result.label,
                "scope": result.scope,
                "status": result.status,
                "utilization_report": display_path(spec.paths.utilization),
                "hierarchy_report": display_path(spec.paths.hierarchy),
                "timing_report": display_path(spec.paths.timing),
                "route_report": (
                    "NOT_PROVIDED"
                    if spec.paths.route is None
                    else display_path(spec.paths.route)
                ),
                "routed_dcp": (
                    "NOT_PROVIDED"
                    if spec.paths.routed_dcp is None
                    else display_path(spec.paths.routed_dcp)
                ),
                "drc_report": display_path(spec.paths.drc),
                "detail": result.detail,
            }
        )
    method_manifest_path = output_dir / "method_manifest.csv"
    _atomic_write(
        method_manifest_path,
        _csv_text(
            (
                "method",
                "method_label",
                "scope",
                "status",
                "utilization_report",
                "hierarchy_report",
                "timing_report",
                "route_report",
                "routed_dcp",
                "drc_report",
                "detail",
            ),
            method_rows,
        ),
    )

    resource_rows: list[dict[str, object]] = []
    for spec in specs:
        result = results[spec.key]
        resource_rows.append(
            _resource_row(
                result,
                "TOTAL_WHOLE_ROUTED_SOC",
                result.resources if result.verified else None,
                "Vivado routed design total; not analyzer-only overhead.",
            )
        )
        delta: ResourceMetrics | None = None
        delta_note = (
            "Signed TOTAL minus COMMON_BASE_PLUS_GENERATOR; negative values "
            "are preserved."
        )
        if (
            result.verified
            and baseline.verified
            and result.resources is not None
            and baseline.resources is not None
        ):
            delta = result.resources.subtract(baseline.resources)
            if result.key == "cpu_polling":
                delta_note += " Reference only; excluded from official savings."
        resource_rows.append(
            _resource_row(
                result,
                "DELTA_VS_COMMON_BASE_PLUS_GENERATOR",
                delta,
                delta_note,
            )
        )
    resource_path = output_dir / "resource_comparison.csv"
    _atomic_write(
        resource_path,
        _csv_text(
            (
                "method",
                "method_label",
                "view",
                "status",
                "slice_luts",
                "lut_as_logic",
                "lut_as_memory",
                "slice_registers",
                "ramb36",
                "ramb18",
                "bram_tile_equiv",
                "dsp48e1",
                "note",
            ),
            resource_rows,
        ),
    )

    timing_rows = []
    for spec in specs:
        result = results[spec.key]
        timing = result.timing if result.verified else None
        timing_rows.append(
            {
                "method": result.key,
                "method_label": result.label,
                "status": result.status,
                "clock_period_ns": _fmt_number(
                    None if timing is None else timing.clock_period_ns
                ),
                "clock_frequency_mhz": _fmt_number(
                    None if timing is None else timing.clock_frequency_mhz
                ),
                "wns_ns": _fmt_number(
                    None if timing is None else timing.wns_ns
                ),
                "tns_ns": _fmt_number(
                    None if timing is None else timing.tns_ns
                ),
                "whs_ns": _fmt_number(
                    None if timing is None else timing.whs_ns
                ),
                "ths_ns": _fmt_number(
                    None if timing is None else timing.ths_ns
                ),
                "wpws_ns": _fmt_number(
                    None if timing is None else timing.wpws_ns
                ),
                "tpws_ns": _fmt_number(
                    None if timing is None else timing.tpws_ns
                ),
                "internal_unconstrained": (
                    "NA"
                    if timing is None
                    else str(timing.internal_unconstrained_endpoints)
                ),
                "fmax_inference": "FORBIDDEN_NOT_COMPUTED",
                "note": "WNS is slack at 10.000 ns, not an Fmax measurement.",
            }
        )
    timing_path = output_dir / "timing_comparison.csv"
    _atomic_write(
        timing_path,
        _csv_text(
            (
                "method",
                "method_label",
                "status",
                "clock_period_ns",
                "clock_frequency_mhz",
                "wns_ns",
                "tns_ns",
                "whs_ns",
                "ths_ns",
                "wpws_ns",
                "tpws_ns",
                "internal_unconstrained",
                "fmax_inference",
                "note",
            ),
            timing_rows,
        ),
    )

    hierarchy_rows = []
    for spec in specs:
        result = results[spec.key]
        if not result.verified:
            continue
        for role, row, note in _component_rows(
            result.key, result.hierarchy_rows
        ):
            hierarchy_rows.append(
                {
                    "method": result.key,
                    "component_role": role,
                    "instance": row.instance,
                    "module": row.module,
                    "total_luts": row.total_luts,
                    "logic_luts": row.logic_luts,
                    "lutrams": row.lutrams,
                    "srls": row.srls,
                    "ffs": row.ffs,
                    "ramb36": row.ramb36,
                    "ramb18": row.ramb18,
                    "dsp_blocks": row.dsp_blocks,
                    "note": note,
                }
            )
    hierarchy_path = output_dir / "hierarchical_attribution.csv"
    _atomic_write(
        hierarchy_path,
        _csv_text(
            (
                "method",
                "component_role",
                "instance",
                "module",
                "total_luts",
                "logic_luts",
                "lutrams",
                "srls",
                "ffs",
                "ramb36",
                "ramb18",
                "dsp_blocks",
                "note",
            ),
            hierarchy_rows,
        ),
    )

    savings_path = output_dir / "official_custom_vs_ila_savings.csv"
    savings_rows = _official_savings_rows(results, cross_assertions)
    _atomic_write(
        savings_path,
        _csv_text(
            (
                "metric",
                "metric_label",
                "status",
                "ila_delta",
                "custom_delta",
                "saved_absolute",
                "saved_percent_of_ila_delta",
                "note",
            ),
            savings_rows,
        ),
    )

    validation_lines = [
        "# EdgeScope-Lite Step 9 resource/timing validation",
        f"OVERALL={overall}",
        "",
    ]
    for spec in specs:
        result = results[spec.key]
        validation_lines.extend(
            (
                f"[{result.key}]",
                f"STATUS={result.status}",
                f"DETAIL={result.detail}",
            )
        )
        for name, status, detail in result.assertions:
            validation_lines.append(
                f"ASSERT.{name}={status} | {detail}"
            )
        validation_lines.append("")
    validation_lines.append("[cross_method]")
    for name, status, detail in cross_assertions:
        validation_lines.append(f"ASSERT.{name}={status} | {detail}")
    validation_path = output_dir / "resource_timing_validation.rpt"
    _atomic_write(validation_path, "\n".join(validation_lines) + "\n")

    completion_fields = _completion_status_fields(results, cross_assertions)
    custom_pending = custom.status == STATUS_NOT_RECEIVED
    custom_unverified = not custom.verified
    status_lines = [
        "# EdgeScope-Lite Step 9 status",
        f"OVERALL={overall}",
        (
            "BASELINE=VERIFIED"
            if baseline.verified
            else f"BASELINE={baseline.status}"
        ),
        f"CPU_REPORT={cpu.status}",
        (
            "ILA_STEP9=PASS"
            if ila.verified
            else f"ILA_STEP9={ila.status}"
        ),
        f"CUSTOM_FULL_SYSTEM={custom.status}",
        (
            "THREE_WAY_COMPARISON="
            f"{completion_fields['THREE_WAY_COMPARISON']}"
        ),
        (
            "OFFICIAL_CUSTOM_VS_ILA_SAVINGS="
            f"{completion_fields['OFFICIAL_CUSTOM_VS_ILA_SAVINGS']}"
        ),
        "CPU_USED_FOR_OFFICIAL_SAVINGS=NO",
        "RESOURCE_SCOPE=WHOLE_ROUTED_SOC",
        "RESOURCE_VIEWS=TOTAL,DELTA_VS_COMMON_BASE_PLUS_GENERATOR",
        "RAMB36_RAMB18_SEPARATE=YES",
        "FMAX_INFERRED_FROM_WNS=NO",
        f"NEXT_ACTION={completion_fields['NEXT_ACTION']}",
    ]
    status_path = output_dir / "step9_status.rpt"
    _atomic_write(status_path, "\n".join(status_lines) + "\n")

    summary_lines = [
        "# Step 9 — 구현 자원 및 타이밍 비교",
        "",
        f"- 전체 상태: `{overall}`",
        (
            "- 비교 단위: 동일한 `base_soc_wrapper` 전체 Routed SoC "
            "(`xc7a35tcpg236-1`, Vivado 2024.2, `sys_clock` 10.000 ns)"
        ),
        (
            "- 표의 `TOTAL_WHOLE_ROUTED_SOC`와 "
            "`DELTA_VS_COMMON_BASE_PLUS_GENERATOR`는 서로 다른 값이다."
        ),
        "- RAMB36과 RAMB18은 별도 보존하며, Tile 환산값은 참고값이다.",
        "- WNS는 10.000 ns 제약에서의 여유시간이며 Fmax로 환산하지 않았다.",
        "",
        "## 검증된 전체 Routed 결과",
        "",
        "| 비교군 | 상태 | LUT | LUT Logic | LUT Memory | FF | RAMB36 | RAMB18 | WNS (ns) | TNS (ns) |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for spec in specs:
        result = results[spec.key]
        resource = result.resources if result.verified else None
        timing = result.timing if result.verified else None
        summary_lines.append(
            "| "
            + " | ".join(
                (
                    result.label,
                    result.status,
                    _fmt_number(
                        None if resource is None else resource.slice_luts
                    ),
                    _fmt_number(
                        None if resource is None else resource.lut_as_logic
                    ),
                    _fmt_number(
                        None if resource is None else resource.lut_as_memory
                    ),
                    _fmt_number(
                        None
                        if resource is None
                        else resource.slice_registers
                    ),
                    _fmt_number(
                        None if resource is None else resource.ramb36
                    ),
                    _fmt_number(
                        None if resource is None else resource.ramb18
                    ),
                    _fmt_number(None if timing is None else timing.wns_ns),
                    _fmt_number(None if timing is None else timing.tns_ns),
                )
            )
            + " |"
        )
    summary_lines.extend(
        (
            "",
            "## 해석 제한",
            "",
            (
                "- CPU Polling은 기능·성능 비교용 참조군이다. CPU 수치를 "
                "Custom-vs-ILA 공식 자원 절감률 계산에 사용하지 않는다."
            ),
            (
                "- ILA의 `ila_reference_0`와 `dbg_hub` 계층 합은 계층 "
                "귀속값이다. 합성 최적화 때문에 전체 SoC 증분과 같은 값으로 "
                "간주하지 않는다."
            ),
        )
    )
    if custom_pending:
        summary_lines.extend(
            (
                (
                    "- Custom 전체 Routed 리포트가 아직 없으므로 공식 "
                    "Custom-vs-ILA 절감률은 `PENDING_CUSTOM`이다. `NA`를 "
                    "0으로 해석하지 않는다."
                ),
                "",
                "## 다음 입력",
                "",
                (
                    "`results/step9/inputs/custom/`에 동일 조건의 "
                    "`utilization.rpt`, `hierarchical_utilization.rpt`, "
                    "`timing_summary.rpt`, `route_status.rpt`, `drc.rpt`, "
                    "`routed_design.dcp`, `build_manifest.rpt`가 필요하다."
                ),
            )
        )
    elif custom_unverified:
        summary_lines.extend(
            (
                (
                    "- Custom 전체 Routed 입력은 존재하지만 검증에 통과하지 "
                    f"못했다(`{custom.status}`). 공식 절감률은 계산하지 않는다."
                ),
                "",
                "## 다음 조치",
                "",
                (
                    "`resource_timing_validation.rpt`의 Custom FAIL 항목을 "
                    "수정한 뒤 전체 검증을 다시 실행해야 한다."
                ),
            )
        )
    summary_path = output_dir / "comparison_summary.md"
    _atomic_write(summary_path, "\n".join(summary_lines) + "\n")

    manifest_lines = [
        "# EdgeScope-Lite Step 9 extraction manifest",
        f"GENERATED_AT_UTC={dt.datetime.now(dt.timezone.utc).isoformat()}",
        f"OVERALL={overall}",
        f"VALIDATOR_SHA256={_sha256(Path(__file__).resolve())}",
        f"REQUIRED_VIVADO={REQUIRED_VIVADO}",
        f"REQUIRED_PART={REQUIRED_PART}",
        f"REQUIRED_TOP={REQUIRED_TOP}",
        f"REQUIRED_CLOCK_PERIOD_NS={REQUIRED_CLOCK_PERIOD_NS:.3f}",
        "RESOURCE_SCOPE=WHOLE_ROUTED_SOC",
        "DELTA_BASELINE=COMMON_BASE_PLUS_GENERATOR",
        "CPU_USED_FOR_OFFICIAL_SAVINGS=NO",
        "FMAX_INFERENCE=FORBIDDEN_NOT_COMPUTED",
    ]
    for spec in specs:
        result = results[spec.key]
        manifest_lines.append(f"METHOD.{result.key}.STATUS={result.status}")
        for name, path in (
            ("UTILIZATION", spec.paths.utilization),
            ("HIERARCHY", spec.paths.hierarchy),
            ("TIMING", spec.paths.timing),
            ("CHECK_TIMING", spec.paths.check_timing),
            ("DRC", spec.paths.drc),
            ("ROUTE", spec.paths.route),
            ("ROUTED_DCP", spec.paths.routed_dcp),
            ("BUILD_MANIFEST", spec.paths.manifest),
            ("CHECKSUM_INDEX", spec.paths.checksum_index),
            ("PROVENANCE", spec.paths.provenance),
            ("COMPLETION_LOG", spec.paths.completion_log),
        ):
            if path is not None and path.is_file():
                manifest_lines.append(
                    f"INPUT.{result.key}.{name}.SHA256={_sha256(path)}"
                )
                manifest_lines.append(
                    f"INPUT.{result.key}.{name}.SIZE_BYTES={path.stat().st_size}"
                )
                manifest_lines.append(
                    f"INPUT.{result.key}.{name}.PATH={display_path(path)}"
                )

    provenance_paths = {
        "BASELINE_TCL": root / "build_step9_common_baseline.tcl",
        "BASELINE_RUNNER": root / "run_step9_common_baseline.sh",
        "BASELINE_XDC": root / "constraints/step9_baseline_common.xdc",
        "EXTRACTOR_RUNNER": root / "run_step9_resource_timing.sh",
    }
    for label, path in provenance_paths.items():
        if path.is_file():
            manifest_lines.append(
                f"TOOL.{label}.SHA256={_sha256(path)}"
            )
            manifest_lines.append(
                f"TOOL.{label}.SIZE_BYTES={path.stat().st_size}"
            )
            manifest_lines.append(
                f"TOOL.{label}.PATH={display_path(path)}"
            )
    manifest_path = output_dir / "resource_timing_manifest.rpt"
    _atomic_write(manifest_path, "\n".join(manifest_lines) + "\n")

    checksum_targets = (
        method_manifest_path,
        resource_path,
        timing_path,
        hierarchy_path,
        savings_path,
        validation_path,
        status_path,
        summary_path,
        manifest_path,
    )
    checksum_lines = [
        f"{_sha256(path)}  {path.name}" for path in checksum_targets
    ]
    _atomic_write(
        output_dir / "SHA256SUMS", "\n".join(checksum_lines) + "\n"
    )
    return overall


def build_argument_parser() -> argparse.ArgumentParser:
    script_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description=(
            "Validate and extract Step 9 whole-routed-SoC resource/timing "
            "reports."
        )
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=script_root,
        help="ila_reference root (default: directory containing host/)",
    )
    parser.add_argument(
        "--baseline-dir",
        default="results/step9/baseline_raw",
        help="clean Common Base+Generator report directory",
    )
    parser.add_argument(
        "--ila-dir",
        default="generated",
        help="Step 5 Vivado ILA report directory",
    )
    parser.add_argument(
        "--cpu-dir",
        default="results/step9/inputs/cpu_polling",
        help="CPU Polling report directory",
    )
    parser.add_argument(
        "--custom-dir",
        default="results/step9/inputs/custom",
        help="Custom full-system report directory",
    )
    parser.add_argument(
        "--output-dir",
        default="results/step9",
        help="Step 9 generated output directory",
    )
    parser.add_argument(
        "--strict-complete",
        action="store_true",
        help="return 2 while Custom full-system input is pending",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_argument_parser().parse_args(argv)
    root = args.root.resolve()
    baseline_dir = _resolve_path(root, args.baseline_dir)
    ila_dir = _resolve_path(root, args.ila_dir)
    cpu_dir = _resolve_path(root, args.cpu_dir)
    custom_dir = _resolve_path(root, args.custom_dir)
    output_dir = _resolve_path(root, args.output_dir)

    specs = build_specs(
        root, baseline_dir, ila_dir, cpu_dir, custom_dir
    )
    results = {
        spec.key: load_and_validate_method(spec, root) for spec in specs
    }
    cross_assertions = _cross_validate(results)
    overall = write_outputs(
        root, output_dir, specs, results, cross_assertions
    )
    print(f"STEP9_RESOURCE_TIMING={overall}")
    print(f"RESULTS={output_dir}")
    if overall == "FAIL":
        return 1
    if overall.startswith("BLOCKED") or overall.startswith("PARTIAL"):
        return 2
    if args.strict_complete and not results["custom"].verified:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
