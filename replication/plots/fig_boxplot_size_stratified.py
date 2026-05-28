#!/usr/bin/env python3
"""
fig_boxplot_size_stratified.py — Size-controlled comparison.

Split companies into SALES quartiles (on the full sample), then within each
bucket compare the three reporting groups' EMRIO intensity. If the gap
shrinks/disappears within buckets, the original difference is size-driven.

Outputs (all under ../output/figures/experiment/):
  - fig_boxplot_size_stratified.pdf   (4 facets, one per SALES quartile)
  - table_size_stratified.csv         (n, median, mean per bucket x group)
  - regression_size_group.txt         (log(ratio) ~ log(SALES) + C(group))

Does not modify fig_boxplot.py or existing outputs.
"""
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import statsmodels.formula.api as smf


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    fig_dir = os.path.join(script_dir, "..", "output", "figures")
    out_dir = os.path.join(fig_dir, "experiment")
    os.makedirs(out_dir, exist_ok=True)

    df_c = pd.read_csv(os.path.join(fig_dir, "df_c_20240406.csv"))
    g_CDP_c = pd.read_csv(os.path.join(fig_dir, "g_CDP_2015.csv"))

    df_c["ratio"] = df_c["S123"] / df_c["SALES"] / 100

    L_REP = "Reporters"
    L_NOA = "In CDP, no S3"
    L_NA = "Not in CDP"
    order = [L_REP, L_NOA, L_NA]

    def classify(row):
        if pd.notna(row["g_S3_CDP_c"]):
            return L_REP
        in_cdp = row["FACTSET_ENTITY_ID"] in set(g_CDP_c["FACTSET_ENTITY_ID"])
        return L_NOA if in_cdp else L_NA

    df_c["Group"] = df_c.apply(classify, axis=1)
    df = df_c.dropna(subset=["SALES", "ratio"]).copy()
    df = df[df["SALES"] > 0]

    # SALES quartiles on the full sample
    df["SizeQ"], edges = pd.qcut(
        df["SALES"], 4, labels=["Q1 (smallest)", "Q2", "Q3", "Q4 (largest)"],
        retbins=True,
    )
    print("SALES quartile edges:", [f"{e:.1f}" for e in edges])

    # -------- Summary table --------
    summary = (
        df.groupby(["SizeQ", "Group"], observed=True)["ratio"]
          .agg(n="count", median="median", mean="mean")
          .reset_index()
    )
    overall = (
        df.groupby("Group", observed=True)["ratio"]
          .agg(n="count", median="median", mean="mean")
          .reset_index()
          .assign(SizeQ="ALL")
    )
    summary_out = pd.concat([overall[summary.columns], summary], ignore_index=True)
    table_path = os.path.join(out_dir, "table_size_stratified.csv")
    summary_out.to_csv(table_path, index=False)
    print(f"Saved {table_path}")
    print(summary_out.to_string(index=False))

    # -------- Regression --------
    df_reg = df.copy()
    df_reg["log_ratio"] = np.log(df_reg["ratio"].clip(lower=1e-6))
    df_reg["log_SALES"] = np.log(df_reg["SALES"])
    df_reg["Group"] = pd.Categorical(df_reg["Group"],
                                     categories=[L_NA, L_NOA, L_REP])

    m1 = smf.ols("log_ratio ~ C(Group)", data=df_reg).fit()
    m2 = smf.ols("log_ratio ~ C(Group) + log_SALES", data=df_reg).fit()

    reg_path = os.path.join(out_dir, "regression_size_group.txt")
    with open(reg_path, "w") as f:
        f.write("=== Model 1: log(ratio) ~ Group ===\n")
        f.write(str(m1.summary()) + "\n\n")
        f.write("=== Model 2: log(ratio) ~ Group + log(SALES) ===\n")
        f.write(str(m2.summary()) + "\n")
    print(f"Saved {reg_path}")
    print("\nGroup coefficients (baseline = Not in CDP):")
    for name, m in [("no size control", m1), ("with log(SALES)", m2)]:
        rep = m.params.get("C(Group)[T.Reporters]", np.nan)
        noa = m.params.get("C(Group)[T.In CDP, no S3]", np.nan)
        print(f"  {name:20s}: Reporters={rep:+.3f}, InCDP_noS3={noa:+.3f}")

    # -------- Plot: 4 facets, one per quartile --------
    plt.rcParams["font.family"] = "sans-serif"
    color_dark = "#294670"

    quartiles = ["Q1 (smallest)", "Q2", "Q3", "Q4 (largest)"]
    fig, axes2d = plt.subplots(2, 2, figsize=(11, 11), sharey=True)
    axes = axes2d.flatten()
    for ax, q in zip(axes, quartiles):
        sub = df[df["SizeQ"] == q]
        counts = sub.groupby("Group", observed=True).size().to_dict()
        tick_labels = [f"{g}\n(n={counts.get(g, 0)})" for g in order]

        sns.stripplot(
            x="Group", y="ratio", data=sub, order=order,
            size=4.0, color=color_dark, alpha=0.5, jitter=0.19, ax=ax,
        )
        sns.boxplot(
            x="Group", y="ratio", data=sub, order=order,
            color="#D7E1EE", fliersize=0,
            medianprops=dict(linewidth=1.5),
            showmeans=True,
            meanprops={"marker": "o", "markerfacecolor": "white",
                       "markeredgecolor": "grey", "markersize": 7},
            width=0.5, boxprops={"linewidth": 1.5}, ax=ax,
        )
        ax.set_title("")
        ax.set_xticklabels(tick_labels, fontsize=13)
        ax.tick_params(axis="y", labelsize=13)
        ax.grid(False)
        ax.set_ylabel("")

    for ax in axes:
        ax.set_xlabel("")
    axes[0].set_ylim(0, 25)
    axes[0].set_yticks(np.arange(0, 26, 5))

    for ax, q in zip(axes, quartiles):
        ax.set_xlabel(q, fontsize=14, labelpad=12)

    plt.tight_layout(w_pad=4.0, h_pad=5.0, rect=[0.04, 0, 1, 1])

    fig.supylabel(
        r"EMRIO Scope 1-3 Emission Intensity (ton CO$_2$e/10k USD)",
        fontsize=15, x=0.01,
    )
    pdf_path = os.path.join(out_dir, "fig_boxplot_size_stratified.pdf")
    jpg_path = os.path.join(out_dir, "fig_boxplot_size_stratified.jpg")
    plt.savefig(pdf_path, bbox_inches="tight")
    plt.savefig(jpg_path, bbox_inches="tight", dpi=200)
    plt.close()
    print(f"Saved {pdf_path}")
    print(f"Saved {jpg_path}")


if __name__ == "__main__":
    main()
