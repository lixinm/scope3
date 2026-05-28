#!/usr/bin/env python3
"""
exiobase_sector_intensity.py — Global supply-chain GHG intensities from
EXIOBASE 2015 (pxp) for 5 target sectors matching SIC codes in Figure 3.

Dataset: EXIOBASE v3.9.6, product-by-product (pxp), 2015.
         (User requested ixi; only pxp is available locally — flagged.)

Method:
  - GHG in CO2-eq (AR5 GWP100): CO2 (fossil) = 1, CH4 = 28, N2O = 265.
    Biogenic CO2 ("CO2_bio - combustion - air", "CO2 - waste - biogenic - air")
    is excluded per standard GHG protocol practice.
  - Direct intensity vector S = f_GHG / x  (kg CO2e per M.EUR output).
  - Leontief inverse L = (I - A)^-1.
  - Total cradle-to-gate intensity per unit final output: t = S @ L
    (kg CO2e per M.EUR; includes Scope 1 + 2 + 3 upstream).
  - Sector output-weighted global intensity (as requested):
        I_j^global = sum_r (t[r,j] * x[r,j]) / sum_r x[r,j]
  - EUR→USD 2015 annual avg: 1 EUR = 1.1096 USD (ECB).
  - Unit conversion to (ton CO2e / 10k USD):
        (kg/M.EUR) × 0.001 (ton/kg) ÷ 1.1096 (USD/EUR) × 10 (10kUSD/100kUSD... )
    Actually: 1 kg/M.EUR = 0.001 ton / (1e6 EUR) = 0.001 ton / (1.1096e6 USD)
                         = (0.001/1.1096e6) × 1e4 ton / 10k USD
                         ≈ 9.012e-6 ton / 10k USD
"""
import os
import numpy as np
import pandas as pd

DATA = os.environ.get("SCOPE3_EXIOBASE_PATH", "./data/IOT_2015_pxp")
OUT = os.environ.get("SCOPE3_EXP_OUT", "./replication/output/figures/experiment")
os.makedirs(OUT, exist_ok=True)

EUR_USD_2015 = 1.1096
GWP = {"CO2": 1.0, "CH4": 28.0, "N2O": 265.0}

TARGETS = [
    # (SIC, SIC name, EXIOBASE sector, quality note)
    ("2821", "Plastic Materials",
     "Plastics, basic",
     "Direct match: EXIOBASE 'Plastics, basic' corresponds to primary plastic "
     "resin production; close to SIC 2821."),
    ("2834", "Pharmaceutical Preparations",
     "Chemicals nec",
     "APPROXIMATE: EXIOBASE pxp has no dedicated pharmaceutical sector; "
     "'Chemicals nec' is the broadest chemicals product covering pharma, "
     "soaps, paints, dyes, specialty chemicals. Likely UNDER-estimates "
     "pharma-specific intensity due to heterogeneous mix."),
    ("3711", "Motor Vehicles",
     "Motor vehicles, trailers and semi-trailers (34)",
     "EXIOBASE does not separate vehicle assembly from parts; same sector "
     "used for SIC 3711 and 3714."),
    ("3714", "Motor Vehicle Parts",
     "Motor vehicles, trailers and semi-trailers (34)",
     "Same EXIOBASE sector as SIC 3711 — combined sector; parts-only "
     "intensity cannot be isolated."),
    ("2844", "Perfumes and Cosmetics",
     "Chemicals nec",
     "APPROXIMATE: no cosmetics-specific sector in EXIOBASE; mapped to "
     "'Chemicals nec' (broader chemical products). Heterogeneous mix."),
]


def load_labels():
    x = pd.read_csv(os.path.join(DATA, "x.txt"), sep="\t")
    x.columns = ["region", "sector", "x"]
    return x


def load_matrix(path, n_header=2, n_index=2):
    """Load a matrix with multi-row header and multi-column index."""
    arr = pd.read_csv(path, sep="\t", header=list(range(n_header)),
                      index_col=list(range(n_index)))
    return arr


def build_ghg_vector():
    F = pd.read_csv(os.path.join(DATA, "air_emissions/F.txt"),
                    sep="\t", header=[0, 1], index_col=0)
    # F is (stressors) x (region, sector)
    print(f"F shape: {F.shape}")
    ghg = np.zeros(F.shape[1])
    used = []
    for stressor in F.index:
        s = str(stressor)
        if "bio" in s.lower():
            continue  # biogenic: exclude
        if s.startswith("CO2"):
            ghg += F.loc[stressor].values * GWP["CO2"]
            used.append((s, "CO2", GWP["CO2"]))
        elif s.startswith("CH4"):
            ghg += F.loc[stressor].values * GWP["CH4"]
            used.append((s, "CH4", GWP["CH4"]))
        elif s.startswith("N2O"):
            ghg += F.loc[stressor].values * GWP["N2O"]
            used.append((s, "N2O", GWP["N2O"]))
    print(f"Aggregated {len(used)} GHG stressors (AR5 GWP100, biogenic excluded):")
    for s, g, w in used:
        print(f"  {g:>4} × {w:<5g}  {s}")
    return ghg, used, list(F.columns)


def main():
    xdf = load_labels()
    print(f"Loaded x: {len(xdf)} region-sector rows")
    n = len(xdf)
    regions = xdf["region"].unique().tolist()
    sectors = xdf["sector"].unique().tolist()
    print(f"  {len(regions)} regions × {len(sectors)} products = {len(regions)*len(sectors)}")

    ghg_kg, stressors_used, F_cols = build_ghg_vector()
    # Safety check: F column order must match x row order
    F_labels = [(str(r), str(s)) for r, s in F_cols]
    x_labels = list(zip(xdf["region"].astype(str), xdf["sector"].astype(str)))
    assert F_labels == x_labels, "F columns do not align with x rows"

    x = xdf["x"].values.astype(np.float64)

    # Direct intensity per unit output (kg CO2e / M.EUR)
    with np.errstate(divide="ignore", invalid="ignore"):
        S = np.where(x > 0, ghg_kg / x, 0.0)
    print(f"S non-zero: {np.count_nonzero(S)}/{n}")

    # Load A (9800 x 9800); first 2 rows header, first 2 cols index
    print("Loading A.txt (this takes a moment)...")
    A = pd.read_csv(os.path.join(DATA, "A.txt"), sep="\t",
                    header=[0, 1], index_col=[0, 1]).values.astype(np.float64)
    print(f"A shape: {A.shape}")
    assert A.shape == (n, n)

    print("Computing Leontief inverse L = (I - A)^-1 ...")
    I = np.eye(n, dtype=np.float64)
    L = np.linalg.solve(I - A, I)
    print("L done.")

    # Total cradle-to-gate intensity per unit output: t = S @ L
    t = S @ L  # shape (n,)  kg CO2e per M.EUR of final output
    print(f"t stats: min={t.min():.1f}, median={np.median(t):.1f}, max={t.max():.1f} (kg/M.EUR)")

    # Build per-sector aggregation
    sec_of = xdf["sector"].values
    rows = []
    for sic, sic_name, exio_sec, note in TARGETS:
        mask = sec_of == exio_sec
        if mask.sum() == 0:
            print(f"WARNING: no rows match '{exio_sec}'")
            continue
        x_total = x[mask].sum()             # sum_r X_rj  (M.EUR)
        E_total = (t[mask] * x[mask]).sum()  # sum_r E_rj  (kg CO2e)
        I_pre = E_total / x_total            # kg CO2e / M.EUR
        # Convert kg/M.EUR -> ton/10k USD
        # 1 kg/M.EUR = 0.001 ton / 1.1096e6 USD = (0.001/1.1096e6)*1e4 ton/10kUSD
        conv = (0.001 / (EUR_USD_2015 * 1e6)) * 1e4  # ≈ 9.012e-6
        I_post = I_pre * conv
        rows.append({
            "SIC_code": sic,
            "SIC_name": sic_name,
            "EXIOBASE_sector": exio_sec,
            "n_regions": int(mask.sum()),
            "global_output_MEUR": x_total,
            "global_footprint_kg_CO2e": E_total,
            "intensity_kg_per_MEUR": I_pre,
            "intensity_ton_per_10kUSD": I_post,
            "note": note,
        })

    out = pd.DataFrame(rows)
    csv_path = os.path.join(OUT, "exiobase2015_sic_benchmarks.csv")
    out.to_csv(csv_path, index=False)
    print(f"\nSaved {csv_path}")
    with pd.option_context("display.max_colwidth", 40, "display.width", 200):
        print(out.to_string(index=False))


if __name__ == "__main__":
    main()
