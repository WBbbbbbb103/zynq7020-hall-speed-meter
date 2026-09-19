#!/usr/bin/env python3
"""Receive or replay a CAR2 dual-AO capture and produce CSV/PNG files."""

from __future__ import annotations

import argparse
import csv
import math
import re
import sys
from pathlib import Path
from typing import BinaryIO


SAMPLE_RATE_HZ = 50_000.0
CAPTURE_DEPTH = 16_384
PRE_SAMPLES = 4_096
RECORD_RE = re.compile(
    rb"^([AB]),([0-9A-F]{4}),([0-9A-F]{3}),([0-9A-F]{3})\r?\n$"
)
STATUS_RE = re.compile(rb"^D,STS,([0-9A-F]),([0-9A-F])\r?\n$")
EDGE_RE = re.compile(rb"^D,(AON|AOF|BON|BOF),([0-9A-F]{16})\r?\n$")


def generate_demo_capture(
    output_path: Path,
    variable_acceleration: bool = False,
    reverse_motion: bool = False,
) -> None:
    """Generate a deterministic dual-Hall capture for PC-only testing."""

    output_path.parent.mkdir(parents=True, exist_ok=True)

    def sample_code(index: int, center: float, channel: str) -> int:
        distance = (index - center) / 720.0
        pulse = math.exp(-0.5 * distance * distance)
        ripple = 18.0 * math.sin(index * (0.013 if channel == "A" else 0.011))
        baseline = 1450.0 if channel == "A" else 1550.0
        amplitude = 1350.0 if channel == "A" else 1250.0
        return max(0, min(4095, round(baseline + amplitude * pulse + ripple)))

    def motion_position(time_s: float) -> float:
        displacement = (
            1.5 * time_s + 0.5 * 4.0 * time_s**2 + (20.0 / 6.0) * time_s**3
        )
        return 0.100 - displacement if reverse_motion else displacement

    def time_at_position(position_m: float) -> float:
        low = -0.100
        high = 0.200
        for _ in range(80):
            middle = 0.5 * (low + high)
            if reverse_motion:
                if motion_position(middle) > position_m:
                    low = middle
                else:
                    high = middle
            else:
                if motion_position(middle) < position_m:
                    low = middle
                else:
                    high = middle
        return 0.5 * (low + high)

    def spatial_sample_code(
        index: int,
        position_m: float,
        sensor_center_m: float,
        channel: str,
    ) -> int:
        sigma_m = 0.018
        distance = (position_m - sensor_center_m) / sigma_m
        pulse = math.exp(-0.5 * distance * distance)
        ripple = 18.0 * math.sin(index * (0.013 if channel == "A" else 0.011))
        baseline = 1450.0 if channel == "A" else 1550.0
        amplitude = 1350.0 if channel == "A" else 1250.0
        return max(0, min(4095, round(baseline + amplitude * pulse + ripple)))

    delay_samples = 1750  # 35 ms at 50 ksample/s
    with output_path.open("w", encoding="ascii", newline="") as output_file:
        output_file.write("#CAR2AO\n")
        output_file.write("D,STS,0,F\n")
        if variable_acceleration:
            if reverse_motion:
                edge_positions_m = {
                    "AON": 0.010,
                    "AOF": -0.010,
                    "BON": 0.110,
                    "BOF": 0.090,
                }
            else:
                edge_positions_m = {
                    "AON": -0.010,
                    "AOF": 0.010,
                    "BON": 0.090,
                    "BOF": 0.110,
                }
            edge_times_s = {
                label: time_at_position(position)
                for label, position in edge_positions_m.items()
            }
            first_edge_time_s = min(edge_times_s.values())
            demo_edges = {
                label: 1_000_000
                + round((edge_time - first_edge_time_s) * 50_000_000.0)
                for label, edge_time in edge_times_s.items()
            }
            event_trigger_times_s = {
                "A": edge_times_s["AON"],
                "B": edge_times_s["BON"],
            }
        else:
            demo_edges = {
                "AON": 1_000_000,
                "AOF": 1_350_000,
                "BON": 2_750_000,
                "BOF": 3_100_000,
            }
            event_trigger_times_s = {"A": 0.0, "B": 0.035}
        for label, timestamp in demo_edges.items():
            output_file.write(f"D,{label},{timestamp:016X}\n")
        for event in ("A", "B"):
            if not variable_acceleration:
                if event == "A":
                    center_a = PRE_SAMPLES
                    center_b = PRE_SAMPLES + delay_samples
                else:
                    center_a = PRE_SAMPLES - delay_samples
                    center_b = PRE_SAMPLES

            for index in range(CAPTURE_DEPTH):
                if variable_acceleration:
                    local_time_s = (index - PRE_SAMPLES) / SAMPLE_RATE_HZ
                    global_time_s = local_time_s + event_trigger_times_s[event]
                    position_m = motion_position(global_time_s)
                    adc_a = spatial_sample_code(index, position_m, 0.0, "A")
                    adc_b = spatial_sample_code(index, position_m, 0.100, "B")
                else:
                    adc_a = sample_code(index, center_a, "A")
                    adc_b = sample_code(index, center_b, "B")
                output_file.write(
                    f"{event},{index:04X},{adc_a:03X},{adc_b:03X}\n"
                )
        output_file.write("#END\n")


def read_capture(
    stream: BinaryIO,
) -> tuple[
    dict[str, list[tuple[int, int, int]]],
    dict[str, object],
]:
    captures: dict[str, list[tuple[int, int, int]]] = {"A": [], "B": []}
    digital: dict[str, object] = {
        "status": None,
        "seen": None,
        "timestamps": {},
    }

    while True:
        line = stream.readline()
        if not line:
            raise RuntimeError("Data ended before the #CAR2AO header was found")
        if line.rstrip(b"\r\n") == b"#CAR2AO":
            break

    while True:
        line = stream.readline()
        if not line:
            raise RuntimeError("Data ended before the #END marker")
        if line.rstrip(b"\r\n") == b"#END":
            break

        status_match = STATUS_RE.match(line)
        if status_match is not None:
            digital["status"] = int(status_match.group(1), 16)
            digital["seen"] = int(status_match.group(2), 16)
            continue

        edge_match = EDGE_RE.match(line)
        if edge_match is not None:
            label = edge_match.group(1).decode("ascii")
            timestamps = digital["timestamps"]
            assert isinstance(timestamps, dict)
            timestamps[label] = int(edge_match.group(2), 16)
            continue

        match = RECORD_RE.match(line)
        if match is None:
            continue

        event = match.group(1).decode("ascii")
        index = int(match.group(2), 16)
        adc_a = int(match.group(3), 16)
        adc_b = int(match.group(4), 16)
        captures[event].append((index, adc_a, adc_b))

    for event, records in captures.items():
        records.sort(key=lambda row: row[0])
        if len(records) != CAPTURE_DEPTH:
            raise RuntimeError(
                f"Event {event} contains {len(records)} samples; "
                f"expected {CAPTURE_DEPTH}"
            )
        if any(index != expected for expected, (index, _, _) in enumerate(records)):
            raise RuntimeError(f"Event {event} has missing or repeated sample indices")

    return captures, digital


def save_edge_csv(
    digital: dict[str, object],
    output_path: Path,
    clock_hz: float,
) -> None:
    timestamps = digital["timestamps"]
    assert isinstance(timestamps, dict)
    if not timestamps:
        return

    first_tick = min(timestamps.values())
    with output_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.writer(output_file)
        writer.writerow(
            ["edge", "timestamp_ticks", "timestamp_s", "relative_to_first_s"]
        )
        for label in ("AON", "AOF", "BON", "BOF"):
            if label not in timestamps:
                continue
            tick = timestamps[label]
            writer.writerow(
                [
                    label,
                    tick,
                    f"{tick / clock_hz:.9f}",
                    f"{(tick - first_tick) / clock_hz:.9f}",
                ]
            )


def report_digital_edges(
    digital: dict[str, object],
    clock_hz: float,
    spacing_mm: float | None,
) -> bool:
    timestamps = digital["timestamps"]
    assert isinstance(timestamps, dict)
    if digital["status"] is None and not timestamps:
        print("Digital four-edge records: not present in this capture")
        return False

    status = int(digital["status"] or 0)
    seen = int(digital["seen"] or 0)
    error = status & 0x1
    error_code = (status >> 1) & 0x3
    print(
        "Digital four-edge status: "
        f"error={error}, error_code={error_code}, seen=0x{seen:X}"
    )

    for label in ("AON", "AOF", "BON", "BOF"):
        if label in timestamps:
            print(
                f"  {label}: {timestamps[label]} ticks "
                f"({timestamps[label] / clock_hz:.9f} s)"
            )

    required = {"AON", "AOF", "BON", "BOF"}
    if error or seen != 0xF or not required.issubset(timestamps):
        print("Digital four-edge record is incomplete; trajectory fitting is disabled")
        return True

    on_delay_s = (timestamps["BON"] - timestamps["AON"]) / clock_hz
    off_delay_s = (timestamps["BOF"] - timestamps["AOF"]) / clock_hz
    direction = "Hall A -> Hall B" if on_delay_s > 0.0 else "Hall B -> Hall A"
    print(f"Digital direction: {direction}")
    print(f"Digital corresponding-edge delays: ON={on_delay_s * 1000.0:.6f} ms, "
          f"OFF={off_delay_s * 1000.0:.6f} ms")

    if spacing_mm is not None and on_delay_s != 0.0 and off_delay_s != 0.0:
        spacing_m = spacing_mm / 1000.0
        print(
            "Digital corresponding-edge average speeds: "
            f"ON={spacing_m / abs(on_delay_s):.6f} m/s, "
            f"OFF={spacing_m / abs(off_delay_s):.6f} m/s"
        )
    return True


def save_csv(
    captures: dict[str, list[tuple[int, int, int]]], output_path: Path
) -> None:
    with output_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.writer(output_file)
        writer.writerow(
            [
                "event",
                "index",
                "time_s",
                "adc_a_code",
                "adc_b_code",
                "xadc_a_v",
                "xadc_b_v",
            ]
        )
        for event in ("A", "B"):
            for index, adc_a, adc_b in captures[event]:
                time_s = (index - PRE_SAMPLES) / SAMPLE_RATE_HZ
                writer.writerow(
                    [
                        event,
                        index,
                        f"{time_s:.8f}",
                        adc_a,
                        adc_b,
                        f"{adc_a / 4095.0:.8f}",
                        f"{adc_b / 4095.0:.8f}",
                    ]
                )


def save_plot(
    captures: dict[str, list[tuple[int, int, int]]],
    output_path: Path,
    divider_ratio: float,
) -> None:
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as exc:
        raise RuntimeError(
            "matplotlib is required for plotting. Install it with: "
            "python -m pip install matplotlib"
        ) from exc

    figure, axes = plt.subplots(2, 1, figsize=(12, 8), sharex=True)
    for axis, event in zip(axes, ("A", "B")):
        records = captures[event]
        times_ms = [
            1000.0 * (index - PRE_SAMPLES) / SAMPLE_RATE_HZ
            for index, _, _ in records
        ]
        ao_a_volts = [adc_a / 4095.0 * divider_ratio for _, adc_a, _ in records]
        ao_b_volts = [adc_b / 4095.0 * divider_ratio for _, _, adc_b in records]

        axis.plot(times_ms, ao_a_volts, label="Hall A AO", linewidth=1.0)
        axis.plot(times_ms, ao_b_volts, label="Hall B AO", linewidth=1.0)
        axis.axvline(0.0, color="black", linestyle="--", linewidth=0.8,
                     label=f"Hall {event} digital trigger")
        axis.set_title(f"Capture triggered by Hall {event}")
        axis.set_ylabel("Estimated Hall AO voltage (V)")
        axis.grid(True, alpha=0.3)
        axis.legend(loc="best")

    axes[-1].set_xlabel("Time relative to digital trigger (ms)")
    figure.tight_layout()
    figure.savefig(output_path, dpi=160)


def estimate_delay_samples(
    records: list[tuple[int, int, int]],
) -> float:
    """Estimate Hall-B delay relative to Hall-A with FFT correlation."""
    try:
        import numpy as np
    except ImportError as exc:
        raise RuntimeError(
            "numpy is required for delay fitting. Install it with: "
            "python -m pip install numpy"
        ) from exc

    signal_a = np.asarray([row[1] for row in records], dtype=float)
    signal_b = np.asarray([row[2] for row in records], dtype=float)
    signal_a -= np.median(signal_a)
    signal_b -= np.median(signal_b)

    correlation_length = signal_a.size + signal_b.size - 1
    fft_length = 1 << (correlation_length - 1).bit_length()
    correlation = np.fft.irfft(
        np.fft.rfft(signal_b, fft_length)
        * np.fft.rfft(signal_a[::-1], fft_length),
        fft_length,
    )[:correlation_length]

    peak_index = int(np.argmax(correlation))
    fractional_offset = 0.0
    if 0 < peak_index < correlation_length - 1:
        left = correlation[peak_index - 1]
        center = correlation[peak_index]
        right = correlation[peak_index + 1]
        denominator = left - 2.0 * center + right
        if denominator != 0.0:
            fractional_offset = 0.5 * (left - right) / denominator

    zero_lag_index = signal_a.size - 1
    return peak_index + fractional_offset - zero_lag_index


def report_delay_and_speed(
    captures: dict[str, list[tuple[int, int, int]]],
    spacing_mm: float | None,
) -> None:
    delays = {
        event: estimate_delay_samples(captures[event]) for event in ("A", "B")
    }
    mean_delay = sum(delays.values()) / len(delays)
    delay_seconds = mean_delay / SAMPLE_RATE_HZ

    print(
        "Fitted B-minus-A delay: "
        f"{mean_delay:.3f} samples = {delay_seconds * 1000.0:.5f} ms "
        f"(A-window {delays['A']:.3f}, B-window {delays['B']:.3f})"
    )
    if mean_delay > 0.0:
        print("Direction: Hall A -> Hall B")
    elif mean_delay < 0.0:
        print("Direction: Hall B -> Hall A")
    else:
        print("Direction: indeterminate")

    if spacing_mm is not None:
        if spacing_mm <= 0.0:
            raise RuntimeError("--spacing-mm must be greater than zero")
        if delay_seconds == 0.0:
            raise RuntimeError("Cannot calculate speed from zero fitted delay")
        speed_m_s = (spacing_mm / 1000.0) / abs(delay_seconds)
        print(
            f"Average speed for {spacing_mm:.3f} mm spacing: "
            f"{speed_m_s:.6f} m/s"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Receive or replay CAR2 dual-Hall AO waveform data"
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--port", help="Serial port, for example COM5")
    source.add_argument("--input", type=Path, help="Previously saved raw UART file")
    source.add_argument(
        "--demo",
        action="store_true",
        help="Generate and plot simulated dual-Hall AO data without hardware",
    )
    source.add_argument(
        "--demo-variable",
        action="store_true",
        help="Generate a consistent variable-acceleration digital/AO packet",
    )
    source.add_argument(
        "--demo-reverse-variable",
        action="store_true",
        help="Generate a consistent B-to-A variable-acceleration packet",
    )
    parser.add_argument("--baud", type=int, default=115_200)
    parser.add_argument("--output", type=Path, default=Path("car2_ao_capture"))
    parser.add_argument(
        "--divider-ratio",
        type=float,
        default=6.0,
        help="AO voltage divided by XADC voltage; 10k/2k divider gives 6",
    )
    parser.add_argument(
        "--spacing-mm",
        type=float,
        help="Effective Hall A/B spacing used for average-speed calculation",
    )
    parser.add_argument(
        "--clock-hz",
        type=float,
        default=50_000_000.0,
        help="FPGA timestamp clock frequency",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    raw_path = args.output.with_suffix(".txt")

    if args.demo or args.demo_variable or args.demo_reverse_variable:
        generate_demo_capture(
            raw_path,
            variable_acceleration=(args.demo_variable or args.demo_reverse_variable),
            reverse_motion=args.demo_reverse_variable,
        )
        input_path = raw_path
    elif args.port:
        try:
            import serial
        except ImportError as exc:
            raise RuntimeError(
                "pyserial is required for live capture. Install it with: "
                "python -m pip install pyserial"
            ) from exc

        print(f"Waiting for #CAR2AO on {args.port} at {args.baud} baud...")
        with serial.Serial(args.port, args.baud, timeout=30) as serial_port:
            with raw_path.open("wb") as raw_file:
                while True:
                    line = serial_port.readline()
                    if not line:
                        raise RuntimeError("Timed out while waiting for FPGA data")
                    if line.rstrip(b"\r\n") == b"#CAR2AO":
                        raw_file.write(line)
                        break
                while True:
                    line = serial_port.readline()
                    if not line:
                        raise RuntimeError("Timed out during FPGA data transfer")
                    raw_file.write(line)
                    if line.rstrip(b"\r\n") == b"#END":
                        break
        input_path = raw_path
    else:
        input_path = args.input

    with input_path.open("rb") as input_file:
        captures, digital = read_capture(input_file)

    has_digital = report_digital_edges(digital, args.clock_hz, args.spacing_mm)
    report_delay_and_speed(captures, args.spacing_mm)

    csv_path = args.output.with_suffix(".csv")
    edge_csv_path = args.output.with_name(args.output.name + "_edges").with_suffix(".csv")
    png_path = args.output.with_suffix(".png")
    save_csv(captures, csv_path)
    if has_digital:
        save_edge_csv(digital, edge_csv_path, args.clock_hz)
    save_plot(captures, png_path, args.divider_ratio)

    print(f"Saved CSV: {csv_path.resolve()}")
    if has_digital:
        print(f"Saved digital edges: {edge_csv_path.resolve()}")
    print(f"Saved plot: {png_path.resolve()}")
    if args.port or args.demo or args.demo_variable or args.demo_reverse_variable:
        print(f"Saved raw UART data: {raw_path.resolve()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
