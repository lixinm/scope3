#!/usr/bin/env python3
"""
fig_sic_vs_exiobase.py — Firm-level EMRIO intensity distributions for 5 SIC
sectors (boxplot + strip) with EXIOBASE 2015 global benchmark overlay.

Reads:
  ../output/figures/df_p_SIC_S123.csv                 (firm/segment level)
  ../output/figures/experiment/exiobase2015_sic_benchmarks.csv  (MRIO avg)

Writes:
  ../output/figures/experiment/fig_sic_vs_exiobase.pdf
"""
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

SCRIPT = os.path.dirname(os.path.abspath(__file__))
FIG = os.path.join(SCRIPT, "..", "output", "figures")
OUT = os.path.join(FIG, "experiment")

TARGETS = [
    ("2821", "Plastic Materials"),
    ("2834", "Pharmaceutical Preparations"),
    ("3711", "Motor Vehicles"),
    ("3714", "Motor Vehicle Parts"),
    ("2844", "Perfumes and Cosmetics"),
]


def main():
    df = pd.read_csv(os.path.join(FIG, "df_p_SIC_S123.csv"))
    bench = pd.read_csv(os.path.join(OUT, "exiobase2015_sic_benchmarks.csv"))
    bench_map = dict(zip(bench["SIC_code"].astype(str),
                         bench["intensity_ton_per_10kUSD"]))
    bench_label_map = dict(zip(bench["SIC_code"].astype(str),
                               bench["EXIOBASE_sector"]))

    df["SIC_CODE"] = df["SIC_CODE"].astype(str)
    df["S123"] = df["g_S1"].fillna(0) + df["g_S2"].fillna(0) + df["g_S3"].fillna(0)
    df["ratio"] = df["S123"] / df["SALES"] / 100

    plt.rcParams["font.family"] = "sans-serif"
    color_dark = "#294670"
    bench_color = "#8C6D4F"

    fig, axes = plt.subplots(1, 5, figsize=(10, 6), sharey=True)
    ymax = 20

    for ax, (sic, name) in zip(axes, TARGETS):
        sub = df[df["SIC_CODE"] == sic].dropna(subset=["ratio"])
        sub = sub[np.isfinite(sub["ratio"])]
        n = len(sub)

        sns.stripplot(x=[""] * n, y=sub["ratio"], ax=ax,
                      size=4.7, color=color_dark, alpha=0.5, jitter=0.19)
        sns.boxplot(x=[""] * n, y=sub["ratio"], ax=ax,
                    color="#D7E1EE", fliersize=0,
                    medianprops=dict(linewidth=1.5),
                    showmeans=True,
                    meanprops={"marker": "o", "markerfacecolor": "white",
                               "markeredgecolor": "grey", "markersize": 8},
                    width=0.3, boxprops={"linewidth": 1.5})

        b = bench_map.get(sic)
        if b is not None:
            y_plot = min(b, ymax - 0.5)
            ax.axhline(y_plot, color=bench_color, linestyle=(0, (5, 3)),
                       linewidth=1.3, alpha=0.85, zorder=4)
            ax.plot(0, y_plot, marker="D", color=bench_color,
                    markersize=9, markeredgecolor="white",
                    markeredgewidth=1.0, zorder=5)

        ax.set_title(f"SIC {sic}\n{name}", fontsize=11)
        ax.set_xlabel("")
        ax.set_ylim(0, ymax)
        ax.set_yticks(np.arange(0, ymax + 1, 5))
        ax.grid(False)

    axes[0].set_ylabel(
        r"EMRIO Scope 1-3 Emission Intensity (ton CO$_2$e/10k USD)",
        fontsize=12,
    )
    for ax in axes[1:]:
        ax.set_ylabel("")

    # Shared legend via proxy
    from matplotlib.lines import Line2D
    proxy = [Line2D([0], [0], marker="D", color=bench_color,
                    linestyle=(0, (5, 3)), linewidth=1.3,
                    markerfacecolor=bench_color, markersize=9,
                    markeredgecolor="white", markeredgewidth=1.0,
                    label="EXIOBASE 2015 global output-weighted benchmark")]
    fig.legend(handles=proxy, loc="lower center", ncol=1, frameon=False,
               bbox_to_anchor=(0.5, -0.02), fontsize=10)

    plt.tight_layout(rect=[0, 0.03, 1, 1])
    out_path = os.path.join(OUT, "fig_sic_vs_exiobase.pdf")
    jpg_path = os.path.join(OUT, "fig_sic_vs_exiobase.jpg")
    plt.savefig(out_path, bbox_inches="tight")
    plt.savefig(jpg_path, bbox_inches="tight", dpi=200)
    plt.close()
    print(f"Saved {out_path}")
    print(f"Saved {jpg_path}")

    # Print summary table
    print("\nSummary:")
    for sic, name in TARGETS:
        sub = df[df["SIC_CODE"] == sic]["ratio"].dropna()
        sub = sub[np.isfinite(sub)]
        print(f"  SIC {sic} ({name}): n={len(sub)}, "
              f"median={sub.median():.2f}, mean={sub.mean():.2f}, "
              f"EXIOBASE={bench_map.get(sic):.2f}")


if __name__ == "__main__":
    main()
