#!/usr/bin/env python3
"""PC-only comparison of digital four-edge and dual-AO trajectory fitting."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


SAMPLE_RATE_HZ = 50_000.0
FPGA_CLOCK_HZ = 50_000_000.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Simulate variable-acceleration motion and compare digital four-edge "
            "and dual-AO trajectory fitting"
        )
    )
    parser.add_argument("--spacing-mm", type=float, default=100.0)
    parser.add_argument("--v0-m-s", type=float, default=1.5)
    parser.add_argument("--accel-m-s2", type=float, default=4.0)
    parser.add_argument("--jerk-m-s3", type=float, default=20.0)
    parser.add_argument("--field-sigma-mm", type=float, default=18.0)
    parser.add_argument("--seed", type=int, default=20260919)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("capture/two_method_variable_accel"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.spacing_mm <= 0.0 or args.field_sigma_mm <= 0.0:
        raise RuntimeError("Spacing and field sigma must both be positive")

    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import numpy as np
    except ImportError as exc:
        raise RuntimeError("This demo requires numpy and matplotlib") from exc

    spacing_m = args.spacing_mm / 1000.0
    sigma_m = args.field_sigma_mm / 1000.0
    v0 = args.v0_m_s
    accel0 = args.accel_m_s2
    jerk = args.jerk_m_s3

    time_s = np.arange(-0.100, 0.160, 1.0 / SAMPLE_RATE_HZ)
    true_position_m = (
        v0 * time_s
        + 0.5 * accel0 * time_s**2
        + (jerk / 6.0) * time_s**3
    )
    true_speed_m_s = v0 + accel0 * time_s + 0.5 * jerk * time_s**2

    if np.any(true_speed_m_s <= 0.0):
        raise RuntimeError("Chosen motion is not monotonic over the demo time window")

    rng = np.random.default_rng(args.seed)
    centers_m = {"A": 0.0, "B": spacing_m}
    baselines_v = {"A": 2.10, "B": 2.25}
    amplitudes_v = {"A": 2.00, "B": 1.85}
    ao_v: dict[str, object] = {}
    normalized: dict[str, object] = {}

    for channel in ("A", "B"):
        field = np.exp(
            -0.5 * ((true_position_m - centers_m[channel]) / sigma_m) ** 2
        )
        noise = rng.normal(0.0, 0.006, size=time_s.size)
        ripple = 0.004 * np.sin(
            2.0 * np.pi * (690.0 if channel == "A" else 610.0) * time_s
        )
        ao_v[channel] = (
            baselines_v[channel] + amplitudes_v[channel] * field + noise + ripple
        )
        normalized[channel] = np.clip(
            (ao_v[channel] - baselines_v[channel]) / amplitudes_v[channel],
            1.0e-6,
            1.0,
        )

    # Digital method: a calibrated threshold maps each ON/OFF edge to a position.
    threshold = 0.45
    half_width_m = sigma_m * np.sqrt(-2.0 * np.log(threshold))
    edge_positions = np.asarray(
        [
            centers_m["A"] - half_width_m,
            centers_m["A"] + half_width_m,
            centers_m["B"] - half_width_m,
            centers_m["B"] + half_width_m,
        ]
    )
    edge_names = ["A_ON", "A_OFF", "B_ON", "B_OFF"]

    def time_at_position(position_m: float) -> float:
        roots = np.roots(
            [jerk / 6.0, accel0 / 2.0, v0, -float(position_m)]
        )
        valid = [
            float(root.real)
            for root in roots
            if abs(root.imag) < 1.0e-9 and time_s[0] <= root.real <= time_s[-1]
        ]
        if len(valid) != 1:
            raise RuntimeError(f"Could not uniquely invert position {position_m}")
        return valid[0]

    edge_times_exact = np.asarray(
        [time_at_position(position) for position in edge_positions]
    )
    edge_times_s = np.round(edge_times_exact * FPGA_CLOCK_HZ) / FPGA_CLOCK_HZ
    digital_position_fit = np.polynomial.Polynomial.fit(
        edge_times_s, edge_positions, deg=3
    ).convert()
    digital_speed_fit = digital_position_fit.deriv()

    # AO method: invert calibrated spatial templates to obtain many x(t) points.
    ao_times_parts = []
    ao_positions_parts = []
    for channel in ("A", "B"):
        values = normalized[channel]
        peak_index = int(np.argmax(ao_v[channel]))
        peak_time_s = time_s[peak_index]
        useful = (values > 0.12) & (values < 0.94)
        useful_times = time_s[useful]
        useful_values = values[useful]
        relative_distance_m = sigma_m * np.sqrt(-2.0 * np.log(useful_values))
        signs = np.where(useful_times < peak_time_s, -1.0, 1.0)
        useful_positions = centers_m[channel] + signs * relative_distance_m
        ao_times_parts.append(useful_times)
        ao_positions_parts.append(useful_positions)

    ao_times_s = np.concatenate(ao_times_parts)
    ao_positions_m = np.concatenate(ao_positions_parts)
    ao_position_fit = np.polynomial.Polynomial.fit(
        ao_times_s, ao_positions_m, deg=3
    ).convert()
    ao_speed_fit = ao_position_fit.deriv()

    digital_position_m = digital_position_fit(time_s)
    ao_position_m = ao_position_fit(time_s)
    digital_speed_m_s = digital_speed_fit(time_s)
    ao_speed_m_s = ao_speed_fit(time_s)

    fit_start_s = float(np.min(edge_times_s))
    fit_end_s = float(np.max(edge_times_s))
    evaluation = (time_s >= fit_start_s) & (time_s <= fit_end_s)

    def error_metrics(estimate):
        error = estimate[evaluation] - true_speed_m_s[evaluation]
        return float(np.sqrt(np.mean(error**2))), float(np.max(np.abs(error)))

    digital_rmse, digital_max = error_metrics(digital_speed_m_s)
    ao_rmse, ao_max = error_metrics(ao_speed_m_s)

    output_base = args.output
    output_base.parent.mkdir(parents=True, exist_ok=True)
    csv_path = output_base.with_suffix(".csv")
    png_path = output_base.with_suffix(".png")
    report_path = output_base.with_suffix(".txt")

    with csv_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.writer(output_file)
        writer.writerow(
            [
                "time_s",
                "true_position_m",
                "true_speed_m_s",
                "digital_fit_speed_m_s",
                "ao_fit_speed_m_s",
                "hall_a_ao_v",
                "hall_b_ao_v",
            ]
        )
        for row in zip(
            time_s,
            true_position_m,
            true_speed_m_s,
            digital_speed_m_s,
            ao_speed_m_s,
            ao_v["A"],
            ao_v["B"],
        ):
            writer.writerow([f"{float(value):.9f}" for value in row])

    figure, axes = plt.subplots(3, 1, figsize=(12, 10), sharex=True)
    time_ms = time_s * 1000.0
    axes[0].plot(time_ms, ao_v["A"], label="Hall A AO", linewidth=1.0)
    axes[0].plot(time_ms, ao_v["B"], label="Hall B AO", linewidth=1.0)
    for name, edge_time in zip(edge_names, edge_times_s):
        axes[0].axvline(edge_time * 1000.0, linestyle="--", linewidth=0.8)
        axes[0].text(
            edge_time * 1000.0,
            axes[0].get_ylim()[0],
            name,
            rotation=90,
            va="bottom",
            ha="right",
            fontsize=8,
        )
    axes[0].set_ylabel("AO voltage (V)")
    axes[0].set_title("SIM: two Hall sensors observing the same variable-acceleration pass")
    axes[0].legend(loc="best")

    axes[1].plot(time_ms, true_position_m * 1000.0, label="True position", linewidth=2.0)
    axes[1].plot(
        time_ms,
        digital_position_m * 1000.0,
        label="Digital four-edge fit",
        linestyle="--",
    )
    axes[1].plot(
        time_ms,
        ao_position_m * 1000.0,
        label="Dual-AO multi-point fit",
        linestyle=":",
    )
    axes[1].scatter(edge_times_s * 1000.0, edge_positions * 1000.0, s=25, zorder=4)
    axes[1].set_ylabel("Position (mm)")
    axes[1].legend(loc="best")

    axes[2].plot(time_ms, true_speed_m_s, label="True instantaneous speed", linewidth=2.0)
    axes[2].plot(
        time_ms,
        digital_speed_m_s,
        label=f"Digital fit (RMSE {digital_rmse:.4f} m/s)",
        linestyle="--",
    )
    axes[2].plot(
        time_ms,
        ao_speed_m_s,
        label=f"AO fit (RMSE {ao_rmse:.4f} m/s)",
        linestyle=":",
    )
    axes[2].axvspan(
        fit_start_s * 1000.0,
        fit_end_s * 1000.0,
        color="green",
        alpha=0.08,
        label="Valid fitted interval",
    )
    axes[2].set_xlabel("Time relative to Hall A center crossing (ms)")
    axes[2].set_ylabel("Instantaneous speed (m/s)")
    axes[2].legend(loc="best")

    for axis in axes:
        axis.grid(True, alpha=0.3)
    figure.tight_layout()
    figure.savefig(png_path, dpi=160)

    report_lines = [
        "CAR2 PC-only trajectory-fitting demo (SIM, not measured)",
        f"Hall spacing: {args.spacing_mm:.3f} mm",
        f"True motion: v0={v0:.6f} m/s, a0={accel0:.6f} m/s^2, jerk={jerk:.6f} m/s^3",
        f"Digital four-edge speed RMSE: {digital_rmse:.9f} m/s",
        f"Digital four-edge maximum error: {digital_max:.9f} m/s",
        f"Dual-AO speed RMSE: {ao_rmse:.9f} m/s",
        f"Dual-AO maximum error: {ao_max:.9f} m/s",
        f"Valid fitted interval: {fit_start_s * 1000.0:.5f} to {fit_end_s * 1000.0:.5f} ms",
        "Real AO fitting requires measured spatial templates and gain/offset calibration.",
    ]
    report_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")

    print("\n".join(report_lines))
    print(f"Saved plot: {png_path.resolve()}")
    print(f"Saved CSV: {csv_path.resolve()}")
    print(f"Saved report: {report_path.resolve()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}")
        raise SystemExit(1)
