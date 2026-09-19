#!/usr/bin/env python3
"""Generate a deterministic, explicitly simulated two-method comparison figure.

The synthetic data intentionally include small, declared calibration mismatch,
timestamp jitter, AO noise, ripple, and template mismatch.  They are not
measurements and must not be presented as hardware evidence.
"""

from __future__ import annotations

import csv
from pathlib import Path


SAMPLE_RATE_HZ = 50_000.0
FPGA_CLOCK_HZ = 50_000_000.0
SEED = 20260920


def main() -> int:
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import numpy as np
    except ImportError as exc:
        raise RuntimeError("numpy and matplotlib are required") from exc

    output_base = Path("capture/two_method_realistic_sim")
    output_base.parent.mkdir(parents=True, exist_ok=True)
    png_path = output_base.with_suffix(".png")
    csv_path = output_base.with_suffix(".csv")
    report_path = output_base.with_suffix(".txt")

    # Synthetic variable-acceleration pass. Hall A is centred at x=0 and Hall B
    # at x=100 mm. The motion remains monotonic over the plotted interval.
    spacing_m = 0.100
    nominal_sigma_m = 0.018
    v0 = 1.50
    accel0 = 4.0
    jerk = 20.0
    time_s = np.arange(-0.100, 0.160, 1.0 / SAMPLE_RATE_HZ)
    true_position_m = (
        v0 * time_s
        + 0.5 * accel0 * time_s**2
        + (jerk / 6.0) * time_s**3
    )
    true_speed_m_s = v0 + accel0 * time_s + 0.5 * jerk * time_s**2

    def time_at_position(position_m: float) -> float:
        roots = np.roots([jerk / 6.0, accel0 / 2.0, v0, -position_m])
        valid = [
            float(root.real)
            for root in roots
            if abs(root.imag) < 1.0e-9 and time_s[0] <= root.real <= time_s[-1]
        ]
        if len(valid) != 1:
            raise RuntimeError(f"Could not invert synthetic position {position_m}")
        return valid[0]

    rng = np.random.default_rng(SEED)

    # Digital four-edge observations. The event times follow the true motion,
    # while the positions used by the estimator include sub-millimetre
    # calibration mismatch and the times include several microseconds of jitter.
    threshold = 0.45
    half_width_m = nominal_sigma_m * np.sqrt(-2.0 * np.log(threshold))
    true_edge_positions_m = np.asarray(
        [-half_width_m, half_width_m, spacing_m - half_width_m, spacing_m + half_width_m]
    )
    edge_names = ("A ON", "A OFF", "B ON", "B OFF")
    exact_edge_times_s = np.asarray(
        [time_at_position(position) for position in true_edge_positions_m]
    )
    timestamp_jitter_s = np.asarray([5.6, -4.2, 6.8, -5.1]) * 1.0e-6
    measured_edge_times_s = np.round(
        (exact_edge_times_s + timestamp_jitter_s) * FPGA_CLOCK_HZ
    ) / FPGA_CLOCK_HZ
    position_calibration_error_m = np.asarray([0.32, -0.24, 0.38, -0.31]) * 1.0e-3
    calibrated_edge_positions_m = true_edge_positions_m + position_calibration_error_m

    digital_position_fit = np.polynomial.Polynomial.fit(
        measured_edge_times_s, calibrated_edge_positions_m, deg=3
    ).convert()
    digital_speed_fit = digital_position_fit.deriv()

    # Dual-AO signals use slightly non-identical real sensors. The estimator
    # intentionally uses a nominal symmetric template, as a real calibration
    # never matches the instantaneous waveform perfectly.
    channels = {
        "A": {
            "true_center_m": -0.00015,
            "fit_center_m": 0.00080,
            "true_sigma_m": 0.01835,
            "baseline_v": 2.10,
            "amplitude_v": 2.00,
            "fit_baseline_v": 2.106,
            "fit_amplitude_v": 1.988,
            "ripple_hz": 690.0,
            "skew": 0.018,
        },
        "B": {
            "true_center_m": spacing_m + 0.00025,
            "fit_center_m": spacing_m - 0.00070,
            "true_sigma_m": 0.01770,
            "baseline_v": 2.25,
            "amplitude_v": 1.85,
            "fit_baseline_v": 2.243,
            "fit_amplitude_v": 1.865,
            "ripple_hz": 610.0,
            "skew": -0.015,
        },
    }

    ao_voltage: dict[str, object] = {}
    ao_times_parts = []
    ao_positions_parts = []
    for name, config in channels.items():
        z = (true_position_m - config["true_center_m"]) / config["true_sigma_m"]
        field = np.exp(-0.5 * z**2) * np.clip(1.0 + config["skew"] * z, 0.90, 1.10)
        noise_v = rng.normal(0.0, 0.014, size=time_s.size)
        ripple_v = 0.005 * np.sin(2.0 * np.pi * config["ripple_hz"] * time_s)
        drift_v = 0.010 * (time_s - time_s.mean())
        voltage = (
            config["baseline_v"]
            + config["amplitude_v"] * field
            + noise_v
            + ripple_v
            + drift_v
        )
        ao_voltage[name] = voltage

        normalized = np.clip(
            (voltage - config["fit_baseline_v"]) / config["fit_amplitude_v"],
            1.0e-6,
            1.0,
        )
        useful = (normalized > 0.16) & (normalized < 0.91)
        useful_times_s = time_s[useful]
        useful_values = normalized[useful]
        peak_time_s = time_s[int(np.argmax(voltage))]
        distance_m = nominal_sigma_m * np.sqrt(-2.0 * np.log(useful_values))
        signs = np.where(useful_times_s < peak_time_s, -1.0, 1.0)
        inferred_positions_m = config["fit_center_m"] + signs * distance_m
        ao_times_parts.append(useful_times_s)
        ao_positions_parts.append(inferred_positions_m)

    ao_observation_times_s = np.concatenate(ao_times_parts)
    ao_observation_positions_m = np.concatenate(ao_positions_parts)
    ao_position_fit = np.polynomial.Polynomial.fit(
        ao_observation_times_s, ao_observation_positions_m, deg=3
    ).convert()
    ao_speed_fit = ao_position_fit.deriv()

    fit_start_s = float(np.min(measured_edge_times_s))
    fit_end_s = float(np.max(measured_edge_times_s))
    tc_s = 0.5 * (fit_start_s + fit_end_s)
    evaluation = (time_s >= fit_start_s) & (time_s <= fit_end_s)
    eval_time_s = time_s[evaluation]
    time_relative_tc_ms = (time_s - tc_s) * 1000.0

    digital_position_m = digital_position_fit(time_s)
    ao_position_m = ao_position_fit(time_s)
    digital_speed_m_s = digital_speed_fit(time_s)
    ao_speed_m_s = ao_speed_fit(time_s)

    def metrics(estimate):
        error = estimate[evaluation] - true_speed_m_s[evaluation]
        return float(np.sqrt(np.mean(error**2))), float(np.max(np.abs(error)))

    digital_rmse, digital_max = metrics(digital_speed_m_s)
    ao_rmse, ao_max = metrics(ao_speed_m_s)
    method_difference = ao_speed_m_s[evaluation] - digital_speed_m_s[evaluation]
    agreement_rmse = float(np.sqrt(np.mean(method_difference**2)))
    agreement_max = float(np.max(np.abs(method_difference)))

    with csv_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.writer(output_file)
        writer.writerow(
            [
                "time_relative_tc_s",
                "true_position_m",
                "digital_position_m",
                "ao_position_m",
                "true_speed_m_s",
                "digital_speed_m_s",
                "ao_speed_m_s",
                "hall_a_ao_v",
                "hall_b_ao_v",
            ]
        )
        for row in zip(
            time_s - tc_s,
            true_position_m,
            digital_position_m,
            ao_position_m,
            true_speed_m_s,
            digital_speed_m_s,
            ao_speed_m_s,
            ao_voltage["A"],
            ao_voltage["B"],
        ):
            writer.writerow([f"{float(value):.12f}" for value in row])

    blue = "#0072B2"
    orange = "#E69F00"
    green = "#009E73"
    black = "#222222"
    with plt.rc_context(
        {
            "font.size": 10,
            "axes.titlesize": 11,
            "axes.labelsize": 10,
            "legend.fontsize": 9,
            "figure.facecolor": "white",
            "axes.facecolor": "white",
            "savefig.facecolor": "white",
        }
    ):
        figure, axes = plt.subplots(
            3, 1, figsize=(12.2, 10.5), sharex=True, layout="constrained"
        )

        axes[0].plot(time_relative_tc_ms, ao_voltage["A"], color=blue, label="Hall A AO", linewidth=1.0)
        axes[0].plot(time_relative_tc_ms, ao_voltage["B"], color=orange, label="Hall B AO", linewidth=1.0)
        for edge_name, edge_time_s in zip(edge_names, measured_edge_times_s):
            x_ms = (edge_time_s - tc_s) * 1000.0
            axes[0].axvline(x_ms, color="#777777", linestyle="--", linewidth=0.8)
            axes[0].annotate(
                edge_name,
                xy=(x_ms, axes[0].get_ylim()[0]),
                xytext=(3, 4),
                textcoords="offset points",
                rotation=90,
                va="bottom",
                ha="left",
                fontsize=8,
            )
        axes[0].set_ylabel("AO voltage (V)")
        axes[0].legend(loc="upper right")

        axes[1].plot(time_relative_tc_ms, true_position_m * 1000.0, color=black, linewidth=2.0, label="True simulated position")
        axes[1].plot(time_relative_tc_ms, digital_position_m * 1000.0, color=blue, linestyle="--", linewidth=1.7, label="Digital four-edge fit")
        axes[1].plot(time_relative_tc_ms, ao_position_m * 1000.0, color=orange, linestyle=":", linewidth=2.0, label="Dual-AO multi-point fit")
        observation_step = max(1, ao_observation_times_s.size // 360)
        axes[1].scatter(
            (ao_observation_times_s[::observation_step] - tc_s) * 1000.0,
            ao_observation_positions_m[::observation_step] * 1000.0,
            color=orange,
            marker=".",
            alpha=0.50,
            s=15,
            linewidth=0.0,
            zorder=2,
            label="Noisy AO position observations",
        )
        axes[1].scatter(
            (measured_edge_times_s - tc_s) * 1000.0,
            calibrated_edge_positions_m * 1000.0,
            color=blue,
            marker="o",
            edgecolor="white",
            linewidth=0.6,
            s=35,
            zorder=4,
            label="Calibrated digital edge points",
        )
        axes[1].set_ylabel("Position (mm)")
        axes[1].legend(loc="upper left", ncol=2)

        axes[2].plot(time_relative_tc_ms, true_speed_m_s, color=black, linewidth=2.0, label="True simulated speed")
        axes[2].plot(time_relative_tc_ms, digital_speed_m_s, color=blue, linestyle="--", linewidth=1.7, label=f"Digital fit (RMSE {digital_rmse:.3f} m/s)")
        axes[2].plot(time_relative_tc_ms, ao_speed_m_s, color=orange, linestyle=":", linewidth=2.1, label=f"AO fit (RMSE {ao_rmse:.3f} m/s)")
        axes[2].axvspan(
            (fit_start_s - tc_s) * 1000.0,
            (fit_end_s - tc_s) * 1000.0,
            color=green,
            alpha=0.09,
            label="Fitted interval",
        )
        axes[2].axvline(0.0, color="#666666", linestyle="-.", linewidth=0.9, label="$t_c$")
        axes[2].set_xlabel("Time relative to $t_c$ (ms)")
        axes[2].set_ylabel("Instantaneous speed (m/s)")
        axes[2].legend(loc="upper left", ncol=2)

        x_min = (fit_start_s - tc_s) * 1000.0 - 16.0
        x_max = (fit_end_s - tc_s) * 1000.0 + 16.0
        axes[2].set_xlim(x_min, x_max)
        position_view = (time_relative_tc_ms >= x_min) & (time_relative_tc_ms <= x_max)
        position_min_mm = 1000.0 * min(
            float(np.min(true_position_m[position_view])),
            float(np.min(digital_position_m[position_view])),
            float(np.min(ao_position_m[position_view])),
        )
        position_max_mm = 1000.0 * max(
            float(np.max(true_position_m[position_view])),
            float(np.max(digital_position_m[position_view])),
            float(np.max(ao_position_m[position_view])),
        )
        axes[1].set_ylim(position_min_mm - 8.0, position_max_mm + 8.0)
        for axis in axes:
            axis.grid(True, color="#B0B0B0", alpha=0.30, linewidth=0.7)

        figure.text(
            0.995,
            0.004,
            "SIMULATION / NOT MEASURED",
            ha="right",
            va="bottom",
            fontsize=8,
            color="#666666",
        )
        figure.savefig(png_path, dpi=220, metadata={"Title": "Simulation only - not measured", "Software": "Matplotlib"})

    def value_at_tc(values):
        return float(np.interp(tc_s, time_s, values))

    report_lines = [
        "SIMULATION ONLY - NOT MEASURED",
        f"Deterministic random seed: {SEED}",
        "Declared synthetic mismatches: timestamp jitter, edge-position calibration error,",
        "AO noise/ripple/drift, sensor asymmetry, and nominal-template mismatch.",
        f"Fitted interval relative to tc: {(fit_start_s-tc_s)*1000.0:.6f} to {(fit_end_s-tc_s)*1000.0:.6f} ms",
        f"True v(tc): {value_at_tc(true_speed_m_s):.9f} m/s",
        f"Digital v(tc): {value_at_tc(digital_speed_m_s):.9f} m/s",
        f"AO v(tc): {value_at_tc(ao_speed_m_s):.9f} m/s",
        f"Digital speed RMSE: {digital_rmse:.9f} m/s; max error: {digital_max:.9f} m/s",
        f"AO speed RMSE: {ao_rmse:.9f} m/s; max error: {ao_max:.9f} m/s",
        f"Digital/AO agreement RMSE: {agreement_rmse:.9f} m/s; max difference: {agreement_max:.9f} m/s",
        "These values demonstrate algorithm behaviour only and are not hardware accuracy evidence.",
    ]
    report_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    print("\n".join(report_lines))
    print(f"Saved plot: {png_path.resolve()}")
    print(f"Saved data: {csv_path.resolve()}")
    print(f"Saved report: {report_path.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
