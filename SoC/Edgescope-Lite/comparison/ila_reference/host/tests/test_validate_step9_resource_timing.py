#!/usr/bin/env python3
"""Focused unit tests for the Step 9 Vivado report extractor."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = (
    Path(__file__).resolve().parents[1]
    / "validate_step9_resource_timing.py"
)
SPEC = importlib.util.spec_from_file_location("step9_validator", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
validator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validator
SPEC.loader.exec_module(validator)


HEADER = """\
| Tool Version : Vivado v.2024.2 (lin64) Build 5239630
| Design       : base_soc_wrapper
| Device       : xc7a35tcpg236-1
| Speed File   : -1
| Design State : Routed
"""


class UtilizationParserTests(unittest.TestCase):
    def test_parses_required_resources_and_preserves_bram_types(self) -> None:
        text = (
            HEADER
            + """
| Slice LUTs      | 3726 | 0 | 0 | 20800 | 17.91 |
| LUT as Logic    | 3500 | 0 | 0 | 20800 | 16.83 |
| LUT as Memory   | 226  | 0 | 0 | 9600  | 2.35  |
| Slice Registers | 4230 | 0 | 0 | 41600 | 10.17 |
| RAMB36/FIFO*    | 32   | 0 | 0 | 50    | 64.00 |
| RAMB18          | 1    | 0 | 0 | 100   | 1.00  |
| DSPs            | 0    | 0 | 0 | 90    | 0.00  |
"""
        )
        metadata, metrics = validator.parse_utilization_text(text)
        self.assertEqual(metadata.vivado_version, "2024.2")
        self.assertEqual(metrics.slice_luts, 3726)
        self.assertEqual(metrics.lut_as_logic, 3500)
        self.assertEqual(metrics.lut_as_memory, 226)
        self.assertEqual(metrics.ramb36, 32)
        self.assertEqual(metrics.ramb18, 1)
        self.assertEqual(metrics.bram_tile_equiv, 32.5)

    def test_rejects_inconsistent_lut_decomposition(self) -> None:
        text = (
            HEADER
            + """
| Slice LUTs      | 9 | 0 | 0 | 20800 | 0 |
| LUT as Logic    | 7 | 0 | 0 | 20800 | 0 |
| LUT as Memory   | 1 | 0 | 0 | 9600  | 0 |
| Slice Registers | 1 | 0 | 0 | 41600 | 0 |
| RAMB36/FIFO*    | 0 | 0 | 0 | 50    | 0 |
| RAMB18          | 0 | 0 | 0 | 100   | 0 |
| DSPs            | 0 | 0 | 0 | 90    | 0 |
"""
        )
        with self.assertRaises(validator.ReportError):
            validator.parse_utilization_text(text)


class MetadataContractTests(unittest.TestCase):
    def test_unrouted_substring_is_not_a_routed_design_state(self) -> None:
        metadata = validator.ReportMetadata(
            tool_version="Vivado v.2024.2",
            vivado_version="2024.2",
            design="base_soc_wrapper",
            device="xc7a35tcpg236-1",
            speed_file="-1",
            design_state="Unrouted",
        )
        errors = validator._metadata_compatible(metadata)
        self.assertTrue(
            any("design_state=Unrouted" in error for error in errors)
        )


class TimingParserTests(unittest.TestCase):
    def _valid_text(self) -> str:
        return (
            HEADER.replace(
                "xc7a35tcpg236-1", "7a35t-cpg236"
            )
            + """
1. checking no_clock (0)
2. checking constant_clock (0)
3. checking pulse_width_clock (0)
4. checking unconstrained_internal_endpoints (0)
5. checking no_input_delay (2)
6. checking no_output_delay (1)
7. checking multiple_clock (0)
8. checking generated_clocks (0)
9. checking loops (0)
10. checking partial_input_delay (0)
11. checking partial_output_delay (0)
12. checking latch_loops (0)
| Design Timing Summary
    WNS(ns) TNS(ns) fail total WHS(ns) THS(ns) fail total WPWS(ns) TPWS(ns) fail total
    ------- ------- ---- ----- ------- ------- ---- ----- -------- -------- ---- -----
      1.544 0.000 0 11670 0.014 0.000 0 11654 3.000 0.000 0 4720

All user specified timing constraints are met.

Clock Waveform(ns) Period(ns) Frequency(MHz)
sys_clock {0.000 5.000} 10.000 100.000
"""
        )

    def test_parses_summary_clock_and_unconstrained_count(self) -> None:
        text = self._valid_text()
        _, metrics = validator.parse_timing_text(text)
        self.assertEqual(metrics.wns_ns, 1.544)
        self.assertEqual(metrics.whs_ns, 0.014)
        self.assertEqual(metrics.wpws_ns, 3.000)
        self.assertEqual(metrics.clock_period_ns, 10.000)
        self.assertEqual(metrics.clock_frequency_mhz, 100.000)
        self.assertEqual(metrics.internal_unconstrained_endpoints, 0)
        self.assertTrue(metrics.constraints_met)

    def test_rejects_nonzero_internal_check_timing_category(self) -> None:
        text = self._valid_text().replace(
            "1. checking no_clock (0)",
            "1. checking no_clock (1)",
            1,
        )
        with self.assertRaises(validator.ReportError):
            validator.parse_timing_text(text)

    def test_rejects_mismatched_verbose_check_timing_group(self) -> None:
        detail_group = "\n".join(
            (
                f"{index}. checking {name} "
                f"({7 if name == 'no_clock' else count})"
            )
            for index, (name, count) in enumerate(
                validator.REQUIRED_CHECK_TIMING_COUNTS,
                start=1,
            )
        )
        with self.assertRaises(validator.ReportError):
            validator.parse_timing_text(
                self._valid_text() + "\n" + detail_group + "\n"
            )

    def test_does_not_offer_or_compute_fmax(self) -> None:
        self.assertFalse(hasattr(validator.TimingMetrics, "fmax_mhz"))


class HierarchyAndSignTests(unittest.TestCase):
    def test_hierarchy_lookup_and_signed_delta(self) -> None:
        text = (
            HEADER
            + """
| Instance | Module | Total LUTs | Logic LUTs | LUTRAMs | SRLs | FFs | RAMB36 | RAMB18 | DSP Blocks |
| base_soc_wrapper | (top) | 100 | 90 | 5 | 5 | 200 | 2 | 1 | 0 |
| test_pattern_generator_0 | generator | 110 | 110 | 0 | 0 | 65 | 0 | 0 | 0 |
"""
        )
        _, rows = validator.parse_hierarchy_text(text)
        generator = validator._generator_row(rows)
        self.assertIsNotNone(generator)
        assert generator is not None
        self.assertEqual(generator.total_luts, 110)

        total = validator.ResourceMetrics(90, 80, 10, 50, 1, 0, 0)
        baseline = validator.ResourceMetrics(100, 85, 15, 60, 1, 1, 0)
        delta = total.subtract(baseline)
        self.assertEqual(delta.slice_luts, -10)
        self.assertEqual(delta.ramb18, -1)


def hierarchy_row(
    instance: str,
    *,
    module: str = "test_module",
    ramb36: int = 0,
    ramb18: int = 0,
) -> validator.HierarchyMetrics:
    return validator.HierarchyMetrics(
        instance=instance,
        module=module,
        total_luts=0,
        logic_luts=0,
        lutrams=0,
        srls=0,
        ffs=0,
        ramb36=ramb36,
        ramb18=ramb18,
        dsp_blocks=0,
    )


class CustomHierarchyEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        dummy = validator.MethodPaths(
            Path("u"), Path("h"), Path("t"), Path("d")
        )
        self.result = validator.MethodResult(
            "custom",
            "custom",
            "scope",
            dummy,
            validator.STATUS_VERIFIED,
            "ready",
        )
        common_rows = [
            hierarchy_row(
                instance,
                module=(
                    "microblaze_riscv_0_local_memory_imp_TEST"
                    if instance == "microblaze_riscv_0_local_memory"
                    else modules[0]
                ),
                ramb36=(
                    32
                    if instance == "microblaze_riscv_0_local_memory"
                    else 0
                ),
            )
            for instance, modules in (
                validator.CUSTOM_REQUIRED_COMMON_HIERARCHIES.items()
            )
        ]
        self.result.hierarchy_rows = common_rows + [
            hierarchy_row("probe_sampler_axi_0"),
            hierarchy_row("basic_trigger_engine_0"),
            hierarchy_row("circular_trace_buffer_0"),
            hierarchy_row("axi_bram_ctrl_0"),
            hierarchy_row(
                "circular_trace_buffer_0_bram", ramb36=1, ramb18=0
            ),
        ]

    def test_requires_all_five_separate_components_and_one_ramb36(self) -> None:
        validator._verify_custom_hierarchy(self.result)
        failures = [
            name
            for name, status, _ in self.result.assertions
            if status != "PASS"
        ]
        self.assertEqual(failures, [])
        self.assertEqual(self.result.status, validator.STATUS_VERIFIED)

    def test_rejects_missing_axi_bram_controller(self) -> None:
        self.result.hierarchy_rows = [
            row
            for row in self.result.hierarchy_rows
            if row.instance != "axi_bram_ctrl_0"
        ]
        validator._verify_custom_hierarchy(self.result)
        self.assertIn(
            "custom_component_exactly_one.axi_bram_controller",
            [
                name
                for name, status, _ in self.result.assertions
                if status == "FAIL"
            ],
        )

    def test_rejects_duplicate_aliases_for_one_custom_role(self) -> None:
        self.result.hierarchy_rows.append(
            hierarchy_row("probe_sampler_0")
        )
        validator._verify_custom_hierarchy(self.result)
        self.assertIn(
            "custom_component_exactly_one.probe_sampler",
            [
                name
                for name, status, _ in self.result.assertions
                if status == "FAIL"
            ],
        )

    def test_rejects_reduced_design_without_common_microblaze_soc(self) -> None:
        self.result.hierarchy_rows = [
            row
            for row in self.result.hierarchy_rows
            if row.instance != "microblaze_riscv_0"
        ]
        validator._verify_custom_hierarchy(self.result)
        self.assertIn(
            "custom_common_base_exactly_one.microblaze_riscv_0",
            [
                name
                for name, status, _ in self.result.assertions
                if status == "FAIL"
            ],
        )

    def test_rejects_common_instance_with_wrong_module(self) -> None:
        self.result.hierarchy_rows = [
            (
                hierarchy_row("axi_timer_0", module="lookalike_timer")
                if row.instance == "axi_timer_0"
                else row
            )
            for row in self.result.hierarchy_rows
        ]
        validator._verify_custom_hierarchy(self.result)
        self.assertIn(
            "custom_common_base_exactly_one.axi_timer_0",
            [
                name
                for name, status, _ in self.result.assertions
                if status == "FAIL"
            ],
        )

    def test_rejects_duplicate_common_instance_with_wrong_module(self) -> None:
        self.result.hierarchy_rows.append(
            hierarchy_row("axi_timer_0", module="lookalike_timer")
        )
        validator._verify_custom_hierarchy(self.result)
        self.assertIn(
            "custom_common_base_exactly_one.axi_timer_0",
            [
                name
                for name, status, _ in self.result.assertions
                if status == "FAIL"
            ],
        )

    def test_rejects_capture_bram_implemented_as_ramb18(self) -> None:
        self.result.hierarchy_rows[-1] = hierarchy_row(
            "circular_trace_buffer_0_bram", ramb36=0, ramb18=2
        )
        validator._verify_custom_hierarchy(self.result)
        self.assertIn(
            "custom_capture_bram_exact_primitive_count",
            [
                name
                for name, status, _ in self.result.assertions
                if status == "FAIL"
            ],
        )

    def test_detects_debug_cores_without_substring_false_positive(self) -> None:
        debug_rows = [
            hierarchy_row("ila_0"),
            hierarchy_row("wrapped", module="base_soc_ila_1_0"),
            hierarchy_row("wrapped_core", module="ila_v6_2_15_0_0"),
            hierarchy_row("system_ila_0"),
            hierarchy_row("vio_0"),
            hierarchy_row("dbg_hub"),
        ]
        self.assertEqual(
            validator._detect_forbidden_debug_cores(debug_rows),
            ["dbg_hub", "ila", "ila_v6", "system_ila", "vio"],
        )
        ordinary_rows = [
            hierarchy_row("previous_value_logic"),
            hierarchy_row("ilaordinary_datapath"),
            hierarchy_row("availability_counter"),
        ]
        self.assertEqual(
            validator._detect_forbidden_debug_cores(ordinary_rows), []
        )


class RouteAndDrcParserTests(unittest.TestCase):
    def _full_scope_drc_text(
        self,
        *,
        command: str = (
            "report_drc -ruledecks {default bitstream_checks} "
            "-no_waivers -file full.rpt"
        ),
        summary_ruledeck: str = "bitstream_checks, default",
    ) -> str:
        return (
            HEADER.replace("Routed", "Fully Routed")
            + f"""
| Command      : {command}
1. REPORT SUMMARY
-----------------
Design limits: <entire design considered>
Ruledeck: {summary_ruledeck}
Max checks: <unlimited>
Checks found: 0
| Rule | Severity | Description | Checks |
2. REPORT DETAILS
-----------------
"""
        )

    def test_route_requires_all_routable_nets_and_zero_errors(self) -> None:
        route = validator.parse_route_text(
            """
 # of routable nets..................... : 7147 :
 # of fully routed nets................. : 7147 :
 # of nets with routing errors.......... : 0 :
"""
        )
        self.assertTrue(route.fully_routed)

    def test_drc_sums_severity_counts(self) -> None:
        text = (
            HEADER.replace("Routed", "Fully Routed")
            + """
Table of Contents
-----------------
1. REPORT SUMMARY
2. REPORT DETAILS
Checks found: 999

1. REPORT SUMMARY
-----------------
Checks found: 4
| Rule | Severity         | Description | Checks |
| A-1  | Warning          | warning     | 3 |
| B-1  | Critical Warning | critical    | 1 |
2. REPORT DETAILS
-----------------
"""
        )
        _, drc = validator.parse_drc_text(text)
        self.assertEqual(drc.checks_found, 4)
        self.assertEqual(drc.warnings, 3)
        self.assertEqual(drc.critical_warnings, 1)
        self.assertEqual(drc.errors, 0)

    def test_drc_parses_full_scope_no_waiver_contract(self) -> None:
        text = self._full_scope_drc_text()
        _, drc = validator.parse_drc_text(text)
        self.assertTrue(drc.full_scope_contract)

    def test_drc_scope_rejects_filters_missing_deck_or_waiver_flag(
        self,
    ) -> None:
        filtered = self._full_scope_drc_text(
            command=(
                "report_drc -ruledecks {default bitstream_checks} "
                "-no_waivers -checks {UCIO-1} -file subset.rpt"
            )
        )
        _, filtered_drc = validator.parse_drc_text(filtered)
        self.assertFalse(filtered_drc.full_scope_contract)

        no_bitstream = self._full_scope_drc_text(
            command="report_drc -ruledecks {default} -no_waivers -file d.rpt",
            summary_ruledeck="default",
        )
        _, no_bitstream_drc = validator.parse_drc_text(no_bitstream)
        self.assertFalse(no_bitstream_drc.full_scope_contract)

        waivers_allowed = self._full_scope_drc_text(
            command=(
                "report_drc -ruledecks {default bitstream_checks} "
                "-file d.rpt"
            )
        )
        _, waivers_allowed_drc = validator.parse_drc_text(waivers_allowed)
        self.assertFalse(waivers_allowed_drc.full_scope_contract)

    def test_drc_rejects_unparsed_summary_rows(self) -> None:
        text = (
            HEADER.replace("Routed", "Fully Routed")
            + """
1. REPORT SUMMARY
-----------------
Checks found: 2
| Rule | Severity | Description | Checks |
| A-1  | Warning  | warning     | 1 |
2. REPORT DETAILS
-----------------
"""
        )
        with self.assertRaises(validator.ReportError):
            validator.parse_drc_text(text)

    def test_drc_rejects_unknown_severity(self) -> None:
        text = (
            HEADER.replace("Routed", "Fully Routed")
            + """
1. REPORT SUMMARY
-----------------
Checks found: 1
| Rule | Severity | Description | Checks |
| A-1  | Info     | info        | 1 |
2. REPORT DETAILS
-----------------
"""
        )
        with self.assertRaises(validator.ReportError):
            validator.parse_drc_text(text)


class BaselinePathStateTests(unittest.TestCase):
    def _spec(self, directory: Path) -> validator.MethodSpec:
        return validator.MethodSpec(
            "common_baseline",
            "baseline",
            "scope",
            validator.MethodPaths(
                directory / "u.rpt",
                directory / "h.rpt",
                directory / "t.rpt",
                directory / "d.rpt",
                route=directory / "r.rpt",
                check_timing=directory / "c.rpt",
                manifest=directory / "m.rpt",
                completion_log=directory / "build.log",
            ),
            require_route=True,
        )

    def test_clear_runner_fail_marker_is_invalid_not_in_progress(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "build.log").write_text(
                "STEP9_BASELINE_LAUNCH|result=FAIL|exit_code=1\n",
                encoding="utf-8",
            )
            status, detail = validator._path_state(self._spec(directory))
        self.assertEqual(status, validator.STATUS_INVALID)
        self.assertIn("BUILD_FAILED", detail)

    def test_log_without_final_marker_is_build_in_progress(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "build.log").write_text(
                "Vivado implementation is still running\n",
                encoding="utf-8",
            )
            status, _ = validator._path_state(self._spec(directory))
        self.assertEqual(status, validator.STATUS_BUILD_IN_PROGRESS)

    def test_pass_marker_still_requires_manifest_and_check_timing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            spec = self._spec(directory)
            for path in (
                spec.paths.utilization,
                spec.paths.hierarchy,
                spec.paths.timing,
                spec.paths.drc,
                spec.paths.route,
            ):
                assert path is not None
                path.write_text("complete\n", encoding="utf-8")
            assert spec.paths.completion_log is not None
            spec.paths.completion_log.write_text(
                "STEP9_BASELINE_LAUNCH|result=PASS|exit_code=0\n",
                encoding="utf-8",
            )
            status, detail = validator._path_state(spec)
        self.assertEqual(status, validator.STATUS_INCOMPLETE)
        self.assertIn("c.rpt", detail)
        self.assertIn("m.rpt", detail)


class GenericPathStateTests(unittest.TestCase):
    def _spec(self, directory: Path) -> validator.MethodSpec:
        return validator.MethodSpec(
            "custom",
            "custom",
            "scope",
            validator.MethodPaths(
                directory / "u.rpt",
                directory / "h.rpt",
                directory / "t.rpt",
                directory / "d.rpt",
                route=directory / "r.rpt",
                routed_dcp=directory / "routed_design.dcp",
                manifest=directory / "m.rpt",
            ),
            require_route=True,
        )

    def test_empty_input_is_not_received_but_partial_input_is_incomplete(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            spec = self._spec(directory)
            status, _ = validator._path_state(spec)
            self.assertEqual(status, validator.STATUS_NOT_RECEIVED)

            spec.paths.utilization.write_text(
                "partial\n", encoding="utf-8"
            )
            status, detail = validator._path_state(spec)
            self.assertEqual(status, validator.STATUS_INCOMPLETE)
            self.assertIn("partial input set", detail)


class SavingsPolicyTests(unittest.TestCase):
    def test_missing_custom_is_pending_not_zero(self) -> None:
        dummy = validator.MethodPaths(
            Path("u"), Path("h"), Path("t"), Path("d")
        )
        baseline = validator.MethodResult(
            "common_baseline",
            "base",
            "scope",
            dummy,
            validator.STATUS_VERIFIED,
            "ok",
            resources=validator.ResourceMetrics(10, 9, 1, 20, 1, 0, 0),
        )
        ila = validator.MethodResult(
            "ila_reference",
            "ila",
            "scope",
            dummy,
            validator.STATUS_VERIFIED,
            "ok",
            resources=validator.ResourceMetrics(20, 18, 2, 40, 1, 1, 0),
        )
        custom = validator.MethodResult(
            "custom",
            "custom",
            "scope",
            dummy,
            validator.STATUS_NOT_RECEIVED,
            "missing",
        )
        cpu = validator.MethodResult(
            "cpu_polling",
            "cpu",
            "scope",
            dummy,
            validator.STATUS_VERIFIED,
            "ok",
            resources=validator.ResourceMetrics(12, 11, 1, 22, 1, 0, 0),
        )
        rows = validator._official_savings_rows(
            {
                "common_baseline": baseline,
                "ila_reference": ila,
                "custom": custom,
                "cpu_polling": cpu,
            }
        )
        self.assertTrue(rows)
        self.assertTrue(
            all(
                row["status"] == "PENDING_CUSTOM_FULL_SYSTEM_REPORT"
                for row in rows
            )
        )
        self.assertTrue(all(row["custom_delta"] == "NA" for row in rows))

    def test_cross_failure_blocks_official_savings_values(self) -> None:
        dummy = validator.MethodPaths(
            Path("u"), Path("h"), Path("t"), Path("d")
        )

        def verified(key: str, value: int) -> validator.MethodResult:
            return validator.MethodResult(
                key,
                key,
                "scope",
                dummy,
                validator.STATUS_VERIFIED,
                "ok",
                resources=validator.ResourceMetrics(
                    value, value, 0, value, 0, 0, 0
                ),
            )

        rows = validator._official_savings_rows(
            {
                "common_baseline": verified("common_baseline", 10),
                "cpu_polling": verified("cpu_polling", 11),
                "ila_reference": verified("ila_reference", 20),
                "custom": verified("custom", 15),
            },
            (("same_common_sources", "FAIL", "mismatch"),),
        )
        self.assertTrue(
            all(
                row["status"] == "BLOCKED_CROSS_METHOD_VALIDATION"
                for row in rows
            )
        )
        self.assertTrue(all(row["ila_delta"] == "NA" for row in rows))
        self.assertTrue(all(row["custom_delta"] == "NA" for row in rows))

    def test_cpu_status_does_not_enter_official_savings_math(self) -> None:
        dummy = validator.MethodPaths(
            Path("u"), Path("h"), Path("t"), Path("d")
        )

        def method(
            key: str, status: str, value: int
        ) -> validator.MethodResult:
            return validator.MethodResult(
                key,
                key,
                "scope",
                dummy,
                status,
                "detail",
                resources=validator.ResourceMetrics(
                    value, value, 0, value, 0, 0, 0
                ),
            )

        rows = validator._official_savings_rows(
            {
                "common_baseline": method(
                    "common_baseline", validator.STATUS_VERIFIED, 10
                ),
                "cpu_polling": method(
                    "cpu_polling", validator.STATUS_INVALID, 999
                ),
                "ila_reference": method(
                    "ila_reference", validator.STATUS_VERIFIED, 20
                ),
                "custom": method(
                    "custom", validator.STATUS_VERIFIED, 15
                ),
            }
        )
        slice_luts = next(
            row for row in rows if row["metric"] == "slice_luts"
        )
        self.assertEqual(slice_luts["status"], validator.STATUS_VERIFIED)
        self.assertEqual(slice_luts["ila_delta"], 10)
        self.assertEqual(slice_luts["custom_delta"], 5)

    def test_missing_resource_row_preserves_method_status(self) -> None:
        dummy = validator.MethodPaths(
            Path("u"), Path("h"), Path("t"), Path("d")
        )
        missing = validator.MethodResult(
            "custom",
            "custom",
            "scope",
            dummy,
            validator.STATUS_NOT_RECEIVED,
            "missing",
        )
        row = validator._resource_row(
            missing,
            "TOTAL_WHOLE_ROUTED_SOC",
            None,
            "test",
        )
        self.assertEqual(row["status"], validator.STATUS_NOT_RECEIVED)

        verified = validator.MethodResult(
            "ila_reference",
            "ila",
            "scope",
            dummy,
            validator.STATUS_VERIFIED,
            "ok",
        )
        delta_row = validator._resource_row(
            verified,
            "DELTA_VS_COMMON_BASE_PLUS_GENERATOR",
            None,
            "test",
        )
        self.assertEqual(
            delta_row["status"], validator.STATUS_NOT_APPLICABLE
        )


class CompletionGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.dummy = validator.MethodPaths(
            Path("u"), Path("h"), Path("t"), Path("d")
        )

    def _results(
        self,
        custom_status: str = validator.STATUS_VERIFIED,
        cpu_status: str = validator.STATUS_VERIFIED,
    ) -> dict[str, validator.MethodResult]:
        statuses = {
            "common_baseline": validator.STATUS_VERIFIED,
            "cpu_polling": cpu_status,
            "ila_reference": validator.STATUS_VERIFIED,
            "custom": custom_status,
        }
        return {
            key: validator.MethodResult(
                key, key, "scope", self.dummy, status, "detail"
            )
            for key, status in statuses.items()
        }

    def test_complete_and_step10_require_all_four_verified(self) -> None:
        complete = validator._completion_status_fields(self._results())
        self.assertEqual(complete["THREE_WAY_COMPARISON"], "COMPLETE")
        self.assertEqual(
            complete["OFFICIAL_CUSTOM_VS_ILA_SAVINGS"], "VERIFIED"
        )
        self.assertEqual(complete["NEXT_ACTION"], "STEP10_FINAL_PACKAGE")

        invalid = validator._completion_status_fields(
            self._results(custom_status=validator.STATUS_INVALID)
        )
        self.assertEqual(
            invalid["THREE_WAY_COMPARISON"], "BLOCKED_CUSTOM_INVALID"
        )
        self.assertEqual(
            invalid["NEXT_ACTION"], "FIX_CUSTOM_FULL_SYSTEM_INPUT"
        )

        cpu_invalid = validator._completion_status_fields(
            self._results(cpu_status=validator.STATUS_INVALID)
        )
        self.assertNotEqual(
            cpu_invalid["THREE_WAY_COMPARISON"], "COMPLETE"
        )
        self.assertNotEqual(
            cpu_invalid["NEXT_ACTION"], "STEP10_FINAL_PACKAGE"
        )
        # CPU is deliberately excluded from the Custom-vs-ILA savings math.
        self.assertEqual(
            cpu_invalid["OFFICIAL_CUSTOM_VS_ILA_SAVINGS"], "VERIFIED"
        )

    def test_not_received_and_invalid_custom_are_distinct(self) -> None:
        missing = validator._completion_status_fields(
            self._results(custom_status=validator.STATUS_NOT_RECEIVED)
        )
        self.assertEqual(
            missing["THREE_WAY_COMPARISON"],
            "PARTIAL_AWAITING_CUSTOM",
        )
        self.assertEqual(
            missing["OFFICIAL_CUSTOM_VS_ILA_SAVINGS"],
            "PENDING_CUSTOM",
        )

        invalid = validator._completion_status_fields(
            self._results(custom_status=validator.STATUS_INVALID)
        )
        self.assertEqual(
            invalid["OFFICIAL_CUSTOM_VS_ILA_SAVINGS"],
            "BLOCKED_CUSTOM_INVALID",
        )

        mixed = validator._completion_status_fields(
            self._results(
                custom_status=validator.STATUS_NOT_RECEIVED,
                cpu_status=validator.STATUS_INVALID,
            )
        )
        self.assertIn(
            "CUSTOM_NOT_RECEIVED",
            mixed["THREE_WAY_COMPARISON"],
        )
        self.assertIn(
            "CPU_POLLING",
            mixed["THREE_WAY_COMPARISON"],
        )

    def test_cross_method_failure_blocks_all_completion_claims(self) -> None:
        fields = validator._completion_status_fields(
            self._results(),
            (("same_sources", "FAIL", "mismatch"),),
        )
        self.assertEqual(
            fields["THREE_WAY_COMPARISON"],
            "BLOCKED_CROSS_METHOD_VALIDATION",
        )
        self.assertEqual(
            fields["OFFICIAL_CUSTOM_VS_ILA_SAVINGS"],
            "BLOCKED_CROSS_METHOD_VALIDATION",
        )
        self.assertNotEqual(fields["NEXT_ACTION"], "STEP10_FINAL_PACKAGE")


class ManifestParserTests(unittest.TestCase):
    def test_duplicate_keys_are_rejected(self) -> None:
        with self.assertRaises(validator.ReportError):
            validator.parse_key_value_manifest("A=1\nA=2\n")
        with self.assertRaises(validator.ReportError):
            validator.parse_colon_manifest("A: 1\nA: 2\n")


class BaselineDrcManifestTests(unittest.TestCase):
    def _result(self) -> validator.MethodResult:
        dummy = validator.MethodPaths(
            Path("u"), Path("h"), Path("t"), Path("d")
        )
        return validator.MethodResult(
            "common_baseline",
            "baseline",
            "scope",
            dummy,
            validator.STATUS_VERIFIED,
            "detail",
            drc=validator.DrcMetrics(
                checks_found=3,
                errors=0,
                critical_warnings=0,
                warnings=3,
            ),
        )

    def test_all_build_time_drc_counts_are_required_and_bound(self) -> None:
        expected = {
            "DRC_ERROR_COUNT": "0",
            "DRC_CRITICAL_WARNING_COUNT": "0",
            "DRC_WARNING_COUNT": "3",
            "DRC_OTHER_COUNT": "0",
        }
        valid = self._result()
        validator._verify_baseline_drc_manifest_counts(valid, expected)
        self.assertTrue(valid.verified)
        self.assertTrue(
            all(status == "PASS" for _, status, _ in valid.assertions)
        )

        missing = self._result()
        validator._verify_baseline_drc_manifest_counts(missing, {})
        self.assertEqual(missing.status, validator.STATUS_INVALID)
        self.assertTrue(
            all(status == "FAIL" for _, status, _ in missing.assertions)
        )

        mismatched = self._result()
        validator._verify_baseline_drc_manifest_counts(
            mismatched,
            {**expected, "DRC_WARNING_COUNT": "2"},
        )
        self.assertEqual(mismatched.status, validator.STATUS_INVALID)
        warning_assertion = next(
            status
            for name, status, _ in mismatched.assertions
            if name == "baseline_manifest.DRC_WARNING_COUNT"
        )
        self.assertEqual(warning_assertion, "FAIL")


class CommonSourceHashTests(unittest.TestCase):
    def test_baseline_and_ila_compare_all_four_common_sources(self) -> None:
        baseline: dict[str, str] = {}
        ila: dict[str, str] = {}
        for index, (baseline_key, ila_key) in enumerate(
            validator.COMMON_SOURCE_MANIFEST_PAIRS, start=1
        ):
            digest = f"{index:064x}"
            baseline[baseline_key] = digest
            ila[ila_key] = digest
        self.assertEqual(
            validator._compare_common_source_hashes(baseline, ila), []
        )

        for baseline_key, _ in validator.COMMON_SOURCE_MANIFEST_PAIRS:
            changed = dict(baseline)
            changed[baseline_key] = "f" * 64
            self.assertTrue(
                validator._compare_common_source_hashes(changed, ila),
                msg=f"mismatch in {baseline_key} was not detected",
            )

    def test_manifest_hashes_are_bound_to_local_canonical_sources(self) -> None:
        root = MODULE_PATH.parents[1]
        manifest = {
            key: validator._sha256(path)
            for key, path in validator._common_source_paths(root).items()
        }
        result = validator.MethodResult(
            "common_baseline",
            "baseline",
            "scope",
            validator.MethodPaths(
                Path("u"), Path("h"), Path("t"), Path("d")
            ),
            validator.STATUS_VERIFIED,
            "ready",
        )
        validator._verify_canonical_common_source_hashes(
            result, manifest, root, "baseline_manifest"
        )
        self.assertEqual(result.status, validator.STATUS_VERIFIED)

        manifest["BASE_SOC_TCL_SHA256"] = "0" * 64
        tampered = validator.MethodResult(
            "common_baseline",
            "baseline",
            "scope",
            result.paths,
            validator.STATUS_VERIFIED,
            "ready",
        )
        validator._verify_canonical_common_source_hashes(
            tampered, manifest, root, "baseline_manifest"
        )
        self.assertEqual(tampered.status, validator.STATUS_INVALID)


class CustomManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = MODULE_PATH.parents[1]

    def _build_fixture(
        self, directory: Path
    ) -> tuple[validator.MethodResult, dict[str, str]]:
        paths = validator.MethodPaths(
            directory / "utilization.rpt",
            directory / "hierarchy.rpt",
            directory / "timing.rpt",
            directory / "drc.rpt",
            route=directory / "route.rpt",
            routed_dcp=directory / "routed_design.dcp",
            manifest=directory / "build_manifest.rpt",
        )
        for index, path in enumerate(paths.core_reports(), start=1):
            path.write_text(f"report {index}\n", encoding="utf-8")
        result = validator.MethodResult(
            "custom",
            "custom",
            "scope",
            paths,
            validator.STATUS_VERIFIED,
            "ready",
        )
        common = self.root / "frozen/common"
        manifest = {
            "OVERALL": "PASS",
            "VIVADO_VERSION": validator.REQUIRED_VIVADO,
            "FPGA_PART": validator.REQUIRED_PART,
            "BOARD_PART": validator.REQUIRED_BOARD_PART,
            "TOP": validator.REQUIRED_TOP,
            "DESIGN_STATE": "ROUTED",
            "CLOCK_HZ": "100000000",
            "CLOCK_PERIOD_NS": "10.000",
            "SYNTHESIS_STRATEGY": "Vivado Synthesis Defaults",
            "IMPLEMENTATION_STRATEGY": "Vivado Implementation Defaults",
            "VIVADO_ILA_COUNT": "0",
            "VIO_COUNT": "0",
            "DEBUG_CORE_COUNT": "0",
            "GENERATOR_HIERARCHY_COUNT": "1",
            "BUILD_SCOPE": "CUSTOM_WHOLE_ROUTED_SOC",
            "GIT_COMMIT": "1" * 40,
            "GIT_WORKTREE_DIRTY": "1",
            "BASE_SOC_TCL_SHA256": validator._sha256(
                common / "base_soc.tcl"
            ),
            "GENERATOR_INTEGRATION_TCL_SHA256": validator._sha256(
                common / "add_test_pattern_generator.tcl"
            ),
            "GENERATOR_RTL_SHA256": validator._sha256(
                common / "rtl/test_pattern_generator.sv"
            ),
            "GENERATOR_ADAPTER_SHA256": validator._sha256(
                common / "rtl/test_pattern_generator_gpio_adapter.v"
            ),
            "PROBE_SAMPLER_COUNT": "1",
            "TRIGGER_ENGINE_COUNT": "1",
            "CIRCULAR_TRACE_BUFFER_COUNT": "1",
            "AXI_BRAM_CONTROLLER_COUNT": "1",
            "CAPTURE_BRAM_COUNT": "1",
            "CAPTURE_BRAM_INCLUDED": "YES",
            "PROBE_SAMPLER_SOURCE_SHA256": "2" * 64,
            "TRIGGER_ENGINE_SOURCE_SHA256": "3" * 64,
            "CIRCULAR_TRACE_BUFFER_SOURCE_SHA256": "4" * 64,
            "CAPTURE_BRAM_SOURCE_SHA256": "5" * 64,
            "ROUTED_DCP_SHA256": validator._sha256(paths.routed_dcp),
            "UTILIZATION_REPORT_SHA256": validator._sha256(
                paths.utilization
            ),
            "HIERARCHICAL_REPORT_SHA256": validator._sha256(
                paths.hierarchy
            ),
            "TIMING_REPORT_SHA256": validator._sha256(paths.timing),
            "DRC_REPORT_SHA256": validator._sha256(paths.drc),
            "ROUTE_REPORT_SHA256": validator._sha256(paths.route),
        }
        return result, manifest

    def _write_manifest(
        self, result: validator.MethodResult, manifest: dict[str, str]
    ) -> None:
        assert result.paths.manifest is not None
        result.paths.manifest.write_text(
            "".join(f"{key}={value}\n" for key, value in manifest.items()),
            encoding="utf-8",
        )

    def test_complete_manifest_binds_common_sources_and_all_reports(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            result, manifest = self._build_fixture(Path(temporary))
            self._write_manifest(result, manifest)
            validator._verify_custom_build_manifest(result, self.root)
        failures = [
            name
            for name, status, _ in result.assertions
            if status != "PASS"
        ]
        self.assertEqual(failures, [])
        self.assertEqual(result.status, validator.STATUS_VERIFIED)

    def test_rejects_missing_source_hash_and_unbound_route_report(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            result, manifest = self._build_fixture(Path(temporary))
            del manifest["CAPTURE_BRAM_SOURCE_SHA256"]
            manifest["ROUTE_REPORT_SHA256"] = "0" * 64
            self._write_manifest(result, manifest)
            validator._verify_custom_build_manifest(result, self.root)
        failures = {
            name
            for name, status, _ in result.assertions
            if status == "FAIL"
        }
        self.assertIn(
            "custom_manifest.source_hash.capture_bram", failures
        )
        self.assertIn("custom_manifest.ROUTE_REPORT_SHA256", failures)


class CheckedInSnapshotTests(unittest.TestCase):
    """Smoke-test the two complete report sets that do not need Step 9 baseline."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.root = MODULE_PATH.parents[1]
        specs = validator.build_specs(
            cls.root,
            cls.root / "results/step9/baseline_raw",
            cls.root / "generated",
            cls.root / "results/step9/inputs/cpu_polling",
            cls.root / "results/step9/inputs/custom",
        )
        cls.specs = {spec.key: spec for spec in specs}

    def test_canonical_ila_step5_reports_are_verified(self) -> None:
        result = validator.load_and_validate_method(
            self.specs["ila_reference"], self.root
        )
        failures = [
            (name, detail)
            for name, status, detail in result.assertions
            if status != "PASS"
        ]
        self.assertEqual(failures, [])
        self.assertEqual(result.status, validator.STATUS_VERIFIED)

    def test_downloaded_cpu_polling_reports_are_verified(self) -> None:
        result = validator.load_and_validate_method(
            self.specs["cpu_polling"], self.root
        )
        failures = [
            (name, detail)
            for name, status, detail in result.assertions
            if status != "PASS"
        ]
        self.assertEqual(failures, [])
        self.assertEqual(result.status, validator.STATUS_VERIFIED)


if __name__ == "__main__":
    unittest.main()
