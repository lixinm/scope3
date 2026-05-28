#!/usr/bin/env python3
"""
fig_triangle_all.py — 5x2 grid of per-sector ternary plots (Scope 1/2/3).

Original: scripts/GHG_scope_analyis/fig_triangle_python_single.ipynb
Output reference: output/figs/fig_triangle_all.pdf

Each subplot shows one SIC sector. Filled markers are non-reporters; open
markers are CDP reporters (FACTSET_ENTITY_IDs present in df_fig1_propername.csv).

Usage:
    python fig_triangle_all.py [--input INPUT_CSV] [--propername PROPERNAME_CSV] [--output OUTPUT_PDF]
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


def insert_newlines(label, char_limit=27):
    words = label.split()
    new_label = ""
    current_line = ""
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


POINTS = np.array([[0, 0], [1, 0], [0.5, np.sqrt(3) / 2]])


def draw_grid_lines(ax):
    num_divisions = 10
    num_k = num_divisions * 10
    for i in range(10, num_k, 10):
        left_x = i / num_k / 2
        left_y = (np.sqrt(3) / 2) * (i / num_k)
        offset_x = -0.01 * np.cos(np.deg2rad(60))
        ax.text(left_x + offset_x, left_y, str(i) + "%", ha="right", va="center", fontsize=6)
        right_x = 0.5 + i / num_k / 2
        right_y = (np.sqrt(3) / 2) * (1 - i / num_k)
        offset_x2 = 0.02 * np.cos(np.deg2rad(120))
        offset_y2 = 0.01 * np.sin(np.deg2rad(120))
        ax.text(right_x - offset_x2, right_y - offset_y2, str(i) + "%", ha="left", va="center", fontsize=6)
    for i in range(num_k - 10, 0, -10):
        ax.text(i / num_k, 0.002, str(num_k - i) + "%", ha="center", va="top", fontsize=6, rotation=45)
    for i in range(num_divisions):
        for j in range(num_divisions - i):
            ax.plot(
                [j / num_divisions + i / num_divisions / 2, (j + 1) / num_divisions + i / num_divisions / 2],
                [(np.sqrt(3) / 2) * i / num_divisions, (np.sqrt(3) / 2) * i / num_divisions],
                color="grey", linestyle="dotted", linewidth=0.5, alpha=0.7,
            )
            if i != num_divisions - 1:
                ax.plot(
                    [(j + i / 2) / num_divisions, (j + i / 2 + 0.5) / num_divisions],
                    [(np.sqrt(3) / 2) * i / num_divisions, (np.sqrt(3) / 2) * (i + 1) / num_divisions],
                    color="grey", linestyle="dotted", linewidth=0.5, alpha=0.7,
                )
            if j != num_divisions - i - 1:
                ax.plot(
                    [(j + i / 2 + 1) / num_divisions, (j + i / 2 + 0.5) / num_divisions],
                    [(np.sqrt(3) / 2) * i / num_divisions, (np.sqrt(3) / 2) * (i + 1) / num_divisions],
                    color="grey", linestyle="dotted", linewidth=0.5, alpha=0.7,
                )


def create_base_plot(ax):
    ax.set_aspect("equal")
    for i in range(3):
        ax.plot(
            [POINTS[i][0], POINTS[(i + 1) % 3][0]],
            [POINTS[i][1], POINTS[(i + 1) % 3][1]], "k-",
        )
    draw_grid_lines(ax)
    ax.set_xlim(-0.1, 1.1)
    ax.set_ylim(-0.1, np.sqrt(3) / 2 + 0.1)
    ax.axis("off")
    ax.add_patch(plt.Polygon(POINTS, closed=True, fill=True, facecolor="lightgrey", edgecolor="none", alpha=0.2))


def plot_data_points(ax, df, desc, color_map, propername_ids):
    category_data = df[df["SIC_1_desc"] == desc]
    for _, row in category_data.iterrows():
        total = row["g_S1"] + row["g_S2"] + row["g_S3"]
        if total <= 0:
            continue
        weights = [row["g_S1"] / total, row["g_S2"] / total, row["g_S3"] / total]
        coord = np.dot(weights, POINTS)
        if row["FACTSET_ENTITY_ID"] in propername_ids:
            facecolor = "none"
            edgecolor = color_map[desc]
        else:
            facecolor = color_map[desc]
            edgecolor = "none"
        ax.scatter(coord[0], coord[1], edgecolor=edgecolor, s=8, alpha=0.8, marker="o", facecolors=facecolor)


def add_annotations(ax):
    ax.text(POINTS[0][0], POINTS[0][1], "Scope 1 ", ha="right", fontsize=8)
    ax.text(POINTS[1][0], POINTS[1][1], " Scope 2 ", ha="left", fontsize=8)
    ax.text(POINTS[2][0], POINTS[2][1] + 0.013, "Scope 3 ", va="bottom", ha="center", fontsize=8)


def add_legend(ax, title, color_map):
    formatted_title = insert_newlines(title, char_limit=27)
    legend_elements = [
        Line2D([0], [0], marker="o", color="w", markerfacecolor=color_map[title], markersize=9,
               label="non-reporter", linestyle="None"),
        Line2D([0], [0], marker="o", color=color_map[title], markerfacecolor="none", markersize=7,
               label="CDP reporter", linestyle="None"),
    ]
    ax.legend(handles=legend_elements, title=formatted_title, bbox_to_anchor=(0.72, 0.98),
              loc="upper left", edgecolor="gray", fontsize=7, prop=FONT, title_fontsize=7)
    plt.setp(ax.get_legend().get_title(), **FONT)


def main():
    parser = argparse.ArgumentParser(description="Generate 5x2 grid of ternary plots")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_input = os.path.join(script_dir, "..", "output", "figures", "df_p_SIC_S123.csv")
    default_propername = os.path.join(script_dir, "..", "output", "figures", "df_fig1_propername.csv")
    default_output = os.path.join(script_dir, "..", "output", "figures", "fig_triangle_all.pdf")

    parser.add_argument("--input", default=default_input, help="Input CSV path (df_p_SIC_S123.csv)")
    parser.add_argument("--propername", default=default_propername, help="CDP reporter ID CSV (df_fig1_propername.csv)")
    parser.add_argument("--output", default=default_output, help="Output PDF path")
    args = parser.parse_args()

    p_SIC = pd.read_csv(args.input)
    df_propername = pd.read_csv(args.propername)
    print(f"Loaded {len(p_SIC)} segments from {args.input}")
    print(f"Loaded {len(df_propername)} CDP reporter IDs from {args.propername}")

    df = prepare_dataframe(p_SIC, DESIRED_ORDER)
    color_map = create_color_map(df["SIC_1_desc"].unique())
    propername_ids = set(df_propername["FACTSET_ENTITY_ID"].unique())

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    pdf_pages = PdfPages(args.output)
    fig, axs = plt.subplots(5, 2, figsize=(8, 15), dpi=300)
    fig.tight_layout(h_pad=0.05, w_pad=0.01)

    for idx, desc in enumerate(df["SIC_1_desc"].unique()):
        ax = axs[idx // 2, idx % 2]
        create_base_plot(ax)
        plot_data_points(ax, df, desc, color_map, propername_ids)
        add_annotations(ax)
        add_legend(ax, desc, color_map)

    pdf_pages.savefig(fig, dpi=300)
    pdf_pages.close()
    plt.close(fig)
    print(f"Saved to {args.output}")


if __name__ == "__main__":
    main()
