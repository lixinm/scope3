#!/usr/bin/env python3
"""
fig_boxplot_size_check.py — Diagnostic: is the reporter-group intensity
difference confounded by company size (SALES)?

Produces two figures in ../output/figures/experiment/:
  (1) fig_boxplot_sales.pdf   — boxplot of SALES by the same three groups
  (2) fig_boxplot_scatter.pdf — scatter of log10(SALES) vs ratio, colored by group

Does NOT modify fig_boxplot.py or its outputs.
"""
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    fig_dir = os.path.join(script_dir, "..", "output", "figures")
    out_dir = os.path.join(fig_dir, "experiment")
    os.makedirs(out_dir, exist_ok=True)

    df_c = pd.read_csv(os.path.join(fig_dir, "df_c_20240406.csv"))
    g_CDP_c = pd.read_csv(os.path.join(fig_dir, "g_CDP_2015.csv"))

    df_c["ratio"] = df_c["S123"] / df_c["SALES"] / 100

    reporter = df_c[df_c["g_S3_CDP_c"].notna()]
    no_answer = df_c[
        df_c["g_S3_CDP_c"].isna()
        & df_c["FACTSET_ENTITY_ID"].isin(g_CDP_c["FACTSET_ENTITY_ID"])
    ]
    not_in_cdp = df_c[
        df_c["g_S3_CDP_c"].isna()
        & ~df_c["FACTSET_ENTITY_ID"].isin(g_CDP_c["FACTSET_ENTITY_ID"])
    ]

    L_REP = "Scope 3 emission \n reporting companies"
    L_NOA = "Scope 3 emission \n non-reporting companies"
    L_NA = "Non-reporters"
    order = [L_REP, L_NOA, L_NA]

    df_all = pd.concat([
        reporter.assign(Group=L_REP),
        no_answer.assign(Group=L_NOA),
        not_in_cdp.assign(Group=L_NA),
    ])

    print("Group sizes & SALES summary (SALES units as stored in df_c):")
    for name, grp in [("Reporters", reporter),
                      ("In CDP, no S3", no_answer),
                      ("Not in CDP", not_in_cdp)]:
        s = grp["SALES"].dropna()
        print(f"  {name}: n={len(grp)}, median SALES={s.median():.1f}, "
              f"mean={s.mean():.1f}, p25={s.quantile(.25):.1f}, p75={s.quantile(.75):.1f}")

    plt.rcParams["font.family"] = "sans-serif"
    color_dark = "#294670"

    # ---------- (1) Boxplot of SALES by group (log y) ----------
    fig, ax = plt.subplots(figsize=(7, 6))
    sns.stripplot(
        x="Group", y="SALES", data=df_all, order=order,
        size=4.7, color=color_dark, alpha=0.5, jitter=0.19, ax=ax,
    )
    sns.boxplot(
        x="Group", y="SALES", data=df_all, order=order,
        color="#D7E1EE", fliersize=0,
        medianprops=dict(linewidth=1.5),
        showmeans=True,
        meanprops={"marker": "o", "markerfacecolor": "white",
                   "markeredgecolor": "grey", "markersize": 8},
        width=0.5, boxprops={"linewidth": 1.5}, ax=ax,
    )
    ax.set_yscale("log")
    ax.set_xlabel("")
    ax.set_ylabel("SALES (log scale, units as in df_c)", fontsize=12)
    ax.grid(False)
    plt.xticks(fontsize=9)
    plt.tight_layout()
    out1 = os.path.join(out_dir, "fig_boxplot_sales.pdf")
    plt.savefig(out1, bbox_inches="tight")
    plt.close()
    print(f"Saved {out1}")

    # ---------- (3) Scatter: log10(SALES) vs ratio, colored by group ----------
    fig, ax = plt.subplots(figsize=(8, 6))
    palette = {L_REP: "#294670", L_NOA: "#E07B39", L_NA: "#8DB580"}
    df_plot = df_all.dropna(subset=["SALES", "ratio"]).copy()
    df_plot = df_plot[df_plot["SALES"] > 0]
    df_plot["log10_SALES"] = np.log10(df_plot["SALES"])

    for g in order:
        sub = df_plot[df_plot["Group"] == g]
        ax.scatter(sub["log10_SALES"], sub["ratio"],
                   s=14, alpha=0.55, color=palette[g],
                   label=g.replace("\n", "").strip(), edgecolor="none")

    ax.set_xlabel("log10(SALES)", fontsize=12)
    ax.set_ylabel(
        r"EMRIO Scope 1-3 Emission Intensity (ton CO$_2$e/10k USD)",
        fontsize=12,
    )
    ax.set_ylim(0, 20)
    ax.legend(fontsize=9, frameon=False, loc="upper right")
    ax.grid(False)
    plt.tight_layout()
    out2 = os.path.join(out_dir, "fig_boxplot_scatter.pdf")
    plt.savefig(out2, bbox_inches="tight")
    plt.close()
    print(f"Saved {out2}")


if __name__ == "__main__":
    main()
