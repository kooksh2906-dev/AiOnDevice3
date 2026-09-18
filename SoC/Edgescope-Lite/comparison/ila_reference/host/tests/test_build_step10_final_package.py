#!/usr/bin/env python3
"""Focused regression tests for the Step-10 package builder."""

from __future__ import annotations

import csv
import hashlib
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = (
    Path(__file__).resolve().parents[1]
    / "build_step10_final_package.py"
)
SPEC = importlib.util.spec_from_file_location("step10_builder", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
builder = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = builder
SPEC.loader.exec_module(builder)


class Step10ParserTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_duplicate_status_key_is_rejected(self) -> None:
        path = self.root / "status.rpt"
        path.write_text("OVERALL=PASS\nOVERALL=FAIL\n", encoding="utf-8")
        with self.assertRaises(builder.PackageError):
            builder.parse_key_values(path)

    def test_checksum_path_traversal_is_rejected(self) -> None:
        outside = self.root.parent / "outside-step10-test.txt"
        outside.write_text("test\n", encoding="utf-8")
        digest = hashlib.sha256(outside.read_bytes()).hexdigest()
        manifest = self.root / "SHA256SUMS"
        manifest.write_text(
            f"{digest}  ../{outside.name}\n", encoding="utf-8"
        )
        try:
            with self.assertRaises(builder.PackageError):
                builder.verify_checksum_manifest(manifest)
        finally:
            outside.unlink()

    def test_checksum_manifest_verifies_exact_file(self) -> None:
        target = self.root / "evidence.rpt"
        target.write_text("OVERALL=PASS\n", encoding="utf-8")
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        manifest = self.root / "SHA256SUMS"
        manifest.write_text(
            f"{digest}  {target.name}\n", encoding="utf-8"
        )
        result = builder.verify_checksum_manifest(manifest)
        self.assertEqual(result.verified_count, 1)


class Step10GateTests(unittest.TestCase):
    def test_current_pending_status_cannot_open_final_gate(self) -> None:
        pending = dict(builder.STEP9_FINAL_GATE)
        pending.update(
            {
                "OVERALL": "PASS_WITH_TEAM_INPUT_PENDING",
                "CUSTOM_FULL_SYSTEM": "NOT_RECEIVED",
                "THREE_WAY_COMPARISON": "PARTIAL_AWAITING_CUSTOM",
                "OFFICIAL_CUSTOM_VS_ILA_SAVINGS": "PENDING_CUSTOM",
                "NEXT_ACTION": "RECEIVE_CUSTOM_FULL_SYSTEM_REPORTS",
            }
        )
        errors = builder.final_gate_errors(pending)
        self.assertEqual(len(errors), 5)

    def test_exact_completed_status_opens_final_gate(self) -> None:
        self.assertEqual(
            builder.final_gate_errors(dict(builder.STEP9_FINAL_GATE)), []
        )

    def test_one_missing_gate_key_keeps_final_locked(self) -> None:
        incomplete = dict(builder.STEP9_FINAL_GATE)
        del incomplete["NEXT_ACTION"]
        self.assertIn("NEXT_ACTION=<missing>", builder.final_gate_errors(incomplete)[0])

    def test_presentation_duration_units_are_human_readable(self) -> None:
        self.assertEqual(builder.display_duration_ns("10"), "10 ns")
        self.assertEqual(builder.display_duration_ns("1000"), "1 µs")
        self.assertEqual(builder.display_duration_ns("1000000"), "1 ms")


class Step10CaptureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_capture(
        self, *, trigger_index: int = 512, sample_512: str = "01"
    ) -> Path:
        path = self.root / "capture.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(builder.NORMALIZED_HEADER)
            for index in range(1024):
                value = "00" if index < 512 else sample_512
                bits = tuple(f"{int(value, 16):08b}")
                writer.writerow(
                    (
                        index,
                        value,
                        int(index == trigger_index),
                        *bits,
                    )
                )
        return path

    def test_valid_normalized_capture(self) -> None:
        path = self.write_capture()
        self.assertEqual(
            builder.validate_normalized_capture(path, "00", "01"), 1024
        )

    def test_wrong_trigger_index_is_rejected(self) -> None:
        path = self.write_capture(trigger_index=513)
        with self.assertRaises(builder.PackageError):
            builder.validate_normalized_capture(path, "00", "01")

    def test_bit_column_corruption_is_rejected(self) -> None:
        path = self.write_capture()
        lines = path.read_text(encoding="utf-8").splitlines()
        fields = lines[12].split(",")
        fields[-1] = "1"
        lines[12] = ",".join(fields)
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        with self.assertRaises(builder.PackageError):
            builder.validate_normalized_capture(path, "00", "01")


class Step10PulseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_summary(self, corrupt: bool = False) -> Path:
        path = self.root / "pulse.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(
                (
                    "width_cycles",
                    "width_ns",
                    "eligible_trials",
                    "detected_count",
                    "detection_rate_percent",
                    "expected_detected_count",
                    "result",
                )
            )
            for width in (1, 10, 100, 1_000, 10_000, 100_000):
                detected = 9 if corrupt and width == 1 else 10
                writer.writerow(
                    (
                        width,
                        width * 10,
                        10,
                        detected,
                        100.0 if detected == 10 else 90.0,
                        10,
                        "PASS" if detected == 10 else "FAIL",
                    )
                )
        return path

    def test_exact_frozen_pulse_summary(self) -> None:
        self.assertEqual(len(builder.validate_pulse_summary(self.write_summary())), 6)

    def test_failed_trial_is_rejected(self) -> None:
        with self.assertRaises(builder.PackageError):
            builder.validate_pulse_summary(self.write_summary(corrupt=True))


if __name__ == "__main__":
    unittest.main(verbosity=2)
