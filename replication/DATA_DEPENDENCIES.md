# Data Dependencies (from `supplychain/data/`)

This document lists all files loaded from `supplychain/data/` by the replication pipeline.

**Total: 18 files, ~92 MB**

## CDP — Carbon Disclosure Project (SI S2.1)

| File | Size | Loaded by | Description |
|------|------|-----------|-------------|
| `data/GHG/GHG_CDP/g_CDP.csv` | 1.1 MB | `lib/load_emissions_data.jl` → `load_cdp_data()` | Company-level Scope 1 emissions |
| `data/GHG/GHG_CDP/subr_gS1_CDP.csv` | 2.0 MB | `lib/load_emissions_data.jl` → `load_cdp_data()` | Regional Scope 1 breakdown |
| `data/GHG/GHG_CDP/subr_gS2_CDP.csv` | 2.3 MB | `lib/load_emissions_data.jl` → `load_cdp_data()` | Regional Scope 2 breakdown |
| `data/GHG/GHG_CDP/g_CDP_S3.csv` | 60 KB | `lib/load_emissions_data.jl` → `load_cdp_data()` | Company-level Scope 3 emissions |
| `data/GHG/GHG_CDP/g_CDP_S3_upstream.csv` | 1.6 MB | `lib/figure_data.jl` | CDP Scope 3 upstream categories (Step 5) |

## IEA — International Energy Agency (SI S1.1)

| File | Size | Loaded by | Description |
|------|------|-----------|-------------|
| `data/GHG/IEA/IEA_all.csv` | 82 MB | `lib/load_emissions_data.jl` → `load_iea_data()` | IEA World Energy Balances |
| `data/GHG/IEA/concordance_IEA_SIC.csv` | 139 KB | `lib/load_emissions_data.jl` → `load_iea_data()` | IEA flow-to-SIC concordance table |
| `data/GHG/IEA/energy_emission_factor.csv` | 3.3 KB | `lib/load_emissions_data.jl` → `load_iea_data()` | IPCC CO2 emission factors by product |

## EDGAR — Emissions Database for Global Atmospheric Research (SI S1.2)

| File | Size | Loaded by | Description |
|------|------|-----------|-------------|
| `data/GHG/Edgar/df_ipcc_sic.csv` | 28 KB | `lib/load_emissions_data.jl` → `load_edgar_data()` | IPCC code → SIC code concordance |
| `data/GHG/Edgar/df_non_CO2.csv` | 125 KB | `lib/load_emissions_data.jl` → `load_edgar_data()` | Non-CO2 GHG emissions (CH4, N2O, F-gases) by country/sector |
| `data/GHG/Edgar/df_EDGAR_CO2.csv` | 79 KB | `lib/load_emissions_data.jl` → `load_edgar_data()` | CO2 emissions by country/IPCC sector |

## EPA — U.S. Environmental Protection Agency (SI S2.3)

| File | Size | Loaded by | Description |
|------|------|-----------|-------------|
| `data/GHG/US/f_NAISC.xlsx` | 1.1 MB | `lib/scope1_epa.jl` | EPA facility NAICS codes |
| `data/GHG/US/g_EPA_f_2015.csv` | 586 KB | `lib/scope1_epa.jl` via `load_epa_data()` | EPA facility-level emissions (pre-matched to FactSet) |

## METI — Japan Ministry of Economy (SI S2.2)

| File | Size | Loaded by | Description |
|------|------|-----------|-------------|
| `data/GHG/JPN_METI_2015_g_i.csv` | 54 KB | `lib/scope1_generate.jl` | Japan 3EID IO table with embedded GHG |
| `data/GHG/JPN_METI_2015_gS1.csv` | 421 KB | `lib/load_emissions_data.jl` → `load_meti_data()` | Japan METI company-level Scope 1 emissions |

## Reference / Concordance

| File | Size | Loaded by | Description |
|------|------|-----------|-------------|
| `data/GHG_related/gistfile1.txt` | 222 KB | `lib/load_emissions_data.jl` → `load_iea_data()` | ISO 3-letter country code → country name dictionary |
| `data/tmp_files/bea_naics_2012_2017_concordance.csv` | 187 KB | `lib/scope1_epa.jl` | BEA-NAICS concordance (US public table) |

## Usage by Pipeline Step

| Step | Script | Data sources loaded |
|------|--------|---------------------|
| Step 1 | `pipeline/01_sector_emissions.jl` | IEA, EDGAR, Japan 3EID IO, country code dictionary |
| Step 2 | `pipeline/02_scope1_subsegments.jl` | CDP (Scope 1/2), EPA, METI, BEA-NAICS concordance |
| Step 3 | `pipeline/03_emrio_aggregate.jl` | CDP (Scope 1, Scope 3) |
| Step 4 | `pipeline/04_scope23.jl` | *(reads Step 3 intermediate outputs, no direct data/ loads)* |
| Step 5 | `pipeline/05_figure_data.jl` | CDP (Scope 1, Scope 3, upstream) |
