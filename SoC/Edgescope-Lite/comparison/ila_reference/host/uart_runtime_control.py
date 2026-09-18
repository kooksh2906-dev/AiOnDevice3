#!/usr/bin/env python3
"""Host-side UART control for the Step 6 ILA reference capture."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import tempfile
import time

import serial
from serial.tools import list_ports


PROFILE_TO_TEST_ID = {
    "rising": 1,
    "falling": 2,
    "pattern": 3,
    "no_trigger": 5,
}


def available_serial_ports() -> list[str]:
    ports = []
    for port in list_ports.comports():
        if port.device.startswith(("/dev/ttyUSB", "/dev/ttyACM")):
            ports.append(port.device)
    return sorted(set(ports))


def resolve_port(explicit_port: str | None) -> str:
    if explicit_port:
        return explicit_port
    ports = available_serial_ports()
    if len(ports) != 1:
        raise RuntimeError(
            "exactly one /dev/ttyUSB* or /dev/ttyACM* port is required; "
            f"found {len(ports)}: {ports}"
        )
    return ports[0]


def parse_report(path: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise RuntimeError(f"malformed report line in {path}: {raw_line!r}")
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip()
    return fields


def atomic_report(path: Path, fields: dict[str, str | int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent, text=True
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write("# EdgeScope-Lite Step 6 UART acknowledgment\n")
            for key, value in fields.items():
                stream.write(f"{key}={value}\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def send_line(
    port: str,
    command: str,
    timeout_seconds: float,
    ack_callback=None,
) -> tuple[list[str], int]:
    deadline = time.monotonic() + timeout_seconds
    received: list[str] = []
    with serial.Serial(
        port=port,
        baudrate=9600,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=0.1,
        write_timeout=2.0,
        xonxoff=False,
        rtscts=False,
        dsrdtr=False,
    ) as uart:
        uart.reset_input_buffer()
        uart.write((command + "\r\n").encode("ascii"))
        uart.flush()
        sent_epoch_ms = time.time_ns() // 1_000_000
        if ack_callback is not None:
            ack_callback(sent_epoch_ms)

        while time.monotonic() < deadline:
            raw_line = uart.readline()
            if not raw_line:
                continue
            line = raw_line.decode("ascii", errors="replace").strip()
            if not line:
                continue
            received.append(line)
            print(line, flush=True)
            if line.startswith("OK "):
                return received, 0
            if line.startswith("ERR"):
                return received, 3
    return received, 4


def command_action(arguments: argparse.Namespace) -> int:
    port = resolve_port(arguments.port)
    command = " ".join(arguments.command)
    _, result = send_line(port, command, arguments.timeout)
    if result == 4:
        print(
            f"UART_ERROR: timeout waiting for OK/ERR on {port}: {command}",
            file=sys.stderr,
        )
    return result


def run_action(arguments: argparse.Namespace) -> int:
    arm_report = Path(arguments.arm_report).resolve()
    state = parse_report(arm_report)
    profile = arguments.profile
    expected_profile = state.get("PROFILE")
    if expected_profile != profile:
        raise RuntimeError(
            f"armed profile is {expected_profile!r}, requested {profile!r}"
        )
    if state.get("RESULT") != "ARMED_WAITING_FOR_TRIGGER":
        raise RuntimeError(
            "arm report does not prove ARMED_WAITING_FOR_TRIGGER"
        )
    session_token = state.get("SESSION_TOKEN")
    if not session_token:
        raise RuntimeError("arm report has no SESSION_TOKEN")

    test_id = PROFILE_TO_TEST_ID[profile]
    command = f"RUN {test_id}"
    port = resolve_port(arguments.port)
    ack_path = Path(arguments.ack_file).resolve()

    def write_no_trigger_ack(sent_epoch_ms: int) -> None:
        if profile != "no_trigger":
            return
        atomic_report(
            ack_path,
            {
                "SESSION_TOKEN": session_token,
                "PROFILE": profile,
                "STATE": "GENERATOR_STARTED",
                "START_EPOCH_MS": sent_epoch_ms,
                "UART_PORT": port,
                "UART_COMMAND": command,
            },
        )
        print(f"UART_ACK_FILE: {ack_path}", flush=True)

    print(
        f"UART_RUN: profile={profile} id={test_id} port={port} "
        f"session={session_token}",
        flush=True,
    )
    _, result = send_line(
        port,
        command,
        arguments.timeout,
        ack_callback=write_no_trigger_ack,
    )
    if result == 4:
        print(
            f"UART_ERROR: timeout waiting for firmware response on {port}",
            file=sys.stderr,
        )
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="EdgeScope-Lite Step 6 UART runtime controller"
    )
    subparsers = parser.add_subparsers(dest="action", required=True)

    list_parser = subparsers.add_parser("list", help="list candidate ports")
    list_parser.set_defaults(handler=lambda _arguments: list_action())

    command_parser = subparsers.add_parser(
        "command", help="send an arbitrary firmware command"
    )
    command_parser.add_argument("--port")
    command_parser.add_argument("--timeout", type=float, default=3.0)
    command_parser.add_argument("command", nargs="+")
    command_parser.set_defaults(handler=command_action)

    run_parser = subparsers.add_parser(
        "run", help="start the Generator for an armed ILA profile"
    )
    run_parser.add_argument(
        "profile", choices=tuple(PROFILE_TO_TEST_ID)
    )
    run_parser.add_argument("--port")
    run_parser.add_argument("--timeout", type=float, default=3.0)
    run_parser.add_argument(
        "--arm-report",
        default=(
            Path(__file__).resolve().parents[1]
            / "results"
            / "step6"
            / "armed_session.rpt"
        ),
    )
    run_parser.add_argument(
        "--ack-file",
        default=(
            Path(__file__).resolve().parents[1]
            / "results"
            / "step6"
            / "no_trigger_runtime_ack.rpt"
        ),
    )
    run_parser.set_defaults(handler=run_action)
    return parser


def list_action() -> int:
    ports = available_serial_ports()
    if not ports:
        print("UART_PORTS: none")
        return 1
    for port in ports:
        print(port)
    return 0


def main() -> int:
    parser = build_parser()
    arguments = parser.parse_args()
    if getattr(arguments, "timeout", 1.0) <= 0:
        parser.error("--timeout must be positive")
    try:
        return arguments.handler(arguments)
    except (OSError, RuntimeError, serial.SerialException) as error:
        print(f"UART_ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
