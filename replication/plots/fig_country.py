#!/usr/bin/env python3
"""
fig_country.py — Country comparison: estimated vs reported Scope 3 emissions.

Original: scripts/GHG_scope_analyis/fig_country_python_redesign0210.ipynb (Cell 7)
Paper reference: Figure 1

Usage:
    python fig_country.py [--input INPUT_CSV] [--output OUTPUT_PDF]

Defaults:
    --input  ../output/figures/df_fig1_20240406.csv
    --output ../output/figures/fig_country.pdf
"""
import argparse
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


def main():
    parser = argparse.ArgumentParser(description="Generate country comparison plot")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_input = os.path.join(script_dir, "..", "output", "figures", "df_fig1_20240406.csv")
    default_output = os.path.join(script_dir, "..", "output", "figures", "fig_country.pdf")

    parser.add_argument("--input", default=default_input, help="Input CSV path")
    parser.add_argument("--output", default=default_output, help="Output PDF path")
    args = parser.parse_args()

    # ---- Load data ----
    df_fig1 = pd.read_csv(args.input)
    print(f"Loaded {len(df_fig1)} companies from {args.input}")

    # ---- Country configuration ----
    countries = ["IND", "USA", "DEU", "GBR", "FRA", "JPN"]
    country_name = {
        "IND": "India",
        "USA": "United States",
        "DEU": "Germany",
        "GBR": "United\nKingdom",
        "FRA": "France",
        "JPN": "Japan",
        "Other": "Other",
    }

    # Classify: keep specified countries, rest as "Other"
    df_fig1["ISO_COUNTRY"] = df_fig1["ISO_COUNTRY"].apply(
        lambda x: x if x in countries else "Other"
    )

    # Average emission for ranking
    df_fig1["mean_emission"] = (df_fig1["g_S3_CDP_c"] + df_fig1["g_S3_est"]) / 2

    # Sort countries by company count (descending), "Other" last
    country_counts = df_fig1["ISO_COUNTRY"].value_counts()
    sorted_countries = [c for c in country_counts.index if c != "Other"]
    sorted_countries = sorted(sorted_countries, key=lambda c: country_counts[c], reverse=True)
    sorted_countries.append("Other")

    df_fig1["ISO_COUNTRY"] = pd.Categorical(
        df_fig1["ISO_COUNTRY"], categories=sorted_countries, ordered=True
    )
    df_fig1 = df_fig1.sort_values(
        by=["ISO_COUNTRY", "mean_emission"], ascending=[True, False]
    )

    # ---- Compute x positions ----
    spacing_factor = 5
    group_spacing = 20
    x_positions = []
    current_x = 0
    country_blocks = {}

    for country in sorted_countries:
        subset_size = (df_fig1["ISO_COUNTRY"] == country).sum()
        x_positions.extend(range(current_x, current_x + subset_size * spacing_factor, spacing_factor))
        country_blocks[country] = (current_x, current_x + subset_size * spacing_factor)
        current_x += subset_size * spacing_factor + group_spacing

    df_fig1["x_position"] = x_positions

    # ---- Create figure ----
    fig, ax = plt.subplots(figsize=(14, 6), dpi=300)
    ax.set_yscale("log")

    # Alternating background per country block
    for i, country in enumerate(sorted_countries):
        if i % 2 == 0:
            x_start, x_end = country_blocks[country]
            ax.axvspan(x_start, x_end, color="lightgray", alpha=0.2)

    # ---- Scatter + connecting lines ----
    for country in sorted_countries:
        subset = df_fig1[df_fig1["ISO_COUNTRY"] == country]

        # Vertical lines: red if estimated > reported, blue otherwise
        for _, row in subset.iterrows():
            line_color = "red" if row["g_S3_est"] > row["g_S3_CDP_c"] else "blue"
            ax.plot(
                [row["x_position"], row["x_position"]],
                [row["g_S3_CDP_c"], row["g_S3_est"]],
                color=line_color, linestyle="-", linewidth=0.7, alpha=0.7,
            )

        # Estimated values (hollow gray circles)
        ax.scatter(
            subset["x_position"], subset["g_S3_est"],
            facecolors="none", edgecolors="gray", alpha=1.0, s=20, linewidth=0.5,
        )

        # Reported values (solid gray dots)
        ax.scatter(
            subset["x_position"], subset["g_S3_CDP_c"],
            color="gray", alpha=0.8, s=20,
        )

    # ---- Axis formatting ----
    ax.xaxis.set_major_locator(plt.NullLocator())
    ax.spines["bottom"].set_position(("outward", 0))
    ax.spines["left"].set_position(("outward", 0))
    ax.tick_params(axis="y", direction="in")
    ax.yaxis.set_minor_locator(plt.NullLocator())
    ax.yaxis.set_major_locator(plt.LogLocator(base=10.0, subs=(1.0,), numticks=8))
    ax.set_ylim(10 ** (-1), 10 ** 9)

    # Country labels
    country_positions = df_fig1.groupby("ISO_COUNTRY")["x_position"].median()
    for country, pos in country_positions.items():
        if country in country_name:
            ax.text(
                pos, 3 * 10 ** 8, country_name[country],
                ha="center", fontsize=8, fontweight="regular",
            )

    # Labels
    ax.set_xlabel("Company Rank within Country (Ordered by Avg of Reported and EMRIO-Based Emissions)")
    ax.set_ylabel(r"Scope 3 Emissions (ton CO$_2$ eq)")
    ax.set_title("Comparison of Reported vs EMRIO-based Emissions")

    # ---- Save ----
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    plt.savefig(args.output, bbox_inches="tight")
    print(f"Saved to {args.output}")
    plt.close()


if __name__ == "__main__":
    main()
