"""Export the article's predictions and rtichoke points for R parity checks."""

from pathlib import Path

import numpy as np
import pandas as pd
from lifelines import CoxPHFitter
from rtichoke import create_calibration_curve_times


DATA_ROOT = (
    "https://raw.githubusercontent.com/"
    "danielegiardiello/Prediction_performance_survival/main/Data"
)
OUTPUT_DIR = Path("validation/generated")
HORIZONS = [1.0, 2.0, 3.0, 4.0, 5.0]


def rcs_3_eval(x: pd.Series, knots: list[float]) -> pd.Series:
    k0, k1, k2 = knots
    return (
        np.maximum(x - k0, 0) ** 3
        - np.maximum(x - k1, 0) ** 3 * (k2 - k0) / (k2 - k1)
        + np.maximum(x - k2, 0) ** 3 * (k1 - k0) / (k2 - k1)
    ) / (k2 - k0) ** 2


def prepare_data() -> tuple[pd.DataFrame, pd.DataFrame]:
    rotterdam = pd.read_csv(f"{DATA_ROOT}/rotterdam.csv")
    gbsg = pd.read_csv(f"{DATA_ROOT}/gbsg.csv")

    rotterdam["time"] = rotterdam["rtime"] / 365.25
    rotterdam["event"] = np.maximum(rotterdam["recur"], rotterdam["death"])
    death_only = (
        (rotterdam["event"] == 1)
        & (rotterdam["recur"] == 0)
        & (rotterdam["death"] == 1)
        & (rotterdam["rtime"] < rotterdam["dtime"])
    )
    rotterdam.loc[death_only, "time"] = (
        rotterdam.loc[death_only, "dtime"] / 365.25
    )
    gbsg["time"] = gbsg["rfstime"] / 365.25
    gbsg["event"] = gbsg["status"]

    rotterdam["size_20_50"] = (rotterdam["size"] == "20-50").astype(int)
    rotterdam["size_gt_50"] = (rotterdam["size"] == ">50").astype(int)
    gbsg["size_20_50"] = ((gbsg["size"] > 20) & (gbsg["size"] <= 50)).astype(
        int
    )
    gbsg["size_gt_50"] = (gbsg["size"] > 50).astype(int)

    for data in (rotterdam, gbsg):
        data["grade_3"] = (data["grade"] == 3).astype(int)
        data["nodes2"] = np.minimum(data["nodes"], 19)
        data["nodes3"] = rcs_3_eval(data["nodes2"], [0, 1, 9])
        data["event"] = np.where(
            (data["event"] == 1) & (data["time"] > 5), 0, data["event"]
        )
        data["time"] = np.minimum(data["time"], 5)

    features = ["size_20_50", "size_gt_50", "grade_3", "nodes2", "nodes3"]
    development = rotterdam[["time", "event", *features]]
    validation = gbsg[["pid", "time", "event", *features]]
    return development, validation


def main() -> None:
    development, validation = prepare_data()
    features = ["size_20_50", "size_gt_50", "grade_3", "nodes2", "nodes3"]
    cox = CoxPHFitter().fit(development, duration_col="time", event_col="event")
    prediction = (
        1 - cox.predict_survival_function(validation[features], times=[5.0]).iloc[0]
    ).to_numpy()

    patient_rows = []
    point_rows = []
    heuristics = [
        {
            "censoring_heuristic": "adjusted",
            "competing_heuristic": "adjusted_as_negative",
        }
    ]
    for horizon in HORIZONS:
        # This is the same rank-based grouping used internally by rtichoke.
        ranks = pd.Series(prediction).rank(method="average").to_numpy()
        decile = np.floor((ranks - 1) * 10 / len(prediction)).astype(int) + 1
        patient_rows.extend(
            {
                "pid": pid,
                "time": time,
                "event": event,
                "horizon": horizon,
                "prediction_python": pred,
                "decile": group,
            }
            for pid, time, event, pred, group in zip(
                validation["pid"],
                validation["time"],
                validation["event"],
                prediction,
                decile,
                strict=True,
            )
        )

    figure = create_calibration_curve_times(
        probs={"Rotterdam Cox model": prediction},
        reals=validation["event"].to_numpy(),
        times=validation["time"].to_numpy(),
        fixed_time_horizons=HORIZONS,
        heuristics_sets=heuristics,
        calibration_type="discrete",
    )
    for horizon_index, horizon in enumerate(HORIZONS):
        calibration_trace = figure.data[1 + horizon_index * 3]
        point_rows.extend(
            {
                "horizon": horizon,
                "decile": group,
                "mean_prediction_python": x,
                "observed_risk_rtichoke": y,
            }
            for group, (x, y) in enumerate(
                zip(calibration_trace.x, calibration_trace.y, strict=True), start=1
            )
        )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(patient_rows).to_csv(OUTPUT_DIR / "patients.csv", index=False)
    pd.DataFrame(point_rows).to_csv(OUTPUT_DIR / "points.csv", index=False)


if __name__ == "__main__":
    main()
