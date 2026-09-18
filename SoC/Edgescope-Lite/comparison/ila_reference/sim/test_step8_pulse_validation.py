#!/usr/bin/env python3
"""Regression tests for Step-8 Pulse Stress waveform validation."""

from __future__ import annotations

import csv
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
VALIDATOR_PATH = (
    SCRIPT_DIR.parent / "host" / "validate_step8_pulse_stress.py"
)


def load_validator():
    spec = importlib.util.spec_from_file_location(
        "step8_validator", VALIDATOR_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {VALIDATOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


validator = load_validator()


class PulseValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.temp_dir = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_raw(
        self,
        width: int,
        *,
        trigger_index: int = 512,
        corrupt_index: int | None = None,
        corrupt_value: int = 0,
    ) -> Path:
        path = self.temp_dir / f"pulse_w{width:06d}_trial_01_raw.csv"
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(
                (
                    "Sample in Buffer",
                    "Sample in Window",
                    "TRIGGER",
                    "fixture/probe_test_o[7:0]",
                )
            )
            writer.writerow(("Radix - UNSIGNED", "UNSIGNED", "UNSIGNED", "HEX"))
            for index in range(1024):
                value = int(512 <= index < 512 + width)
                if corrupt_index == index:
                    value = corrupt_value
                writer.writerow(
                    (index, index, int(index == trigger_index), f"{value:02X}")
                )
        return path

    def test_all_frozen_widths(self) -> None:
        for width in validator.WIDTHS:
            path = self.write_raw(width)
            samples = validator.parse_raw(path, width, 1)
            self.assertEqual(len(samples), 1024)
            self.assertEqual(samples[511].value, 0)
            self.assertEqual(samples[512].value, 1)

    def test_short_pulse_first_low_off_by_one_is_rejected(self) -> None:
        path = self.write_raw(10, corrupt_index=522, corrupt_value=1)
        with self.assertRaises(SystemExit):
            validator.parse_raw(path, 10, 1)

    def test_trigger_position_is_frozen(self) -> None:
        path = self.write_raw(1, trigger_index=513)
        with self.assertRaises(SystemExit):
            validator.parse_raw(path, 1, 1)

    def test_long_pulse_fall_is_outside_window(self) -> None:
        path = self.write_raw(100_000)
        samples = validator.parse_raw(path, 100_000, 1)
        self.assertEqual({sample.value for sample in samples[512:]}, {1})

    def test_uart_success_contract(self) -> None:
        reply = (
            "OK RUN id=6 pulse=0x000186A0 "
            "saw_busy=1 status=0x00000002"
        )
        match = validator.UART_REPLY.fullmatch(reply)
        self.assertIsNotNone(match)
        self.assertEqual(int(match.group(1), 16), 100_000)


if __name__ == "__main__":
    unittest.main(verbosity=2)
