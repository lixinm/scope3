#!/usr/bin/env python3
"""
fig_triangle_all_exiobase.py — 5x2 grid of per-sector ternary plots
(Scope 1/2/3) with the EXIOBASE 2015 sector benchmark overlaid as a diamond
marker in each subplot.

Combines:
  - fig_triangle_all.py (per-sector firm scatter, non-reporter / CDP-reporter)
  - fig_triangle_exiobase.py (EXIOBASE 2015 SIC-1 benchmark point)

Reads the precomputed EXIOBASE benchmark from
    output/figures/experiment/exiobase2015_sic1_s1s2s3_breakdown.csv
(produced by fig_triangle_exiobase.py). If the CSV is missing, this script
will tell you to run fig_triangle_exiobase.py first.

Usage:
    python fig_triangle_all_exiobase.py
"""
import argparse
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.backends.backend_pdf import PdfPages


FONT = {"weight": "normal", "size": 7, "family": "Arial"}

DESIRED_ORDER = [
    "Agriculture, Forestry and Fishing",
    "Mining",
    "Construction",
    "Manufacturing",
    "Transportation, Communications, Electric, Gas and Sanitary service",
    "Wholesale Trade",
    "Retail Trade",
    "Finance, Insurance and Real Estate",
    "Services",
    "Public Administration",
]

POINTS = np.array([[0, 0], [1, 0], [0.5, np.sqrt(3) / 2]])


def insert_newlines(label, char_limit=27):
    words = label.split()
    new_label, current_line = "", ""
    for word in words:
        if len(current_line) + len(word) + 1 > char_limit:
            new_label += current_line.strip() + "\n"
            current_line = word + " "
        else:
            current_line += word + " "
    new_label += current_line.strip()
    return new_label


def prepare_dataframe(df, desired_order):
    df = df[df["SIC_1_desc"].isin(desired_order)].copy()
    df["SIC_1_desc"] = pd.Categorical(df["SIC_1_desc"], categories=desired_order, ordered=True)
    return df.sort_values("SIC_1_desc")


def create_color_map(unique_desc):
    new_order_indices = [1, 3, 2, 0, 4, 5, 6, 7, 8, 9]
    tab10_colors = plt.get_cmap("tab10").colors
    new_order = [tab10_colors[i] for i in new_order_indices]
    return dict(zip(unique_desc, new_order))


def draw_grid_lines(ax):
    nd = 10
    num_k = nd * 10
    for i in range(10, num_k, 10):
        lx = i / num_k / 2
        ly = (np.sqrt(3) / 2) * (i / num_k)
        ax.text(lx - 0.01 * np.cos(np.deg2rad(60)), ly,
                f"{i}%", ha="right", va="center", fontsize=6)
        rx = 0.5 + i / num_k / 2
        ry = (np.sqrt(3) / 2) * (1 - i / num_k)
        ax.text(rx - 0.02 * np.cos(np.deg2rad(120)),
                ry - 0.01 * np.sin(np.deg2rad(120)),
                f"{i}%", ha="left", va="center", fontsize=6)
    for i in range(num_k - 10, 0, -10):
        ax.text(i / num_k, 0.002, f"{num_k - i}%",
                ha="center", va="top", fontsize=6, rotation=45)
    for i in range(nd):
        for j in range(nd - i):
            ax.plot([j / nd + i / nd / 2, (j + 1) / nd + i / nd / 2],
                    [(np.sqrt(3) / 2) * i / nd] * 2,
                    color="grey", linestyle="dotted", linewidth=0.5, alpha=0.7)
            if i != nd - 1:
                ax.plot([(j + i / 2) / nd, (j + i / 2 + 0.5) / nd],
                        [(np.sqrt(3) / 2) * i / nd, (np.sqrt(3) / 2) * (i + 1) / nd],
                        color="grey", linestyle="dotted", linewidth=0.5, alpha=0.7)
            if j != nd - i - 1:
                ax.plot([(j + i / 2 + 1) / nd, (j + i / 2 + 0.5) / nd],
                        [(np.sqrt(3) / 2) * i / nd, (np.sqrt(3) / 2) * (i + 1) / nd],
                        color="grey", linestyle="dotted", linewidth=0.5, alpha=0.7)


def create_base_plot(ax):
    ax.set_aspect("equal")
    for i in range(3):
        ax.plot([POINTS[i][0], POINTS[(i + 1) % 3][0]],
                [POINTS[i][1], POINTS[(i + 1) % 3][1]], "k-")
    draw_grid_lines(ax)
    ax.set_xlim(-0.1, 1.1)
    ax.set_ylim(-0.1, np.sqrt(3) / 2 + 0.1)
    ax.axis("off")
    ax.add_patch(plt.Polygon(POINTS, closed=True, fill=True,
                             facecolor="lightgrey", edgecolor="none", alpha=0.2))


def bary(s1, s2, s3):
    tot = s1 + s2 + s3
    w = np.array([s1 / tot, s2 / tot, s3 / tot])
    return w @ POINTS


def plot_data_points(ax, df, desc, color_map, propername_ids):
    sub = df[df["SIC_1_desc"] == desc]
    for _, row in sub.iterrows():
        tot = row["g_S1"] + row["g_S2"] + row["g_S3"]
        if tot <= 0:
            continue
        coord = bary(row["g_S1"], row["g_S2"], row["g_S3"])
        if row["FACTSET_ENTITY_ID"] in propername_ids:
            facecolor, edgecolor = "none", color_map[desc]
        else:
            facecolor, edgecolor = color_map[desc], "none"
        ax.scatter(coord[0], coord[1], edgecolor=edgecolor, s=8, alpha=0.8,
                   marker="o", facecolors=facecolor)


def plot_exiobase_marker(ax, desc, df_bench, color_map):
    row = df_bench[df_bench["SIC_1_desc"] == desc]
    if row.empty:
        return False
    r = row.iloc[0]
    xy = bary(r["share_S1"], r["share_S2"], r["share_S3"])
    c = color_map[desc]
    ax.scatter(xy[0], xy[1], marker="D", s=22, facecolor=c,
               edgecolor="black", linewidth=0.5, zorder=6)
    return True


def add_annotations(ax):
    ax.text(POINTS[0][0], POINTS[0][1], "Scope 1 ", ha="right", fontsize=8)
    ax.text(POINTS[1][0], POINTS[1][1], " Scope 2 ", ha="left", fontsize=8)
    ax.text(POINTS[2][0], POINTS[2][1] + 0.013, "Scope 3 ",
            va="bottom", ha="center", fontsize=8)


def add_legend(ax, title, color_map, has_bench):
    formatted_title = insert_newlines(title, char_limit=27)
    elems = [
        Line2D([0], [0], marker="o", color="w",
               markerfacecolor=color_map[title], markersize=9,
               label="non-reporter", linestyle="None"),
        Line2D([0], [0], marker="o", color=color_map[title],
               markerfacecolor="none", markersize=7,
               label="CDP reporter", linestyle="None"),
    ]
    if has_bench:
        elems.append(
            Line2D([0], [0], marker="D", color="w",
                   markerfacecolor=color_map[title], markeredgecolor="black",
                   markeredgewidth=0.5, markersize=4,
                   label="EXIOBASE", linestyle="None")
        )
    ax.legend(handles=elems, title=formatted_title,
              bbox_to_anchor=(0.72, 0.98), loc="upper left",
              edgecolor="gray", fontsize=7, prop=FONT, title_fontsize=7)
    plt.setp(ax.get_legend().get_title(), **FONT)


def main():
    parser = argparse.ArgumentParser(
        description="5x2 ternary plots with EXIOBASE benchmark overlay")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    fig_dir = os.path.join(script_dir, "..", "output", "figures")
    parser.add_argument("--input",
                        default=os.path.join(fig_dir, "df_p_SIC_S123.csv"))
    parser.add_argument("--propername",
                        default=os.path.join(fig_dir, "df_fig1_propername.csv"))
    parser.add_argument("--bench",
                        default=os.path.join(fig_dir, "experiment",
                                             "exiobase2015_sic1_s1s2s3_breakdown.csv"))
    parser.add_argument("--output",
                        default=os.path.join(fig_dir, "experiment",
                                             "fig_triangle_all_exiobase.pdf"))
    args = parser.parse_args()

    if not os.path.exists(args.bench):
        raise SystemExit(
            f"Benchmark CSV not found: {args.bench}\n"
            f"Run fig_triangle_exiobase.py first to generate it."
        )

    p_SIC = pd.read_csv(args.input)
    df_propername = pd.read_csv(args.propername)
    df_bench = pd.read_csv(args.bench)
    print(f"Loaded {len(p_SIC)} segments, {len(df_propername)} CDP IDs, "
          f"{len(df_bench)} EXIOBASE benchmarks")

    df = prepare_dataframe(p_SIC, DESIRED_ORDER)
    color_map = create_color_map(df["SIC_1_desc"].unique())
    propername_ids = set(df_propername["FACTSET_ENTITY_ID"].unique())
    bench_descs = set(df_bench["SIC_1_desc"].unique())

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    pdf_pages = PdfPages(args.output)
    fig, axs = plt.subplots(5, 2, figsize=(8, 15), dpi=300)
    fig.tight_layout(h_pad=0.05, w_pad=0.01)

    for idx, desc in enumerate(df["SIC_1_desc"].unique()):
        ax = axs[idx // 2, idx % 2]
        create_base_plot(ax)
        plot_data_points(ax, df, desc, color_map, propername_ids)
        has_bench = plot_exiobase_marker(ax, desc, df_bench, color_map)
        add_annotations(ax)
        add_legend(ax, desc, color_map, has_bench and desc in bench_descs)

    pdf_pages.savefig(fig, dpi=300)
    pdf_pages.close()
    jpg_path = args.output.replace(".pdf", ".jpg")
    fig.savefig(jpg_path, dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved to {args.output}")
    print(f"Saved to {jpg_path}")


if __name__ == "__main__":
    main()
