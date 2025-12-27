import polars as pl
import numpy as np
import plotly.graph_objects as go
from plotly.subplots import make_subplots

def _make_deciles_dat_binary(
    probs: dict[str, np.ndarray],
    reals: np.ndarray,
    n_bins: int = 10,
) -> pl.DataFrame:
    y = np.asarray(reals).ravel()
    n = y.shape[0]
    frames = []
    for model, p in probs.items():
        p = np.asarray(p).ravel()
        if p.shape[0] != n:
            raise ValueError(
                f"probs['{model}'] length={p.shape[0]} does not match reals length={n}."
            )
        frames.append(
            pl.DataFrame(
                {
                    "reference_group": model,
                    "model": model,
                    "prob": p.astype(float, copy=False),
                    "real": y.astype(float, copy=False),
                }
            )
        )

    df = pl.concat(frames, how="vertical")

    labels = [str(i) for i in range(1, n_bins + 1)]

    df = df.with_columns(
        [
            pl.col("prob").cast(pl.Float64),
            pl.col("real").cast(pl.Float64),
            pl.col("prob")
            .qcut(n_bins, labels=labels, allow_duplicates=True)
            .over(["reference_group", "model"])
            .alias("decile"),
        ]
    ).with_columns(pl.col("decile").cast(pl.Int32))

    deciles_data = (
        df.group_by(["reference_group", "model", "decile"])
        .agg(
            [
                pl.len().alias("n"),
                pl.mean("prob").alias("x"),
                pl.mean("real").alias("y"),
                pl.sum("real").alias("n_reals"),
            ]
        )
        .sort(["reference_group", "model", "x"])  # Sort by mean predicted probability
    )

    return deciles_data


def create_calibration_curve_workaround(
    probs: dict[str, np.ndarray],
    reals: np.ndarray,
    n_bins: int = 10,
    size: int = 600,
    color_values: list[str] = [
        "#1b9e77",
        "#d95f02",
        "#7570b3",
        "#e7298a",
        "#07004D",
        "#E6AB02",
        "#FE5F55",
        "#54494B",
        "#006E90",
        "#BC96E6",
        "#52050A",
        "#1F271B",
        "#BE7C4D",
        "#63768D",
        "#08A045",
        "#320A28",
        "#82FF9E",
        "#2176FF",
        "#D1603D",
        "#585123",
    ],
) -> go.Figure:
    deciles_data = _make_deciles_dat_binary(probs, reals, n_bins)

    fig = make_subplots(
        rows=2, cols=1, shared_xaxes=True, x_title="Predicted", row_heights=[0.8, 0.2]
    )

    fig.update_layout(
        {
            "xaxis": {"showgrid": False},
            "yaxis": {"showgrid": False},
            "barmode": "overlay",
            "plot_bgcolor": "rgba(0, 0, 0, 0)",
            "legend": {
                "orientation": "h",
                "xanchor": "center",
                "yanchor": "top",
                "x": 0.5,
                "y": 1.3,
                "bgcolor": "rgba(0, 0, 0, 0)",
            },
            "showlegend": True,
        }
    )

    x_ref = np.linspace(0, 1, 101)
    reference_data = pl.DataFrame({"x": x_ref, "y": x_ref})

    fig.add_trace(
        go.Scatter(
            x=reference_data["x"],
            y=reference_data["y"],
            name="Perfectly Calibrated",
            legendgroup="Perfectly Calibrated",
            hoverinfo="text",
            line={
                "width": 2,
                "dash": "dot",
                "color": "#BEBEBE",
            },
            showlegend=False,
        ),
        row=1,
        col=1,
    )

    reference_groups = deciles_data["reference_group"].unique().to_list()

    for i, reference_group in enumerate(reference_groups):
        dec_sub = deciles_data.filter(
            pl.col("reference_group") == reference_group
        )

        fig.add_trace(
            go.Scatter(
                x=dec_sub.get_column("x").to_list(),
                y=dec_sub.get_column("y").to_list(),
                name=reference_group,
                legendgroup=reference_group,
                hoverinfo="text",
                mode="lines+markers",
                marker={
                    "size": 10,
                    "color": color_values[i % len(color_values)],
                },
            ),
            row=1,
            col=1,
        )

    fig.update_layout(
        width=size,
        height=size,
    )

    return fig
