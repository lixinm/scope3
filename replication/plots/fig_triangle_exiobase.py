#!/usr/bin/env python3
"""
fig_triangle_exiobase.py — Ternary plot (S1/S2/S3 proportions) with EXIOBASE
2015 benchmark markers for the 10 SIC 1-digit categories.

Overlays on top of the firm-level scatter (same data as fig_triangle):
  - for each SIC 1-digit category, aggregate all matched EXIOBASE products
    across all 49 regions, output-weighted, compute global S1/S2/S3 shares.

Does NOT modify fig_triangle.py or fig_triangle.pdf. Writes a new PDF in
../output/figures/experiment/.

Scope definitions used on the EXIOBASE side:
  Scope 1 = direct GHG of the sector (kg CO2e)
  Scope 2 = upstream emissions embedded in purchased electricity + heat/steam
            (single-layer A contribution from these rows)
  Scope 3 = total cradle-to-gate (S @ L @ diag(x)) - S1 - S2

GHG: AR5 GWP100 on CO2 (fossil), CH4 x 28, N2O x 265. Biogenic CO2 excluded.
EXIOBASE dataset: v3.9.6 pxp 2015 (product-by-product; ixi not available).
"""
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib as mpl

DATA = os.environ.get("SCOPE3_EXIOBASE_PATH", "./data/IOT_2015_pxp")
FIG = os.environ.get("SCOPE3_FIG_PATH", "./replication/output/figures")
OUT = os.path.join(FIG, "experiment")

GWP = {"CO2": 1.0, "CH4": 28.0, "N2O": 265.0}


# ---------------------------------------------------------------------------
# SIC 1-digit -> list of EXIOBASE pxp product names
# ---------------------------------------------------------------------------
SIC_MAP = {
    "Agriculture, Forestry and Fishing": [
        "Paddy rice", "Wheat", "Cereal grains nec", "Vegetables, fruit, nuts",
        "Oil seeds", "Sugar cane, sugar beet", "Plant-based fibers",
        "Crops nec", "Cattle", "Pigs", "Poultry", "Meat animals nec",
        "Animal products nec", "Raw milk", "Wool, silk-worm cocoons",
        "Products of forestry, logging and related services (02)",
        "Fish and other fishing products; services incidental of fishing (05)",
        "Manure (biogas treatment)", "Manure (conventional treatment)",
    ],
    "Mining": [
        "Anthracite", "Coking Coal", "Other Bituminous Coal",
        "Sub-Bituminous Coal", "Lignite/Brown Coal", "Peat",
        "Crude petroleum and services related to crude oil extraction, excluding surveying",
        "Natural gas and services related to natural gas extraction, excluding surveying",
        "Uranium and thorium ores (12)",
        "Iron ores", "Copper ores and concentrates",
        "Nickel ores and concentrates", "Aluminium ores and concentrates",
        "Precious metal ores and concentrates",
        "Lead, zinc and tin ores and concentrates",
        "Other non-ferrous metal ores and concentrates",
        "Stone", "Sand and clay",
        "Chemical and fertilizer minerals, salt and other mining and quarrying products n.e.c.",
    ],
    "Construction": [
        "Construction work (45)",
    ],
    "Manufacturing": [
        # Food & beverages & tobacco
        "Processed rice", "Products of meat cattle", "Products of meat pigs",
        "Products of meat poultry", "Meat products nec", "Fish products",
        "products of Vegetable oils and fats", "Dairy products", "Sugar",
        "Food products nec", "Beverages", "Tobacco products (16)",
        # Textiles, apparel, leather, wood, paper, print
        "Textiles (17)", "Wearing apparel; furs (18)",
        "Leather and leather products (19)",
        "Wood and products of wood and cork (except furniture); articles of straw and plaiting materials (20)",
        "Pulp", "Paper and paper products", "Printed matter and recorded media (22)",
        # Refinery & fuels
        "Coke Oven Coke", "Coke oven gas", "Coal Tar", "Gas Coke", "Gas Works Gas",
        "Blast Furnace Gas", "Oxygen Steel Furnace Gas",
        "Motor Gasoline", "Aviation Gasoline", "Gasoline Type Jet Fuel",
        "Kerosene Type Jet Fuel", "Kerosene", "Gas/Diesel Oil", "Heavy Fuel Oil",
        "Liquefied Petroleum Gases (LPG)", "Naphtha", "Lubricants", "Bitumen",
        "Paraffin Waxes", "Petroleum Coke", "Refinery Feedstocks",
        "Refinery Gas", "White Spirit & SBP", "Additives/Blending Components",
        "Non-specified Petroleum Products", "Other Hydrocarbons",
        "Ethane", "Natural Gas Liquids",
        "Biodiesels", "Biogasoline", "Biogas", "Other Liquid Biofuels",
        "Charcoal", "BKB/Peat Briquettes", "Patent Fuel",
        # Chemicals, plastics, rubber, nuclear fuel
        "N-fertiliser", "P- and other fertiliser", "Chemicals nec",
        "Plastics, basic", "Rubber and plastic products (25)", "Nuclear fuel",
        # Non-metallic mineral products
        "Glass and glass products",
        "Bricks, tiles and construction products, in baked clay",
        "Cement, lime and plaster", "Ceramic goods",
        "Other non-metallic mineral products",
        # Basic and fabricated metals
        "Basic iron and steel and of ferro-alloys and first products thereof",
        "Aluminium and aluminium products", "Precious metals",
        "Lead, zinc and tin and products thereof", "Copper products",
        "Other non-ferrous metal products",
        "Fabricated metal products, except machinery and equipment (28)",
        "Foundry work services",
        # Machinery & equipment, electronics, instruments
        "Machinery and equipment n.e.c. (29)",
        "Office machinery and computers (30)",
        "Electrical machinery and apparatus n.e.c. (31)",
        "Radio, television and communication equipment and apparatus (32)",
        "Medical, precision and optical instruments, watches and clocks (33)",
        # Transport equipment
        "Motor vehicles, trailers and semi-trailers (34)",
        "Other transport equipment (35)",
        # Furniture + other
        "Furniture; other manufactured goods n.e.c. (36)",
        # Recycling/secondary (manufacturing SIC 37)
        "Secondary aluminium for treatment, Re-processing of secondary aluminium into new aluminium",
        "Secondary construction material for treatment, Re-processing of secondary construction material into aggregates",
        "Secondary copper for treatment, Re-processing of secondary copper into new copper",
        "Secondary glass for treatment, Re-processing of secondary glass into new glass",
        "Secondary lead for treatment, Re-processing of secondary lead into new lead",
        "Secondary other non-ferrous metals for treatment, Re-processing of secondary other non-ferrous metals into new other non-ferrous metals",
        "Secondary paper for treatment, Re-processing of secondary paper into new pulp",
        "Secondary plastic for treatment, Re-processing of secondary plastic into new plastic",
        "Secondary preciuos metals for treatment, Re-processing of secondary preciuos metals into new preciuos metals",
        "Secondary steel for treatment, Re-processing of secondary steel into new steel",
        "Wood material for treatment, Re-processing of secondary wood material into new wood material",
        "Secondary raw materials",
        "Ash for treatment, Re-processing of ash into clinker",
    ],
    "Transportation, Communications, Electric, Gas and Sanitary service": [
        # Electricity
        "Electricity by coal", "Electricity by gas", "Electricity by nuclear",
        "Electricity by hydro", "Electricity by wind",
        "Electricity by petroleum and other oil derivatives",
        "Electricity by biomass and waste",
        "Electricity by solar photovoltaic", "Electricity by solar thermal",
        "Electricity by tide, wave, ocean", "Electricity by Geothermal",
        "Electricity nec",
        "Transmission services of electricity",
        "Distribution and trade services of electricity",
        # Gas distribution, steam, water
        "Distribution services of gaseous fuels through mains",
        "Steam and hot water supply services",
        "Collected and purified water, distribution services of water (41)",
        # Transportation
        "Railway transportation services", "Other land transportation services",
        "Sea and coastal water transportation services",
        "Inland water transportation services", "Air transport services (62)",
        "Supporting and auxiliary transport services; travel agency services (63)",
        "Transportation services via pipelines",
        # Communications
        "Post and telecommunication services (64)",
        # Sanitary / waste treatment
        "Food waste for treatment: biogasification and land application",
        "Food waste for treatment: composting and land application",
        "Food waste for treatment: incineration",
        "Food waste for treatment: landfill",
        "Food waste for treatment: waste water treatment",
        "Paper and wood waste for treatment: composting and land application",
        "Paper for treatment: landfill",
        "Paper waste for treatment: biogasification and land application",
        "Paper waste for treatment: incineration",
        "Plastic waste for treatment: incineration",
        "Plastic waste for treatment: landfill",
        "Textiles waste for treatment: incineration",
        "Textiles waste for treatment: landfill",
        "Wood waste for treatment: incineration",
        "Wood waste for treatment: landfill",
        "Oil/hazardous waste for treatment: incineration",
        "Inert/metal/hazardous waste for treatment: landfill",
        "Intert/metal waste for treatment: incineration",
        "Other waste for treatment: waste water treatment",
        "Sewage sludge for treatment: biogasification and land application",
        "Bottles for treatment, Recycling of bottles by direct reuse",
    ],
    "Wholesale Trade": [
        "Wholesale trade and commission trade services, except of motor vehicles and motorcycles (51)",
    ],
    "Retail Trade": [
        "Retail  trade services, except of motor vehicles and motorcycles; repair services of personal and household goods (52)",
        "Retail trade services of motor fuel",
        "Sale, maintenance, repair of motor vehicles, motor vehicles parts, motorcycles, motor cycles parts and accessoiries",
        "Hotel and restaurant services (55)",
    ],
    "Finance, Insurance and Real Estate": [
        "Financial intermediation services, except insurance and pension funding services (65)",
        "Insurance and pension funding services, except compulsory social security services (66)",
        "Services auxiliary to financial intermediation (67)",
        "Real estate services (70)",
    ],
    "Services": [
        "Renting services of machinery and equipment without operator and of personal and household goods (71)",
        "Computer and related services (72)",
        "Research and development services (73)",
        "Other business services (74)",
        "Education services (80)",
        "Health and social work services (85)",
        "Membership organisation services n.e.c. (91)",
        "Recreational, cultural and sporting services (92)",
        "Other services (93)",
        "Private households with employed persons (95)",
        "Extra-territorial organizations and bodies",
    ],
    "Public Administration": [
        "Public administration and defence services; compulsory social security services (75)",
    ],
}

ELECTRICITY_LIKE = {
    "Electricity by coal", "Electricity by gas", "Electricity by nuclear",
    "Electricity by hydro", "Electricity by wind",
    "Electricity by petroleum and other oil derivatives",
    "Electricity by biomass and waste",
    "Electricity by solar photovoltaic", "Electricity by solar thermal",
    "Electricity by tide, wave, ocean", "Electricity by Geothermal",
    "Electricity nec",
    "Transmission services of electricity",
    "Distribution and trade services of electricity",
    "Steam and hot water supply services",
}


def load_exiobase():
    xdf = pd.read_csv(os.path.join(DATA, "x.txt"), sep="\t")
    xdf.columns = ["region", "sector", "x"]
    n = len(xdf)

    F = pd.read_csv(os.path.join(DATA, "air_emissions/F.txt"),
                    sep="\t", header=[0, 1], index_col=0)
    assert F.shape[1] == n

    # GHG vector (kg CO2e per (region, sector))
    ghg = np.zeros(n)
    for stressor in F.index:
        s = str(stressor)
        if "bio" in s.lower():
            continue
        if s.startswith("CO2"):
            ghg += F.loc[stressor].values * GWP["CO2"]
        elif s.startswith("CH4"):
            ghg += F.loc[stressor].values * GWP["CH4"]
        elif s.startswith("N2O"):
            ghg += F.loc[stressor].values * GWP["N2O"]

    x = xdf["x"].values.astype(np.float64)
    with np.errstate(divide="ignore", invalid="ignore"):
        S = np.where(x > 0, ghg / x, 0.0)

    print("Loading A.txt ...")
    A = pd.read_csv(os.path.join(DATA, "A.txt"), sep="\t",
                    header=[0, 1], index_col=[0, 1]).values.astype(np.float64)
    assert A.shape == (n, n)

    print("Computing L = (I - A)^-1 ...")
    I = np.eye(n, dtype=np.float64)
    L = np.linalg.solve(I - A, I)

    t = S @ L               # kg/M.EUR total intensity
    total_emis = t * x      # kg CO2e cradle-to-gate per (region, sector)

    # Scope 2: single-layer contribution from electricity/heat rows
    is_elec = np.array([sec in ELECTRICITY_LIKE for sec in xdf["sector"]])
    S_elec = np.where(is_elec, S, 0.0)
    s2_per_output = S_elec @ A      # kg/M.EUR
    s2_abs = s2_per_output * x      # kg CO2e per (region, sector)

    s1_abs = ghg.copy()
    s3_abs = total_emis - s1_abs - s2_abs

    neg = (s3_abs < 0).sum()
    if neg:
        print(f"  NOTE: {neg} (region, sector) cells have negative S3 "
              f"(numerical); clipped to 0.")
        s3_abs = np.clip(s3_abs, 0, None)

    return xdf, s1_abs, s2_abs, s3_abs


def aggregate_by_sic(xdf, s1, s2, s3):
    sec = xdf["sector"].values
    rows = []
    missing = []
    for sic, sec_list in SIC_MAP.items():
        mask = np.isin(sec, sec_list)
        for name in sec_list:
            if (sec == name).sum() == 0:
                missing.append((sic, name))
        a = s1[mask].sum()
        b = s2[mask].sum()
        c = s3[mask].sum()
        tot = a + b + c
        if tot <= 0:
            continue
        rows.append({
            "SIC_1_desc": sic,
            "n_sectors": len(sec_list),
            "S1_kg": a, "S2_kg": b, "S3_kg": c,
            "share_S1": a / tot, "share_S2": b / tot, "share_S3": c / tot,
        })
    if missing:
        print("WARNING: EXIOBASE sector names not found (check spelling):")
        for s, n in missing:
            print(f"  [{s}] {n!r}")
    return pd.DataFrame(rows)


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


def plot_triangle(df_firm, df_bench, out_path):
    """Replicate fig_triangle.py aesthetic and overlay EXIOBASE benchmarks."""
    FONT = {"weight": "normal", "size": 7, "family": "Arial"}

    desired_order = list(SIC_MAP.keys())
    df = df_firm[df_firm["SIC_1_desc"].isin(desired_order)].copy()
    df["SIC_1_desc"] = pd.Categorical(df["SIC_1_desc"],
                                      categories=desired_order, ordered=True)
    df = df.sort_values("SIC_1_desc")
    unique_desc = df["SIC_1_desc"].unique()

    new_order_indices = [1, 3, 2, 0, 4, 5, 6, 7, 8, 9]
    tab10 = plt.get_cmap("tab10").colors
    palette = [tab10[i] for i in new_order_indices]
    color_map = dict(zip(unique_desc, palette))

    points = np.array([[0, 0], [1, 0], [0.5, np.sqrt(3) / 2]])

    def bary(s1, s2, s3):
        tot = s1 + s2 + s3
        w = np.array([s1 / tot, s2 / tot, s3 / tot])
        return w @ points

    fig, ax = plt.subplots(figsize=(8, 6))
    ax.set_aspect("equal")

    # ---- Firm scatter ----
    for desc in unique_desc:
        sub = df[df["SIC_1_desc"] == desc]
        if len(sub) == 0:
            continue
        coords = np.array([bary(r.g_S1, r.g_S2, r.g_S3)
                           for r in sub.itertuples()])
        ax.scatter(coords[:, 0], coords[:, 1],
                   color=color_map[desc], edgecolor="none", s=8,
                   label=desc, alpha=0.8)

    # ---- Triangle edges ----
    for i in range(3):
        ax.plot([points[i][0], points[(i + 1) % 3][0]],
                [points[i][1], points[(i + 1) % 3][1]], "k-")

    # ---- Tick labels (left, right, bottom) ----
    nd = 10
    num_k = nd * 10
    for i in range(10, num_k, 10):
        lx = i / num_k / 2
        ly = (np.sqrt(3) / 2) * (i / num_k)
        ax.text(lx - 0.01 * np.cos(np.deg2rad(60)), ly,
                f"{i}%", ha="right", va="center", fontsize=6)
    for i in range(10, num_k, 10):
        rx = 0.5 + i / num_k / 2
        ry = (np.sqrt(3) / 2) * (1 - i / num_k)
        ax.text(rx - 0.02 * np.cos(np.deg2rad(120)),
                ry - 0.01 * np.sin(np.deg2rad(120)),
                f"{i}%", ha="left", va="center", fontsize=6)
    for i in range(num_k - 10, 0, -10):
        ax.text(i / num_k, 0.002, f"{num_k - i}%",
                ha="center", va="top", fontsize=6, rotation=45)

    # ---- Grid lines (coarse + fine) ----
    for nd_g, ls, alpha in [(5, "dotted", 0.7), (10, "-.", 0.5)]:
        for i in range(nd_g):
            for j in range(nd_g - i):
                ax.plot(
                    [j / nd_g + i / nd_g / 2, (j + 1) / nd_g + i / nd_g / 2],
                    [(np.sqrt(3) / 2) * i / nd_g] * 2,
                    color="grey", linestyle=ls, linewidth=0.5, alpha=alpha,
                )
                if i != nd_g - 1:
                    ax.plot(
                        [(j + i / 2) / nd_g, (j + i / 2 + 0.5) / nd_g],
                        [np.sqrt(3) / 2 * i / nd_g, np.sqrt(3) / 2 * (i + 1) / nd_g],
                        color="grey", linestyle=ls, linewidth=0.5, alpha=alpha,
                    )
                if j != nd_g - i - 1:
                    ax.plot(
                        [(j + i / 2 + 1) / nd_g, (j + i / 2 + 0.5) / nd_g],
                        [np.sqrt(3) / 2 * i / nd_g, np.sqrt(3) / 2 * (i + 1) / nd_g],
                        color="grey", linestyle=ls, linewidth=0.5, alpha=alpha,
                    )

    ax.set_xlim(-0.1, 1.1)
    ax.set_ylim(-0.1, np.sqrt(3) / 2 + 0.1)
    ax.axis("off")

    ax.add_patch(plt.Polygon(points, closed=True, fill=True,
                             facecolor="lightgrey", edgecolor="none", alpha=0.2))

    ax.text(points[0][0], points[0][1], "Scope 1 ", ha="right", fontsize=8)
    ax.text(points[1][0], points[1][1], " Scope 2 ", ha="left", fontsize=8)
    ax.text(points[2][0], points[2][1] + 0.013, "Scope 3 ",
            va="bottom", ha="center", fontsize=8)

    # ---- EXIOBASE benchmark markers (small diamonds) ----
    for _, row in df_bench.iterrows():
        desc = row["SIC_1_desc"]
        if desc not in color_map:
            continue
        c = color_map[desc]
        xy = bary(row["share_S1"], row["share_S2"], row["share_S3"])
        ax.scatter(xy[0], xy[1], marker="D", s=22, facecolor=c,
                   edgecolor="black", linewidth=0.5, zorder=6)

    # ---- Inset zoom panel ----
    x1, x2, y1, y2 = 0.386, 0.61, 0.68, 0.87
    axins = ax.inset_axes([-0.34, 0.46, 0.6, 0.58])
    axins.set_xlim(x1, x2); axins.set_ylim(y1, y2)
    axins.set_xticklabels([]); axins.set_yticklabels([])
    axins.set_xticks([]); axins.set_yticks([])

    for desc in unique_desc:
        sub = df[df["SIC_1_desc"] == desc]
        if len(sub) == 0:
            continue
        coords = np.array([bary(r.g_S1, r.g_S2, r.g_S3)
                           for r in sub.itertuples()])
        mask = ((coords[:, 0] >= x1) & (coords[:, 0] <= x2)
                & (coords[:, 1] >= y1) & (coords[:, 1] <= y2))
        if mask.any():
            axins.scatter(coords[mask, 0], coords[mask, 1],
                          color=color_map[desc], edgecolor="none",
                          s=9, alpha=0.8)

    for i in range(3):
        axins.plot([points[i][0], points[(i + 1) % 3][0]],
                   [points[i][1], points[(i + 1) % 3][1]], "k-")

    for i in range(8, 10):
        lx = i / nd / 2
        ly = (np.sqrt(3) / 2) * (i / nd)
        if x1 <= lx <= x2 and y1 <= ly <= y2:
            axins.text(lx - 0.005 * np.cos(np.deg2rad(60)),
                       ly + 0.005 * np.sin(np.deg2rad(60)),
                       f"{int(i * 100 / nd)}%", ha="right", va="center", fontsize=6)

    for i in range(nd):
        for j in range(nd - i):
            axins.plot(
                [j / nd + i / nd / 2, (j + 1) / nd + i / nd / 2],
                [(np.sqrt(3) / 2) * i / nd] * 2,
                color="grey", linestyle="-.", linewidth=0.5, alpha=0.5,
            )
            if i != nd - 1:
                axins.plot(
                    [(j + i / 2) / nd, (j + i / 2 + 0.5) / nd],
                    [np.sqrt(3) / 2 * i / nd, np.sqrt(3) / 2 * (i + 1) / nd],
                    color="grey", linestyle="-.", linewidth=0.5, alpha=0.5,
                )
            if j != nd - i - 1:
                axins.plot(
                    [(j + i / 2 + 1) / nd, (j + i / 2 + 0.5) / nd],
                    [np.sqrt(3) / 2 * i / nd, np.sqrt(3) / 2 * (i + 1) / nd],
                    color="grey", linestyle="-.", linewidth=0.5, alpha=0.5,
                )

    axins.add_patch(plt.Polygon(points, closed=True, fill=True,
                                facecolor="lightgrey", edgecolor="none", alpha=0.2))

    # EXIOBASE markers in inset
    for _, row in df_bench.iterrows():
        desc = row["SIC_1_desc"]
        if desc not in color_map:
            continue
        c = color_map[desc]
        xy = bary(row["share_S1"], row["share_S2"], row["share_S3"])
        if x1 <= xy[0] <= x2 and y1 <= xy[1] <= y2:
            axins.scatter(xy[0], xy[1], marker="D", s=22, facecolor=c,
                          edgecolor="black", linewidth=0.5, zorder=6)

    for spine in axins.spines.values():
        spine.set_edgecolor("grey")
    ax.indicate_inset_zoom(axins, edgecolor="grey")
    axins.set_facecolor("none")

    # ---- Legend (same style as fig_triangle.py + extra EXIOBASE entry) ----
    from matplotlib.lines import Line2D
    updated_labels = [insert_newlines(label) for label in unique_desc]
    sic_handles = [
        Line2D([0], [0], marker="o", linestyle="",
               markerfacecolor=color_map[d], markeredgecolor="none",
               markersize=7, label=lbl)
        for d, lbl in zip(unique_desc, updated_labels)
    ]
    sic_handles.append(
        Line2D([0], [0], marker="D", linestyle="",
               markerfacecolor="grey", markeredgecolor="black",
               markeredgewidth=0.5, markersize=5, label="EXIOBASE")
    )
    plt.grid(False)
    ax.legend(handles=sic_handles, bbox_to_anchor=(0.72, 0.98),
              loc="upper left", edgecolor="gray", fontsize=9, prop=FONT)

    plt.savefig(out_path, bbox_inches="tight")
    jpg_path = out_path.replace(".pdf", ".jpg")
    plt.savefig(jpg_path, bbox_inches="tight", dpi=200)
    plt.close()
    print(f"Saved {out_path}")
    print(f"Saved {jpg_path}")


def main():
    os.makedirs(OUT, exist_ok=True)

    # Firm-level data (same source as fig_triangle)
    firm = pd.read_csv(os.path.join(FIG, "df_p_SIC_S123.csv"))
    firm = firm[["g_S1", "g_S2", "g_S3", "SIC_1_desc"]].dropna()
    firm = firm[(firm["g_S1"] + firm["g_S2"] + firm["g_S3"]) > 0]
    print(f"Loaded {len(firm)} firm segments")

    # EXIOBASE breakdown — reuse cached CSV if present (heavy computation)
    bench_csv = os.path.join(OUT, "exiobase2015_sic1_s1s2s3_breakdown.csv")
    if os.path.exists(bench_csv):
        print(f"Reusing cached EXIOBASE breakdown: {bench_csv}")
        bench = pd.read_csv(bench_csv)
    else:
        xdf, s1, s2, s3 = load_exiobase()
        bench = aggregate_by_sic(xdf, s1, s2, s3)
        bench.to_csv(bench_csv, index=False)
        print(f"\nSaved {bench_csv}")
    print(bench[["SIC_1_desc", "share_S1", "share_S2", "share_S3"]].to_string(index=False))

    out_pdf = os.path.join(OUT, "fig_triangle_exiobase.pdf")
    plot_triangle(firm, bench, out_pdf)


if __name__ == "__main__":
    main()
