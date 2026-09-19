#!/usr/bin/env python3
"""Compare digital four-edge and dual-AO trajectory fits from one UART packet."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path


EDGE_LABELS = ("AON", "AOF", "BON", "BOF")
EDGE_RE = re.compile(rb"^D,(AON|AOF|BON|BOF),([0-9A-F]{16})\r?\n$")
STATUS_RE = re.compile(rb"^D,STS,([0-9A-F]),([0-9A-F])\r?\n$")
SAMPLE_RE = re.compile(
    rb"^([AB]),([0-9A-F]{4}),([0-9A-F]{3}),([0-9A-F]{3})\r?\n$"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fit and compare four-edge and dual-AO instantaneous speed"
    )
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--edge-calibration", type=Path, required=True)
    parser.add_argument("--ao-calibration", type=Path, required=True)
    parser.add_argument(
        "--output", type=Path, default=Path("capture/combined_trajectory")
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, object]:
    with path.open("r", encoding="utf-8") as input_file:
        return json.load(input_file)


def read_packet(path: Path):
    timestamps: dict[str, int] = {}
    captures: dict[str, list[tuple[int, int, int]]] = {"A": [], "B": []}
    status = -1
    seen = -1
    with path.open("rb") as input_file:
        for line in input_file:
            status_match = STATUS_RE.match(line)
            if status_match is not None:
                status = int(status_match.group(1), 16)
                seen = int(status_match.group(2), 16)
                continue
            edge_match = EDGE_RE.match(line)
            if edge_match is not None:
                timestamps[edge_match.group(1).decode("ascii")] = int(
                    edge_match.group(2), 16
                )
                continue
            sample_match = SAMPLE_RE.match(line)
            if sample_match is not None:
                event = sample_match.group(1).decode("ascii")
                captures[event].append(
                    (
                        int(sample_match.group(2), 16),
                        int(sample_match.group(3), 16),
                        int(sample_match.group(4), 16),
                    )
                )

    if (status & 0x1) or ((status >> 1) & 0x3) or seen != 0xF:
        raise RuntimeError(
            f"Invalid digital capture status: status=0x{status:X}, seen=0x{seen:X}"
        )
    for label in EDGE_LABELS:
        if label not in timestamps:
            raise RuntimeError(f"Missing timestamp {label}")
    for event in ("A", "B"):
        captures[event].sort(key=lambda row: row[0])
        if not captures[event]:
            raise RuntimeError(f"Missing AO capture {event}")
    return timestamps, captures


def main() -> int:
    args = parse_args()
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import numpy as np
    except ImportError as exc:
        raise RuntimeError("numpy and matplotlib are required") from exc

    timestamps, captures = read_packet(args.input)
    edge_calibration = load_json(args.edge_calibration)
    ao_calibration = load_json(args.ao_calibration)

    clock_hz = float(edge_calibration["clock_hz"])
    sample_rate_hz = float(ao_calibration["sample_rate_hz"])
    pre_samples = int(ao_calibration["pre_samples"])
    if clock_hz <= 0.0 or sample_rate_hz <= 0.0:
        raise RuntimeError("Clock and sample rates must be positive")

    direction = "forward" if timestamps["AON"] < timestamps["BON"] else "reverse"
    direction_name = "Hall A -> Hall B" if direction == "forward" else "Hall B -> Hall A"
    selected_event = "A" if direction == "forward" else "B"
    trigger_label = "AON" if selected_event == "A" else "BON"

    first_tick = min(timestamps.values())
    last_tick = max(timestamps.values())
    tc_tick = 0.5 * (first_tick + last_tick)

    edge_config = edge_calibration[direction]
    assert isinstance(edge_config, dict)
    edge_times_s = np.asarray(
        [(timestamps[label] - tc_tick) / clock_hz for label in EDGE_LABELS]
    )
    edge_positions_m = np.asarray(
        [float(edge_config[f"{label}_mm"]) / 1000.0 for label in EDGE_LABELS]
    )
    digital_position_fit = np.polynomial.Polynomial.fit(
        edge_times_s, edge_positions_m, deg=3
    ).convert()
    digital_speed_fit = digital_position_fit.deriv()

    records = captures[selected_event]
    indices = np.asarray([record[0] for record in records], dtype=float)
    trigger_time_s = (timestamps[trigger_label] - tc_tick) / clock_hz
    sample_times_s = trigger_time_s + (indices - pre_samples) / sample_rate_hz
    adc_codes = {
        "A": np.asarray([record[1] for record in records], dtype=float),
        "B": np.asarray([record[2] for record in records], dtype=float),
    }

    channel_config = ao_calibration["channels"]
    assert isinstance(channel_config, dict)
    ao_observation_times = []
    ao_observation_positions = []
    selected_masks: dict[str, object] = {}

    for channel in ("A", "B"):
        config = channel_config[channel]
        baseline = float(config["baseline_code"])
        amplitude = float(config["amplitude_code"])
        center_m = float(config["center_mm"]) / 1000.0
        sigma_m = float(config["sigma_mm"]) / 1000.0
        normalized = np.clip((adc_codes[channel] - baseline) / amplitude, 1.0e-6, 1.0)
        useful = (normalized > 0.12) & (normalized < 0.94)
        selected_masks[channel] = useful
        peak_time_s = sample_times_s[int(np.argmax(adc_codes[channel]))]
        useful_times = sample_times_s[useful]
        distance_m = sigma_m * np.sqrt(-2.0 * np.log(normalized[useful]))
        if direction == "forward":
            signs = np.where(useful_times < peak_time_s, -1.0, 1.0)
        else:
            signs = np.where(useful_times < peak_time_s, 1.0, -1.0)
        ao_observation_times.append(useful_times)
        ao_observation_positions.append(center_m + signs * distance_m)

    ao_times_s = np.concatenate(ao_observation_times)
    ao_positions_m = np.concatenate(ao_observation_positions)
    ao_position_fit = np.polynomial.Polynomial.fit(
        ao_times_s, ao_positions_m, deg=3
    ).convert()
    ao_speed_fit = ao_position_fit.deriv()

    evaluation_time_s = np.linspace(
        (first_tick - tc_tick) / clock_hz,
        (last_tick - tc_tick) / clock_hz,
        1001,
    )
    digital_position_m = digital_position_fit(evaluation_time_s)
    ao_position_m = ao_position_fit(evaluation_time_s)
    digital_speed_m_s = digital_speed_fit(evaluation_time_s)
    ao_speed_m_s = ao_speed_fit(evaluation_time_s)

    if direction == "forward" and (
        np.any(digital_speed_m_s <= 0.0) or np.any(ao_speed_m_s <= 0.0)
    ):
        raise RuntimeError("A fitted forward trajectory contains non-positive speed")
    if direction == "reverse" and (
        np.any(digital_speed_m_s >= 0.0) or np.any(ao_speed_m_s >= 0.0)
    ):
        raise RuntimeError("A fitted reverse trajectory contains non-negative speed")

    difference = ao_speed_m_s - digital_speed_m_s
    agreement_rmse = float(np.sqrt(np.mean(difference**2)))
    agreement_max = float(np.max(np.abs(difference)))

    output_base = args.output
    output_base.parent.mkdir(parents=True, exist_ok=True)
    csv_path = output_base.with_suffix(".csv")
    png_path = output_base.with_suffix(".png")
    report_path = output_base.with_suffix(".txt")

    with csv_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.writer(output_file)
        writer.writerow(
            [
                "time_relative_to_tc_s",
                "digital_position_m",
                "ao_position_m",
                "digital_speed_m_s",
                "ao_speed_m_s",
                "ao_minus_digital_speed_m_s",
            ]
        )
        for row in zip(
            evaluation_time_s,
            digital_position_m,
            ao_position_m,
            digital_speed_m_s,
            ao_speed_m_s,
            difference,
        ):
            writer.writerow([f"{float(value):.12f}" for value in row])

    figure, axes = plt.subplots(3, 1, figsize=(12, 10), sharex=True)
    sample_time_ms = sample_times_s * 1000.0
    axes[0].plot(sample_time_ms, adc_codes["A"], label="Hall A AO code", linewidth=0.8)
    axes[0].plot(sample_time_ms, adc_codes["B"], label="Hall B AO code", linewidth=0.8)
    axes[0].set_ylabel("ADC code")
    axes[0].set_title(
        f"{ao_calibration.get('evidence_label', 'TO_CONFIRM')}: combined trajectory fit"
    )
    axes[0].legend(loc="best")

    eval_time_ms = evaluation_time_s * 1000.0
    axes[1].plot(eval_time_ms, digital_position_m * 1000.0, label="Digital four-edge")
    axes[1].plot(eval_time_ms, ao_position_m * 1000.0, label="Dual-AO multi-point", linestyle="--")
    axes[1].scatter(edge_times_s * 1000.0, edge_positions_m * 1000.0, s=20, zorder=3)
    axes[1].set_ylabel("Position (mm)")
    axes[1].legend(loc="best")

    axes[2].plot(eval_time_ms, digital_speed_m_s, label="Digital four-edge speed")
    axes[2].plot(eval_time_ms, ao_speed_m_s, label="Dual-AO speed", linestyle="--")
    axes[2].axvline(0.0, color="black", linestyle=":", linewidth=0.8, label="tc")
    axes[2].set_xlabel("Time relative to tc (ms)")
    axes[2].set_ylabel("Instantaneous speed (m/s)")
    axes[2].ticklabel_format(axis="y", style="plain", useOffset=False)
    axes[2].legend(loc="best")
    margin_s = 0.010
    axes[2].set_xlim(
        evaluation_time_s[0] * 1000.0 - margin_s * 1000.0,
        evaluation_time_s[-1] * 1000.0 + margin_s * 1000.0,
    )

    for axis in axes:
        axis.grid(True, alpha=0.3)
    figure.tight_layout()
    figure.savefig(png_path, dpi=160)

    report_lines = [
        "CAR2 combined trajectory comparison",
        f"Edge evidence: {edge_calibration.get('evidence_label', 'TO_CONFIRM')}",
        f"AO evidence: {ao_calibration.get('evidence_label', 'TO_CONFIRM')}",
        f"Direction: {direction_name}",
        f"Selected AO capture: event {selected_event}",
        f"tc tick: {tc_tick:.3f}",
        f"Digital v(tc): {float(digital_speed_fit(0.0)):.9f} m/s",
        f"AO v(tc): {float(ao_speed_fit(0.0)):.9f} m/s",
        f"Method-agreement RMSE: {agreement_rmse:.9f} m/s",
        f"Method-agreement maximum difference: {agreement_max:.9f} m/s",
        "Accuracy status: NOT VERIFIED; agreement between methods is not independent validation.",
    ]
    report_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    print("\n".join(report_lines))
    print(f"Saved comparison CSV: {csv_path.resolve()}")
    print(f"Saved comparison plot: {png_path.resolve()}")
    print(f"Saved comparison report: {report_path.resolve()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}")
        raise SystemExit(1)
