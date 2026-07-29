#!/usr/bin/env python3
"""Make an updatemem BIT header reproducible without touching its payload."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import struct
import tempfile


def parse_header(data: bytes) -> tuple[dict[str, tuple[int, int]], int]:
    if len(data) < 32:
        raise ValueError("BIT file is too small")

    magic_length = struct.unpack_from(">H", data, 0)[0]
    offset = 2 + magic_length
    if offset + 2 > len(data):
        raise ValueError("truncated BIT magic field")
    marker_length = struct.unpack_from(">H", data, offset)[0]
    offset += 2
    if marker_length != 1:
        raise ValueError(f"unexpected BIT marker length: {marker_length}")

    fields: dict[str, tuple[int, int]] = {}
    for expected_tag in "abcd":
        if offset >= len(data) or chr(data[offset]) != expected_tag:
            raise ValueError(f"missing BIT header tag {expected_tag!r}")
        offset += 1
        if offset + 2 > len(data):
            raise ValueError(f"truncated length for BIT tag {expected_tag!r}")
        field_length = struct.unpack_from(">H", data, offset)[0]
        offset += 2
        field_start = offset
        field_end = field_start + field_length
        if field_end > len(data):
            raise ValueError(f"truncated BIT tag {expected_tag!r}")
        fields[expected_tag] = (field_start, field_end)
        offset = field_end

    if offset >= len(data) or chr(data[offset]) != "e":
        raise ValueError("missing BIT payload tag 'e'")
    offset += 1
    if offset + 4 > len(data):
        raise ValueError("truncated BIT payload length")
    payload_length = struct.unpack_from(">I", data, offset)[0]
    payload_start = offset + 4
    if payload_start + payload_length != len(data):
        raise ValueError(
            "BIT payload length does not match the physical file size"
        )
    return fields, payload_start


def field_value(data: bytes, bounds: tuple[int, int]) -> bytes:
    start, end = bounds
    return data[start:end]


def normalize(reference_path: Path, target_path: Path) -> None:
    reference = reference_path.read_bytes()
    target = target_path.read_bytes()
    reference_fields, reference_payload_start = parse_header(reference)
    target_fields, target_payload_start = parse_header(target)

    for identity_tag in ("a", "b"):
        if field_value(reference, reference_fields[identity_tag]) != field_value(
            target, target_fields[identity_tag]
        ):
            raise ValueError(
                f"BIT identity field {identity_tag!r} differs from reference"
            )

    payload_digest_before = hashlib.sha256(
        target[target_payload_start:]
    ).hexdigest()
    normalized = bytearray(target)
    for timestamp_tag in ("c", "d"):
        reference_value = field_value(
            reference, reference_fields[timestamp_tag]
        )
        target_start, target_end = target_fields[timestamp_tag]
        if len(reference_value) != target_end - target_start:
            raise ValueError(
                f"BIT timestamp field {timestamp_tag!r} length differs"
            )
        normalized[target_start:target_end] = reference_value

    payload_digest_after = hashlib.sha256(
        normalized[target_payload_start:]
    ).hexdigest()
    if payload_digest_after != payload_digest_before:
        raise ValueError("normalization changed the configuration payload")
    if target_payload_start != reference_payload_start:
        raise ValueError("reference and target payload offsets differ")

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{target_path.name}.", dir=target_path.parent
    )
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(normalized)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, target_path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise

    print("BIT_HEADER_NORMALIZE: PASS")
    print(f"Reference: {reference_path}")
    print(f"Target   : {target_path}")
    print(f"Payload SHA-256: {payload_digest_after}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--target", required=True, type=Path)
    arguments = parser.parse_args()
    normalize(arguments.reference.resolve(), arguments.target.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
