#!/usr/bin/env python3
"""
fig_country_ratio.py — Main text figure: ratio of EMRIO-based to
company-reported Scope 3 emissions, grouped by country.

Uses row==1 filtered data (purchased goods & services reporters only).
Same plotting logic as the appendix version but with fewer companies
and Y-axis ticks up to 10000x.

Original: scripts/GHG_scope_analyis/fig_country_python_redesign0210.ipynb (Cells 8-10)
          run with df_fig1_20240406.csv (row==1 filtered)
Paper reference: Figure in main text

Usage:
    python fig_country_ratio.py [--input INPUT_CSV] [--output OUTPUT_PDF]

Defaults:
    --input  ../output/figures/df_fig1_20240406.csv
    --output ../output/figures/fig_gS_compare_country_ratio.pdf
"""
import argparse
import os
import numpy as np
import pandas as pd
import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm


def main():
    parser = argparse.ArgumentParser(
        description="Generate main-text country ratio comparison plot"
    )
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_input = os.path.join(
        script_dir, "..", "output", "figures", "df_fig1_20240406.csv"
    )
    default_output = os.path.join(
        script_dir, "..", "output", "figures", "fig_gS_compare_country_ratio.pdf"
    )

    parser.add_argument("--input", default=default_input, help="Input CSV path")
    parser.add_argument("--output", default=default_output, help="Output PDF path")
    args = parser.parse_args()

    # ---- Load data ----
    df_fig1 = pd.read_csv(args.input)
    print(f"Loaded {len(df_fig1)} companies from {args.input}")

    # ---- Global style (journal) ----
    mpl.rcParams["axes.linewidth"] = 1.2
    mpl.rcParams["font.size"] = 10
    mpl.rcParams["figure.dpi"] = 300

    # ---- Hyperparameters (matching notebook Cell 10) ----
    HIGH_ESTIMATION_VMIN_RATIO = 0.00001
    LOW_ESTIMATION_VMIN_RATIO = 0.05
    EPSILON = 1e-3
    LINE_WIDTH = 0.2
    DOT_SIZE = 3
    DOT_LINEWIDTH = 0.2
    ALPHA_VALUE = 0.9

    # ---- Country configuration (hardcoded whitelist) ----
    countries = ["IND", "USA", "DEU", "GBR", "FRA", "JPN", "CAN", "BRA", "ESP"]
    country_name = {
        "IND": "  India",
        "USA": "United States",
        "DEU": "Germany",
        "GBR": "United\nKingdom",
        "FRA": "France",
        "JPN": "Japan",
        "CAN": "Canada",
        "BRA": "Brazil",
        "ESP": "Spain",
        "Other": "Others",
    }

    # Classify: keep specified countries, rest as "Other"
    df_fig1["ISO_COUNTRY"] = df_fig1["ISO_COUNTRY"].apply(
        lambda x: x if x in countries else "Other"
    )

    # ---- Compute ratio ----
    df_fig1["est_report_ratio"] = df_fig1["g_S3_est"] / df_fig1["g_S3_CDP_c"].replace(
        0, np.nan
    )

    # ---- Sort countries by company count (descending), "Other" last ----
    country_counts = df_fig1["ISO_COUNTRY"].value_counts()
    sorted_countries = [c for c in country_counts.index if c != "Other"]
    sorted_countries = sorted(
        sorted_countries, key=lambda c: country_counts[c], reverse=True
    ) + ["Other"]

    # Sort within each country by est_report_ratio (largest first)
    df_fig1["ISO_COUNTRY"] = pd.Categorical(
        df_fig1["ISO_COUNTRY"], categories=sorted_countries, ordered=True
    )
    df_fig1 = df_fig1.sort_values(
        by=["ISO_COUNTRY", "est_report_ratio"], ascending=[True, False]
    )

    # ---- Compute x positions ----
    spacing_factor = 5
    group_spacing = 20
    x_positions = []
    current_x = 0
    country_blocks = {}

    for country in sorted_countries:
        subset_size = (df_fig1["ISO_COUNTRY"] == country).sum()
        x_positions.extend(
            range(current_x, current_x + subset_size * spacing_factor, spacing_factor)
        )
        country_blocks[country] = (current_x, current_x + subset_size * spacing_factor)
        current_x += subset_size * spacing_factor + group_spacing

    df_fig1["x_position"] = x_positions

    # ---- Ratio-based y values ----
    df_fig1["y_reported"] = 1
    df_fig1["y_estimated"] = df_fig1["est_report_ratio"]
    df_fig1["line_length"] = abs(df_fig1["y_estimated"] - df_fig1["y_reported"])

    # ---- LogNorm color normalization ----
    cmap_high = plt.get_cmap("Reds")
    cmap_low = plt.get_cmap("Blues")

    high_all = df_fig1[df_fig1["y_estimated"] > 1]
    low_all = df_fig1[df_fig1["y_estimated"] <= 1]

    if not high_all.empty:
        max_high = high_all["line_length"].max()
        vmin_high = max(max_high * HIGH_ESTIMATION_VMIN_RATIO, EPSILON)
        norm_high = LogNorm(vmin=vmin_high, vmax=max_high)
    else:
        norm_high = LogNorm(vmin=EPSILON, vmax=1)

    if not low_all.empty:
        max_low = low_all["line_length"].max()
        vmin_low = max(max_low * LOW_ESTIMATION_VMIN_RATIO, EPSILON)
        norm_low = LogNorm(vmin=vmin_low, vmax=max_low)
    else:
        norm_low = LogNorm(vmin=EPSILON, vmax=1)

    # ---- Create figure ----
    fig, ax = plt.subplots(figsize=(8.5, 5))
    ax.set_yscale("log")

    # Alternating background per country block
    for i, country in enumerate(sorted_countries):
        if i % 2 == 0:
            x_start, x_end = country_blocks[country]
            ax.axvspan(x_start, x_end, color="lightgray", alpha=0.3)

    # ---- Draw lines and scatter ----
    for country in sorted_countries:
        subset = df_fig1[df_fig1["ISO_COUNTRY"] == country]
        if subset.empty:
            continue

        for _, row in subset.iterrows():
            if row["y_estimated"] > 1:
                color = cmap_high(norm_high(row["line_length"]))
            else:
                color = cmap_low(norm_low(row["line_length"]))

            # Connecting line (from reported to estimated)
            ax.plot(
                [row["x_position"], row["x_position"]],
                [row["y_reported"], row["y_estimated"]],
                color=color,
                linewidth=LINE_WIDTH,
                alpha=ALPHA_VALUE,
                zorder=2,
            )

            # Estimated value (hollow gray circle)
            ax.scatter(
                row["x_position"],
                row["y_estimated"],
                facecolors="none",
                edgecolors="gray",
                alpha=ALPHA_VALUE,
                s=DOT_SIZE,
                linewidth=DOT_LINEWIDTH,
                zorder=3,
            )

            # Reported value (solid gray circle)
            ax.scatter(
                row["x_position"],
                row["y_reported"],
                color="gray",
                alpha=ALPHA_VALUE,
                s=DOT_SIZE - 2.5,
                zorder=3,
            )

    # ---- Journal-style axis formatting ----
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_linewidth(1.2)
    ax.spines["bottom"].set_linewidth(1.2)
    ax.tick_params(axis="both", which="both", direction="in", length=5, width=1.2)
    ax.minorticks_off()

    # No x-axis ticks
    ax.xaxis.set_major_locator(plt.NullLocator())

    # ---- Y-axis ticks (no 100000x — data max is ~17000x) ----
    predefined_ticks = [0.01, 0.1, 1, 10, 100, 1000, 10000]
    ax.set_yticks(predefined_ticks)
    yticklabels = []
    for t in predefined_ticks:
        if t < 0.1:
            label = f"{t:.2f}x"
        elif t < 1:
            label = f"{t:.1f}x"
        else:
            label = f"{int(t)}x"
        yticklabels.append(label)
    ax.set_yticklabels(yticklabels)

    # ---- Country name labels ----
    y_max = df_fig1["y_estimated"].max()
    country_positions = df_fig1.groupby("ISO_COUNTRY", observed=True)["x_position"].median()
    no_rotate_countries = {sorted_countries[0], sorted_countries[1], sorted_countries[-1]}

    for country, pos in country_positions.items():
        if country in country_name:
            rot = 0 if country in no_rotate_countries else 45
            ax.text(
                pos,
                y_max * 1.05,
                country_name[country],
                ha="center",
                va="bottom",
                fontsize=9,
                rotation=rot,
                rotation_mode="anchor",
            )

    # ---- Axis labels (no title, matching notebook) ----
    ax.set_xlabel("Company Rank within Country (Sorted by Ratio)", fontsize=10)
    ax.set_ylabel(
        "Ratio of EMRIO-Based to Company-Reported Scope 3 Emissions", fontsize=10
    )

    # ---- Save ----
    plt.tight_layout()
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    plt.savefig(args.output)
    print(f"Saved to {args.output}")
    plt.close()


if __name__ == "__main__":
    main()
