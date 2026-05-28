#!/usr/bin/env python3
"""
table_country_ratio.py — Table 1: Number of reporting companies and share
of companies for which the EMRIO-based estimate exceeds the self-reported
value, by country.

Original: scripts/GHG_scope_analyis/country_ratio.ipynb
Paper reference: Table 1

Usage:
    python table_country_ratio.py [--input INPUT_CSV] [--output OUTPUT_CSV]

Defaults:
    --input  ../output/figures/df_fig1_20240406.csv
    --output ../output/figures/table_country_ratio.csv
"""
import argparse
import os
import pandas as pd


def main():
    parser = argparse.ArgumentParser(
        description="Generate Table 1: country-level reporting stats"
    )
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_input = os.path.join(
        script_dir, "..", "output", "figures", "df_fig1_20240406.csv"
    )
    default_output = os.path.join(
        script_dir, "..", "output", "figures", "table_country_ratio.csv"
    )

    parser.add_argument("--input", default=default_input, help="Input CSV path")
    parser.add_argument("--output", default=default_output, help="Output CSV path")
    args = parser.parse_args()

    # ---- Load data ----
    df = pd.read_csv(args.input)
    print(f"Loaded {len(df)} companies from {args.input}")

    # ---- Country configuration (hardcoded, matching paper) ----
    countries = ["IND", "USA", "DEU", "GBR", "FRA", "JPN", "CAN", "BRA", "ESP"]
    name_map = {
        "USA": "the United States",
        "JPN": "Japan",
        "FRA": "France",
        "GBR": "the United Kingdom",
        "DEU": "Germany",
        "CAN": "Canada",
        "BRA": "Brazil",
        "ESP": "Spain",
        "IND": "India",
        "Other": "others",
    }

    # Classify: keep specified countries, rest as "Other"
    df["ISO_COUNTRY"] = df["ISO_COUNTRY"].apply(
        lambda x: x if x in countries else "Other"
    )

    # ---- Compute per-country stats ----
    # Order matches the paper: by company count descending, others last
    country_order = ["USA", "JPN", "FRA", "GBR", "DEU", "CAN", "BRA", "ESP", "IND", "Other"]

    rows = []
    for c in country_order:
        sub = df[df["ISO_COUNTRY"] == c]
        n = len(sub)
        n_est_gt = (sub["g_S3_est"] > sub["g_S3_CDP_c"]).sum()
        share = round(n_est_gt / n, 2) if n > 0 else 0.0
        rows.append({
            "Country": name_map[c],
            "No. of Reporting Cos.": n,
            "Estimate>Report Share": share,
        })

    # Total row
    n_total = len(df)
    n_est_gt_total = (df["g_S3_est"] > df["g_S3_CDP_c"]).sum()
    share_total = round(n_est_gt_total / n_total, 2)
    rows.append({
        "Country": "Total",
        "No. of Reporting Cos.": n_total,
        "Estimate>Report Share": share_total,
    })

    result = pd.DataFrame(rows)

    # ---- Print ----
    print()
    print("Table 1: Reporting companies and Estimate>Report share by country")
    print(result.to_string(index=False))

    # ---- Save ----
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    result.to_csv(args.output, index=False)
    print(f"\nSaved to {args.output}")


if __name__ == "__main__":
    main()
