#!/usr/bin/env python3
"""Regression tests for the Step-7 ILA CSV normalizer and validator."""

from __future__ import annotations

import csv
import hashlib
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REFERENCE_DIR = SCRIPT_DIR.parent


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


normalizer = load_module(
    "step7_normalizer",
    REFERENCE_DIR / "host" / "normalize_step7_ila_csv.py",
)
validator = load_module(
    "step7_validator",
    REFERENCE_DIR / "host" / "validate_step7_normalized.py",
)


EXPECTED_HASHES = {
    "rising": "b14c91f9f9c580c1c05a97a9a4a35aabe74b107d4e9334023ee92f51e3851a71",
    "falling": "60df25ce4f3b7bd16481829ee16aa1896e1b2fff4be90062026645f3c58a1786",
    "pattern": "1860ab5295dbb1ef4f6c2953d8cf06d825e0064744b4570909313b448fdc2d01",
}


class Step7NormalizationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.temp_dir = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_raw(
        self,
        profile: str,
        *,
        trigger_index: int = 512,
        corrupt_window: int | None = None,
        corrupt_value: int | None = None,
        value_text: str | None = None,
    ) -> Path:
        before, after = normalizer.PROFILES[profile]
        path = self.temp_dir / f"{profile}_raw.csv"
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
                value = before if index < 512 else after
                rendered_value = f"{value:02x}"
                if corrupt_value == index:
                    rendered_value = value_text or "XX"
                window = index + 1 if corrupt_window == index else index
                writer.writerow(
                    (index, window, int(index == trigger_index), rendered_value)
                )
        return path

    def test_golden_outputs(self) -> None:
        for profile, expected_hash in EXPECTED_HASHES.items():
            raw_path = self.write_raw(profile)
            samples = normalizer.parse_vivado_csv(raw_path, profile)
            output = normalizer.normalized_csv_text(samples)
            actual_hash = hashlib.sha256(output.encode("utf-8")).hexdigest()
            self.assertEqual(actual_hash, expected_hash)

    def test_single_trigger_must_be_at_512(self) -> None:
        raw_path = self.write_raw("rising", trigger_index=511)
        with self.assertRaises(SystemExit):
            normalizer.parse_vivado_csv(raw_path, "rising")

    def test_window_index_mismatch_is_rejected(self) -> None:
        raw_path = self.write_raw("falling", corrupt_window=700)
        with self.assertRaises(SystemExit):
            normalizer.parse_vivado_csv(raw_path, "falling")

    def test_unknown_probe_value_is_rejected(self) -> None:
        raw_path = self.write_raw(
            "pattern", corrupt_value=700, value_text="XX"
        )
        with self.assertRaises(SystemExit):
            normalizer.parse_vivado_csv(raw_path, "pattern")

    def test_normalized_channel_corruption_is_rejected(self) -> None:
        raw_path = self.write_raw("pattern")
        samples = normalizer.parse_vivado_csv(raw_path, "pattern")
        normalized_path = self.temp_dir / "pattern_normalized.csv"
        normalized_path.write_text(
            normalizer.normalized_csv_text(samples), encoding="utf-8"
        )
        validator.parse_normalized(normalized_path, "pattern")

        lines = normalized_path.read_text(encoding="utf-8").splitlines()
        fields = lines[513].split(",")
        fields[-1] = "0" if fields[-1] == "1" else "1"
        lines[513] = ",".join(fields)
        normalized_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        with self.assertRaises(SystemExit):
            validator.parse_normalized(normalized_path, "pattern")

    def test_step7_no_trigger_csv_is_absent(self) -> None:
        official_output = REFERENCE_DIR / "results" / "step7"
        self.assertFalse((official_output / "no_trigger_normalized.csv").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
