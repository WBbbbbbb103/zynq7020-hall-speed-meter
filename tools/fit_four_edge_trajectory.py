#!/usr/bin/env python3
"""Fit x(t) and instantaneous speed from four calibrated Hall edges."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path


EDGE_RE = re.compile(rb"^D,(AON|AOF|BON|BOF),([0-9A-F]{16})\r?\n$")
STATUS_RE = re.compile(rb"^D,STS,([0-9A-F]),([0-9A-F])\r?\n$")
EDGE_LABELS = ("AON", "AOF", "BON", "BOF")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fit a cubic trajectory from calibrated Hall edge positions"
    )
    parser.add_argument("--input", type=Path, required=True, help="Raw CAR2 UART file")
    parser.add_argument("--calibration", type=Path, required=True)
    parser.add_argument(
        "--output", type=Path, default=Path("capture/four_edge_trajectory")
    )
    return parser.parse_args()


def read_edges(path: Path) -> tuple[dict[str, int], int, int]:
    timestamps: dict[str, int] = {}
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

    missing = [label for label in EDGE_LABELS if label not in timestamps]
    if missing:
        raise RuntimeError(f"Missing edge records: {', '.join(missing)}")
    if status < 0 or seen < 0:
        raise RuntimeError("Missing D,STS status record")
    error = status & 0x1
    error_code = (status >> 1) & 0x3
    if error or error_code != 0 or seen != 0xF:
        raise RuntimeError(
            f"Invalid edge capture: error={error}, code={error_code}, seen=0x{seen:X}"
        )
    return timestamps, status, seen


def load_calibration(path: Path) -> dict[str, object]:
    with path.open("r", encoding="utf-8") as input_file:
        calibration = json.load(input_file)
    if "clock_hz" not in calibration:
        raise RuntimeError("Calibration file is missing clock_hz")
    for direction in ("forward", "reverse"):
        if direction not in calibration:
            raise RuntimeError(f"Calibration file is missing {direction}")
        for label in EDGE_LABELS:
            if f"{label}_mm" not in calibration[direction]:
                raise RuntimeError(f"Calibration is missing {direction}.{label}_mm")
    return calibration


def main() -> int:
    args = parse_args()
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import numpy as np
    except ImportError as exc:
        raise RuntimeError("numpy and matplotlib are required") from exc

    timestamps, _, _ = read_edges(args.input)
    calibration = load_calibration(args.calibration)
    clock_hz = float(calibration["clock_hz"])
    if clock_hz <= 0.0:
        raise RuntimeError("clock_hz must be positive")

    direction = "forward" if timestamps["AON"] < timestamps["BON"] else "reverse"
    direction_name = "Hall A -> Hall B" if direction == "forward" else "Hall B -> Hall A"
    position_config = calibration[direction]
    assert isinstance(position_config, dict)

    ticks = np.asarray([timestamps[label] for label in EDGE_LABELS], dtype=float)
    positions_m = np.asarray(
        [float(position_config[f"{label}_mm"]) / 1000.0 for label in EDGE_LABELS]
    )

    first_tick = float(np.min(ticks))
    last_tick = float(np.max(ticks))
    tc_tick = 0.5 * (first_tick + last_tick)
    edge_time_s = (ticks - tc_tick) / clock_hz

    trajectory = np.polynomial.Polynomial.fit(
        edge_time_s, positions_m, deg=3
    ).convert()
    speed = trajectory.deriv()

    evaluation_time_s = np.linspace(
        (first_tick - tc_tick) / clock_hz,
        (last_tick - tc_tick) / clock_hz,
        1001,
    )
    fitted_position_m = trajectory(evaluation_time_s)
    fitted_speed_m_s = speed(evaluation_time_s)

    if direction == "forward" and np.any(fitted_speed_m_s <= 0.0):
        raise RuntimeError("Fitted forward trajectory contains zero/negative speed")
    if direction == "reverse" and np.any(fitted_speed_m_s >= 0.0):
        raise RuntimeError("Fitted reverse trajectory contains zero/positive speed")

    output_base = args.output
    output_base.parent.mkdir(parents=True, exist_ok=True)
    csv_path = output_base.with_suffix(".csv")
    png_path = output_base.with_suffix(".png")
    report_path = output_base.with_suffix(".txt")

    with csv_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.writer(output_file)
        writer.writerow(
            ["time_relative_to_tc_s", "position_m", "instantaneous_speed_m_s"]
        )
        for row in zip(evaluation_time_s, fitted_position_m, fitted_speed_m_s):
            writer.writerow([f"{float(value):.12f}" for value in row])

    figure, axes = plt.subplots(2, 1, figsize=(11, 8), sharex=True)
    time_ms = evaluation_time_s * 1000.0
    axes[0].plot(time_ms, fitted_position_m * 1000.0, label="Cubic trajectory fit")
    axes[0].scatter(
        edge_time_s * 1000.0,
        positions_m * 1000.0,
        label="Calibrated edge points",
        zorder=3,
    )
    for label, edge_time, position in zip(EDGE_LABELS, edge_time_s, positions_m):
        axes[0].annotate(
            label,
            (edge_time * 1000.0, position * 1000.0),
            xytext=(4, 5),
            textcoords="offset points",
        )
    axes[0].set_ylabel("Position (mm)")
    axes[0].set_title(
        f"{calibration.get('evidence_label', 'TO_CONFIRM')}: digital four-edge fit"
    )
    axes[0].legend(loc="best")
    axes[0].grid(True, alpha=0.3)

    axes[1].plot(time_ms, fitted_speed_m_s, label="Instantaneous speed")
    axes[1].axvline(0.0, color="black", linestyle="--", linewidth=0.8, label="tc")
    axes[1].set_xlabel("Time relative to tc (ms)")
    axes[1].set_ylabel("Speed (m/s)")
    axes[1].ticklabel_format(axis="y", style="plain", useOffset=False)
    axes[1].legend(loc="best")
    axes[1].grid(True, alpha=0.3)
    figure.tight_layout()
    figure.savefig(png_path, dpi=160)

    edge_speed_m_s = speed(edge_time_s)
    report_lines = [
        "CAR2 digital four-edge trajectory fit",
        f"Evidence label: {calibration.get('evidence_label', 'TO_CONFIRM')}",
        f"Direction: {direction_name}",
        f"Clock: {clock_hz:.3f} Hz",
        f"tc tick: {tc_tick:.3f}",
        "tc definition: midpoint of the earliest and latest captured edge timestamps",
    ]
    for label, tick, relative_time, position, edge_speed in zip(
        EDGE_LABELS, ticks, edge_time_s, positions_m, edge_speed_m_s
    ):
        report_lines.append(
            f"{label}: tick={int(tick)}, t-tc={relative_time:.9f} s, "
            f"x={position * 1000.0:.6f} mm, v={edge_speed:.9f} m/s"
        )
    report_lines.extend(
        [
            f"v(tc): {float(speed(0.0)):.9f} m/s",
            "Accuracy status: NOT VERIFIED; independent measured validation data are required.",
        ]
    )
    report_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")

    print("\n".join(report_lines))
    print(f"Saved trajectory CSV: {csv_path.resolve()}")
    print(f"Saved trajectory plot: {png_path.resolve()}")
    print(f"Saved fit report: {report_path.resolve()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}")
        raise SystemExit(1)
