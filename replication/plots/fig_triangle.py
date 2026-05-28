#!/usr/bin/env python3
"""
fig_triangle.py — Ternary plot of Scope 1/2/3 proportions by SIC sector.

Original: scripts/GHG_scope_analyis/fig_triangle_python.ipynb
Paper reference: Figure 2

Usage:
    python fig_triangle.py [--input INPUT_CSV] [--output OUTPUT_PDF]

Defaults:
    --input  ../output/figures/df_p_SIC_S123.csv
    --output ../output/figures/fig_triangle.pdf
"""
import argparse
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from mpl_toolkits.axes_grid1.inset_locator import inset_axes


def insert_newlines(label, char_limit=27):
    """Wrap long labels for the legend."""
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


def main():
    parser = argparse.ArgumentParser(description="Generate ternary plot")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_input = os.path.join(script_dir, "..", "output", "figures", "df_p_SIC_S123.csv")
    default_output = os.path.join(script_dir, "..", "output", "figures", "fig_triangle.pdf")

    parser.add_argument("--input", default=default_input, help="Input CSV path")
    parser.add_argument("--output", default=default_output, help="Output PDF path")
    args = parser.parse_args()

    # ---- Load data ----
    p_SIC = pd.read_csv(args.input)
    print(f"Loaded {len(p_SIC)} segments from {args.input}")

    FONT = {"weight": "normal", "size": 7, "family": "Arial"}

    df = p_SIC[["g_S1", "g_S2", "g_S3", "SIC_1_desc"]]

    # ---- SIC sector ordering ----
    desired_order = [
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
    df = df[df["SIC_1_desc"].isin(desired_order)]
    df["SIC_1_desc"] = pd.Categorical(df["SIC_1_desc"], categories=desired_order, ordered=True)
    df = df.sort_values("SIC_1_desc")
    unique_desc = df["SIC_1_desc"].unique()

    # ---- Color mapping (reordered tab10) ----
    new_order_indices = [1, 3, 2, 0, 4, 5, 6, 7, 8, 9]
    tab10_colors = plt.get_cmap("tab10").colors
    new_order = [tab10_colors[i] for i in new_order_indices]
    color_map = dict(zip(unique_desc, new_order))

    # ---- Triangle vertices ----
    points = np.array([[0, 0], [1, 0], [0.5, np.sqrt(3) / 2]])

    # ---- Create figure ----
    fig, ax = plt.subplots(figsize=(8, 6))
    ax.set_aspect("equal")

    # ---- Scatter points ----
    for desc in unique_desc:
        category_data = df[df["SIC_1_desc"] == desc]
        tri_coords = []
        for _, row in category_data.iterrows():
            total = row["g_S1"] + row["g_S2"] + row["g_S3"]
            weights = [row["g_S1"] / total, row["g_S2"] / total, row["g_S3"] / total]
            coord = np.dot(weights, points)
            tri_coords.append(coord)
        tri_coords = np.array(tri_coords)
        ax.scatter(
            tri_coords[:, 0], tri_coords[:, 1],
            color=color_map[desc], edgecolor="none", s=8, label=desc, alpha=0.8,
        )

    # ---- Triangle edges ----
    for i in range(3):
        ax.plot(
            [points[i][0], points[(i + 1) % 3][0]],
            [points[i][1], points[(i + 1) % 3][1]], "k-",
        )

    # ---- Tick labels ----
    num_divisions = 10
    num_k = num_divisions * 10
    for i in range(10, num_k, 10):
        left_x = i / num_k / 2
        left_y = (np.sqrt(3) / 2) * (i / num_k)
        offset_x = -0.01 * np.cos(np.deg2rad(60))
        ax.text(left_x + offset_x, left_y, str(i) + "%", ha="right", va="center", fontsize=6)

    for i in range(10, num_k, 10):
        right_x = 0.5 + i / num_k / 2
        right_y = (np.sqrt(3) / 2) * (1 - i / num_k)
        offset_x = 0.02 * np.cos(np.deg2rad(120))
        offset_y = 0.01 * np.sin(np.deg2rad(120))
        ax.text(right_x - offset_x, right_y - offset_y, str(i) + "%", ha="left", va="center", fontsize=6)

    for i in range(num_k - 10, 0, -10):
        ax.text(i / num_k, +0.002, str(num_k - i) + "%", ha="center", va="top", fontsize=6, rotation=45)

    # ---- Grid lines (coarse) ----
    num_divisions = 5
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
                    [np.sqrt(3) / 2 * i / num_divisions, np.sqrt(3) / 2 * (i + 1) / num_divisions],
                    color="grey", linestyle="dotted", linewidth=0.5, alpha=0.7,
                )
            if j != num_divisions - i - 1:
                ax.plot(
                    [(j + i / 2 + 1) / num_divisions, (j + i / 2 + 0.5) / num_divisions],
                    [np.sqrt(3) / 2 * i / num_divisions, np.sqrt(3) / 2 * (i + 1) / num_divisions],
                    color="grey", linestyle="dotted", linewidth=0.5, alpha=0.7,
                )

    # ---- Grid lines (fine) ----
    num_divisions = 10
    for i in range(num_divisions):
        for j in range(num_divisions - i):
            ax.plot(
                [j / num_divisions + i / num_divisions / 2, (j + 1) / num_divisions + i / num_divisions / 2],
                [(np.sqrt(3) / 2) * i / num_divisions, (np.sqrt(3) / 2) * i / num_divisions],
                color="grey", linestyle="-.", linewidth=0.5, alpha=0.5,
            )
            if i != num_divisions - 1:
                ax.plot(
                    [(j + i / 2) / num_divisions, (j + i / 2 + 0.5) / num_divisions],
                    [np.sqrt(3) / 2 * i / num_divisions, np.sqrt(3) / 2 * (i + 1) / num_divisions],
                    color="grey", linestyle="-.", linewidth=0.5, alpha=0.5,
                )
            if j != num_divisions - i - 1:
                ax.plot(
                    [(j + i / 2 + 1) / num_divisions, (j + i / 2 + 0.5) / num_divisions],
                    [np.sqrt(3) / 2 * i / num_divisions, np.sqrt(3) / 2 * (i + 1) / num_divisions],
                    color="grey", linestyle="-.", linewidth=0.5, alpha=0.5,
                )

    # ---- Styling ----
    ax.set_xlim(-0.1, 1.1)
    ax.set_ylim(-0.1, np.sqrt(3) / 2 + 0.1)
    ax.axis("off")

    triangle_bg = plt.Polygon(points, closed=True, fill=True, facecolor="lightgrey", edgecolor="none", alpha=0.2)
    ax.add_patch(triangle_bg)

    ax.text(points[0][0], points[0][1], "Scope 1 ", ha="right", fontsize=8)
    ax.text(points[1][0], points[1][1], " Scope 2 ", ha="left", fontsize=8)
    ax.text(points[2][0], points[2][1] + 0.013, "Scope 3 ", va="bottom", ha="center", fontsize=8)

    # ---- Inset zoom panel ----
    x1, x2, y1, y2 = 0.386, 0.61, 0.68, 0.87
    axins = ax.inset_axes([-0.34, 0.46, 0.6, 0.58])
    axins.set_xlim(x1, x2)
    axins.set_ylim(y1, y2)
    axins.set_xticklabels([])
    axins.set_yticklabels([])
    axins.set_xticks([])
    axins.set_yticks([])

    for desc in unique_desc:
        category_data = df[df["SIC_1_desc"] == desc]
        tri_coords = []
        for _, row in category_data.iterrows():
            total = row["g_S1"] + row["g_S2"] + row["g_S3"]
            weights = [row["g_S1"] / total, row["g_S2"] / total, row["g_S3"] / total]
            coord = np.dot(weights, points)
            tri_coords.append(coord)
        tri_coords = np.array(tri_coords)
        mask = (tri_coords[:, 0] >= x1) & (tri_coords[:, 0] <= x2) & (tri_coords[:, 1] >= y1) & (tri_coords[:, 1] <= y2)
        axins.scatter(tri_coords[mask, 0], tri_coords[mask, 1], color=color_map[desc], edgecolor="none", s=9, alpha=0.8)

    for i in range(3):
        axins.plot([points[i][0], points[(i + 1) % 3][0]], [points[i][1], points[(i + 1) % 3][1]], "k-")

    # Inset tick labels
    num_divisions = 10
    for i in range(8, 10):
        left_x = i / num_divisions / 2
        left_y = (np.sqrt(3) / 2) * (i / num_divisions)
        if x1 <= left_x <= x2 and y1 <= left_y <= y2:
            offset_x = 0.005 * np.cos(np.deg2rad(60))
            offset_y = 0.005 * np.sin(np.deg2rad(60))
            axins.text(left_x - offset_x, left_y + offset_y, str(int(i * 100 / num_divisions)) + "%", ha="right", va="center", fontsize=6)

    # Inset grid
    for i in range(num_divisions):
        for j in range(num_divisions - i):
            axins.plot(
                [j / num_divisions + i / num_divisions / 2, (j + 1) / num_divisions + i / num_divisions / 2],
                [(np.sqrt(3) / 2) * i / num_divisions, (np.sqrt(3) / 2) * i / num_divisions],
                color="grey", linestyle="-.", linewidth=0.5, alpha=0.5,
            )
            if i != num_divisions - 1:
                axins.plot(
                    [(j + i / 2) / num_divisions, (j + i / 2 + 0.5) / num_divisions],
                    [np.sqrt(3) / 2 * i / num_divisions, np.sqrt(3) / 2 * (i + 1) / num_divisions],
                    color="grey", linestyle="-.", linewidth=0.5, alpha=0.5,
                )
            if j != num_divisions - i - 1:
                axins.plot(
                    [(j + i / 2 + 1) / num_divisions, (j + i / 2 + 0.5) / num_divisions],
                    [np.sqrt(3) / 2 * i / num_divisions, np.sqrt(3) / 2 * (i + 1) / num_divisions],
                    color="grey", linestyle="-.", linewidth=0.5, alpha=0.5,
                )

    triangle_bg2 = plt.Polygon(points, closed=True, fill=True, facecolor="lightgrey", edgecolor="none", alpha=0.2)
    axins.add_patch(triangle_bg2)
    for spine in axins.spines.values():
        spine.set_edgecolor("grey")
    ax.indicate_inset_zoom(axins, edgecolor="grey")
    axins.set_facecolor("none")

    # ---- Legend ----
    updated_labels = [insert_newlines(label) for label in unique_desc]
    plt.grid(False)
    plt.legend(labels=updated_labels, bbox_to_anchor=(0.72, 0.98), loc="upper left", edgecolor="gray", fontsize=9, prop=FONT)

    # ---- Save ----
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    plt.savefig(args.output, bbox_inches="tight")
    print(f"Saved to {args.output}")
    plt.close()


if __name__ == "__main__":
    main()
