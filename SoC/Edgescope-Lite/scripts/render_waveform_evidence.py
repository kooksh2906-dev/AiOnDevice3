#!/usr/bin/env python3
"""Render three key regions from the real trigger-regression VCD as a PNG."""

from __future__ import annotations

import argparse
from bisect import bisect_right
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


BACKGROUND = "#10151d"
PANEL = "#171e29"
GRID = "#344052"
TEXT = "#e8edf5"
MUTED = "#9ca9ba"
DIGITAL = "#7ee787"
BUS = "#79c0ff"
EVENT = "#ff7b72"
STATE_FILL = "#21304a"


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    path = Path("/usr/share/fonts/truetype/dejavu") / name
    return ImageFont.truetype(str(path), size)


def parse_vcd(path: Path) -> tuple[dict[str, str], dict[str, list[tuple[int, str]]]]:
    scope: list[str] = []
    path_to_symbol: dict[str, str] = {}
    changes: dict[str, list[tuple[int, str]]] = {}
    now = 0
    in_definitions = True

    with path.open("r", encoding="utf-8", errors="replace") as stream:
        for raw in stream:
            line = raw.strip()
            if not line:
                continue

            if in_definitions:
                if line.startswith("$scope "):
                    parts = line.split()
                    scope.append(parts[2])
                elif line.startswith("$upscope"):
                    scope.pop()
                elif line.startswith("$var "):
                    parts = line.split()
                    symbol = parts[3]
                    reference = parts[4]
                    full_path = ".".join(scope + [reference])
                    path_to_symbol[full_path] = symbol
                    changes.setdefault(symbol, [])
                elif line.startswith("$enddefinitions"):
                    in_definitions = False
                continue

            if line.startswith("#"):
                now = int(line[1:])
            elif line[0] in "01xz":
                value = line[0]
                symbol = line[1:]
                changes.setdefault(symbol, []).append((now, value))
            elif line[0] in "bBrR":
                parts = line.split()
                if len(parts) == 2:
                    value = parts[0][1:].lower()
                    symbol = parts[1]
                    changes.setdefault(symbol, []).append((now, value))

    for series in changes.values():
        series.sort(key=lambda item: item[0])
    return path_to_symbol, changes


def value_at(series: list[tuple[int, str]], when: int) -> str:
    index = bisect_right(series, (when, chr(0x10FFFF))) - 1
    return "x" if index < 0 else series[index][1]


def event_time(series: list[tuple[int, str]], target: str = "1") -> int:
    for when, value in series:
        if value == target:
            return when
    raise ValueError(f"event value {target!r} was not found")


def display_bus(value: str, state: bool = False) -> str:
    if any(bit in value for bit in "xz"):
        return "X"
    number = int(value, 2) if value else 0
    if state:
        return {
            0: "IDLE",
            1: "PREFILL",
            2: "ARMED",
            3: "POST",
            4: "DONE",
        }.get(number, str(number))
    return str(number)


def render_digital(
    draw: ImageDraw.ImageDraw,
    series: list[tuple[int, str]],
    start: int,
    end: int,
    x0: int,
    x1: int,
    y: int,
) -> None:
    def xpos(when: int) -> int:
        return x0 + int((when - start) * (x1 - x0) / (end - start))

    top = y - 7
    bottom = y + 7

    points = [(start, value_at(series, start))]
    points.extend((t, v) for t, v in series if start < t <= end)

    for index, (when, value) in enumerate(points):
        next_time = points[index + 1][0] if index + 1 < len(points) else end
        current_y = top if value == "1" else bottom if value == "0" else y
        draw.line(
            (xpos(when), current_y, xpos(next_time), current_y),
            fill=DIGITAL,
            width=2,
        )
        if index + 1 < len(points):
            next_value = points[index + 1][1]
            next_y = top if next_value == "1" else bottom if next_value == "0" else y
            draw.line(
                (xpos(next_time), current_y, xpos(next_time), next_y),
                fill=DIGITAL,
                width=2,
            )


def render_bus(
    draw: ImageDraw.ImageDraw,
    series: list[tuple[int, str]],
    start: int,
    end: int,
    x0: int,
    x1: int,
    y: int,
    font: ImageFont.FreeTypeFont,
    state: bool = False,
) -> None:
    def xpos(when: int) -> int:
        return x0 + int((when - start) * (x1 - x0) / (end - start))

    points = [(start, value_at(series, start))]
    points.extend((t, v) for t, v in series if start < t <= end)

    for index, (when, value) in enumerate(points):
        next_time = points[index + 1][0] if index + 1 < len(points) else end
        left = xpos(when)
        right = xpos(next_time)
        draw.rectangle(
            (left, y - 8, right, y + 8),
            fill=STATE_FILL if state else PANEL,
            outline=BUS,
            width=1,
        )
        label = display_bus(value, state)
        text_box = draw.textbbox((0, 0), label, font=font)
        text_width = text_box[2] - text_box[0]
        if right - left > text_width + 8:
            draw.text(
                ((left + right - text_width) // 2, y - 7),
                label,
                fill=TEXT,
                font=font,
            )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "vcd",
        nargs="?",
        type=Path,
        default=Path("artifacts/waves/tb_circular_trace_buffer_trigger.vcd"),
    )
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=Path("docs/circular_trace_buffer_waveform.png"),
    )
    args = parser.parse_args()

    paths, changes = parse_vcd(args.vcd)
    root = "tb_circular_trace_buffer_trigger"
    requested = [
        ("sample_valid", f"{root}.sample_valid_i", "digital"),
        ("trigger_pulse", f"{root}.trigger_pulse_i", "digital"),
        ("FSM state", f"{root}.dut.state_q", "state"),
        ("bram_en", f"{root}.bram_en_o", "digital"),
        ("bram_word_addr", f"{root}.bram_addr_o", "bus"),
        ("pre_ready", f"{root}.pre_ready_o", "digital"),
        ("triggered", f"{root}.triggered_o", "digital"),
        ("capture_done", f"{root}.capture_done_o", "digital"),
        ("irq", f"{root}.irq_o", "digital"),
        ("start_addr", f"{root}.start_addr_o", "bus"),
        ("trigger_addr", f"{root}.trigger_addr_o", "bus"),
    ]

    signals: list[tuple[str, list[tuple[int, str]], str]] = []
    for label, full_path, kind in requested:
        if full_path not in paths:
            raise KeyError(f"VCD signal not found: {full_path}")
        signals.append((label, changes[paths[full_path]], kind))

    pre_time = event_time(changes[paths[f"{root}.pre_ready_o"]])
    trigger_time = event_time(changes[paths[f"{root}.triggered_o"]])
    done_time = event_time(changes[paths[f"{root}.capture_done_o"]])
    panels = [
        ("PREFILL → ARMED (512th valid sample)", pre_time),
        ("ARMED → POST (trigger sample = post #1)", trigger_time),
        ("POST → DONE (512 post samples complete)", done_time),
    ]

    width = 1800
    left = 205
    right = width - 45
    top_margin = 82
    panel_header = 42
    row_height = 26
    panel_gap = 28
    panel_height = panel_header + row_height * len(signals) + 20
    height = top_margin + len(panels) * panel_height + (len(panels) - 1) * panel_gap + 36

    image = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(image)
    title_font = load_font(28, bold=True)
    panel_font = load_font(19, bold=True)
    signal_font = load_font(15)
    small_font = load_font(13)

    draw.text(
        (32, 22),
        "Circular Trace Buffer — RTL Simulation Evidence",
        fill=TEXT,
        font=title_font,
    )
    draw.text(
        (width - 430, 30),
        "Source: Icarus Verilog VCD · 1 ps resolution",
        fill=MUTED,
        font=small_font,
    )

    half_window = 55_000  # 55 ns on either side of each transition.
    for panel_index, (panel_title, center) in enumerate(panels):
        panel_y = top_margin + panel_index * (panel_height + panel_gap)
        draw.rounded_rectangle(
            (22, panel_y, width - 22, panel_y + panel_height),
            radius=12,
            fill=PANEL,
            outline=GRID,
            width=1,
        )
        draw.text((42, panel_y + 11), panel_title, fill=TEXT, font=panel_font)
        draw.text(
            (width - 285, panel_y + 15),
            f"absolute time {center / 1_000_000:.3f} µs",
            fill=MUTED,
            font=small_font,
        )

        start = center - half_window
        end = center + half_window
        waveform_top = panel_y + panel_header
        waveform_bottom = waveform_top + row_height * len(signals)

        for offset_ns in range(-40, 41, 20):
            when = center + offset_ns * 1000
            x = left + int((when - start) * (right - left) / (end - start))
            draw.line((x, waveform_top, x, waveform_bottom), fill=GRID, width=1)
            label = f"{offset_ns:+d} ns"
            draw.text((x - 22, waveform_bottom + 2), label, fill=MUTED, font=small_font)

        event_x = left + int((center - start) * (right - left) / (end - start))
        draw.line(
            (event_x, waveform_top - 4, event_x, waveform_bottom),
            fill=EVENT,
            width=2,
        )

        for signal_index, (label, series, kind) in enumerate(signals):
            row_y = waveform_top + signal_index * row_height + row_height // 2
            draw.text((42, row_y - 8), label, fill=TEXT, font=signal_font)
            draw.line((left, row_y + 12, right, row_y + 12), fill="#242d3a", width=1)

            if kind == "digital":
                render_digital(draw, series, start, end, left, right, row_y)
            else:
                render_bus(
                    draw,
                    series,
                    start,
                    end,
                    left,
                    right,
                    row_y,
                    small_font,
                    state=(kind == "state"),
                )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output)
    print(f"Rendered {args.output}")


if __name__ == "__main__":
    main()
