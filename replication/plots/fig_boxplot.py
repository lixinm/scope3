#!/usr/bin/env python3
"""
fig_boxplot.py — Reporter boxplot: emission intensity by reporting status.

Original: scripts/GHG_scope_analyis/fig_reporter_python.ipynb (Cells 1, 3)
Paper reference: Figure showing EMRIO-based emission intensities grouped by
                 Scope 3 reporting status.

Companies are split into three groups:
  1. Scope 3 reporting companies: have g_S3_CDP_c value (CDP reporters)
  2. Scope 3 non-reporting companies: in CDP database but no Scope 3 report
  3. Non-reporters: not in CDP database at all

Y-axis: ratio = S123 / SALES / 100  (ton CO2e per 10k USD)

Usage:
    python fig_boxplot.py [--input DF_C] [--cdp G_CDP] [--output PDF]

Defaults:
    --input  ../output/figures/df_c_20240406.csv
    --cdp    ../output/figures/g_CDP_2015.csv
    --output ../output/figures/fig_boxplot.pdf
"""
import argparse
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns


def main():
    parser = argparse.ArgumentParser(description="Generate reporter boxplot")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_input = os.path.join(script_dir, "..", "output", "figures", "df_c_20240406.csv")
    default_cdp = os.path.join(script_dir, "..", "output", "figures", "g_CDP_2015.csv")
    default_output = os.path.join(script_dir, "..", "output", "figures", "fig_boxplot.pdf")

    parser.add_argument("--input", default=default_input, help="Input df_c CSV path")
    parser.add_argument("--cdp", default=default_cdp, help="g_CDP reference CSV path")
    parser.add_argument("--output", default=default_output, help="Output PDF path")
    args = parser.parse_args()

    # ---- Load data ----
    df_c = pd.read_csv(args.input)
    g_CDP_c = pd.read_csv(args.cdp)
    print(f"Loaded {len(df_c)} companies from {args.input}")
    print(f"Loaded {len(g_CDP_c)} CDP entries from {args.cdp}")

    # ---- Compute emission intensity (original Cell 1) ----
    # ratio = S123 / SALES / 100 → ton CO2e per 10,000 USD
    df_c["ratio"] = df_c["S123"] / df_c["SALES"] / 100

    # ---- Split into three groups (original Cell 1) ----
    # Group 1: Scope 3 reporters — have g_S3_CDP_c value
    group_reporter = df_c[df_c["g_S3_CDP_c"].notna()]

    # Group 2: In CDP but did NOT report Scope 3
    group_no_answer = df_c[
        (df_c["g_S3_CDP_c"].isna())
        & (df_c["FACTSET_ENTITY_ID"].isin(g_CDP_c["FACTSET_ENTITY_ID"]))
    ]

    # Group 3: Not in CDP at all
    group_NA = df_c[
        (df_c["g_S3_CDP_c"].isna())
        & (~df_c["FACTSET_ENTITY_ID"].isin(g_CDP_c["FACTSET_ENTITY_ID"]))
    ]

    print(f"  Reporters:     {len(group_reporter)}")
    print(f"  In CDP, no S3: {len(group_no_answer)}")
    print(f"  Not in CDP:    {len(group_NA)}")

    # ---- Combine into df_violin with Group labels ----
    df_violin = pd.concat([
        group_reporter.assign(Group="Scope 3 emission \n reporting companies"),
        group_no_answer.assign(Group="Scope 3 emission \n non-reporting companies"),
        group_NA.assign(Group="Non-reporters"),
    ])

    # Print group averages for verification
    for name, grp in [("Reporters", group_reporter),
                       ("Non-reporters (CDP)", group_no_answer),
                       ("Non-reporters (NA)", group_NA)]:
        avg = grp["ratio"].mean() if len(grp) > 0 else float("nan")
        med = grp["ratio"].median() if len(grp) > 0 else float("nan")
        print(f"  {name}: mean={avg:.2f}, median={med:.2f}")

    # ---- Create boxplot (original Cell 3) ----
    plt.rcParams["font.family"] = "sans-serif"
    color_dark = "#294670"

    plt.figure(figsize=(7, 6))

    # Strip plot (individual data points)
    sns.stripplot(
        x="Group", y="ratio", data=df_violin,
        size=4.7, color=color_dark, alpha=0.5, jitter=0.19,
    )

    # Box plot overlay
    ax = sns.boxplot(
        x="Group", y="ratio", data=df_violin,
        color="#D7E1EE", fliersize=0,
        medianprops=dict(linewidth=1.5),
        showmeans=True,
        meanprops={
            "marker": "o",
            "markerfacecolor": "white",
            "markeredgecolor": "grey",
            "markersize": 8,
        },
        width=0.5,
        boxprops={"linewidth": 1.5},
    )

    # Style box edges
    for artist in ax.artists:
        artist.set_edgecolor(color_dark)
        artist.set_linewidth(1.5)

    # Axis labels
    ax.set_xlabel("", fontsize=12)
    ax.set_ylabel(
        r"EMRIO-based Scope 1-3 Emission Intensities (ton CO$_2$e/10k USD)",
        fontsize=12,
    )

    # Y-axis limits and ticks
    ymax = 20
    ax.set_ylim(bottom=0, top=ymax)
    plt.yticks(np.arange(0, ymax + 1, 5))

    plt.xticks(fontsize=9)
    ax.grid(False)

    plt.tight_layout()

    # ---- Save ----
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    plt.savefig(args.output, bbox_inches="tight")
    print(f"Saved to {args.output}")
    plt.close()


if __name__ == "__main__":
    main()
