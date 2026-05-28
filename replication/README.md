# Replication Package

**Paper**: "Large Missing Emissions in Corporate Scope 3 Disclosures"

This replication package reproduces the paper's main computational results
(Scope 1, 2, and 3 GHG emissions for 9,466 companies across 121 countries)
from the underlying proprietary data sources.

## Prerequisites

### Software
- **Julia 1.5.4** (the version used for the original analysis)
- Required packages: CSV, DataFrames (0.22), DataFramesMeta, JLD2,
  SparseArrays, LinearAlgebra, XLSX

### Data
This package assumes access to the following proprietary datasets,
installed at paths specified in `config.jl`:

| Dataset | Description | Used in |
|---------|-------------|---------|
| EMRIO | Enterprise-level Multi-Regional IO (78,677×78,677 transaction matrix) | Steps 3-4 |
| CDP | Carbon Disclosure Project firm-level emissions | Step 2 |
| IEA | International Energy Agency CO₂ by sector | Step 1 |
| EDGAR | EU emissions database (non-CO₂ gases) | Step 1 |
| EPA | US EPA Greenhouse Gas Reporting Program | Step 2 |
| METI | Japan Ministry of Economy emissions data | Step 2 |
| FactSet | Company financial data (segments, sales) | Steps 1-4 |

## Quick Start

```bash
cd replication/
julia run_all.jl
```

Or run individual steps:

```bash
julia pipeline/01_sector_emissions.jl    # Step 1
julia pipeline/02_scope1_subsegments.jl  # Step 2
julia pipeline/03_emrio_aggregate.jl     # Step 3
julia pipeline/04_scope23.jl            # Step 4
```

## Configuration

Paths are read from environment variables (see `config.jl`):

```bash
export SCOPE3_BASE_PATH=/path/to/supplychain    # project root
export SCOPE3_DATA_ROOT=/path/to/data           # external data root (<DATA_ROOT>)
```

If unset, the defaults are `./` and `./data/` respectively.

Other parameters live in `config.jl`:

- `YEAR` — analysis year (default: 2015)
- `GHG_TYPE` — greenhouse gas scope (default: "GHG6")
- `COUNTRY_LIST_OVERRIDE` — set to a vector of country codes for testing

The EXIOBASE comparison plots (`plots/fig_triangle_exiobase.py`,
`plots/exiobase_sector_intensity.py`) additionally read:

```bash
export SCOPE3_EXIOBASE_PATH=/path/to/IOT_2015_pxp
export SCOPE3_FIG_PATH=./replication/output/figures
export SCOPE3_EXP_OUT=./replication/output/figures/experiment
```

**Important**: All output is written to `replication/output/`.
Original results outside this directory are never modified.

## Pipeline Structure

### Step 1: Sector-Level Emissions (`pipeline/01_sector_emissions.jl`)
- **SI Reference**: S1 (Eqs. S1-1 to S1-6)
- **Input**: IEA CO₂, EDGAR non-CO₂, country IO tables
- **Output**: `output/i_x_g/{YEAR}/{country}.csv` (71 countries)
- Computes sector-level GHG emissions and output for each country,
  combining IEA CO₂ data with EDGAR non-CO₂ data, and calculates
  the Rest-of-World (RoW) residual.

### Step 2: Scope 1 Subsegment Estimates (`pipeline/02_scope1_subsegments.jl`)
- **SI Reference**: S2 (Eqs. S2-1 to S2-20)
- **Input**: Step 1 output, CDP, EPA, METI, FactSet segment data
- **Output**: `output/g_S1_{YEAR}/{country}.csv` (71 countries)
- Estimates firm-level Scope 1 emissions by downscaling from
  company → segment → subsegment using the 4-step CDP methodology,
  supplemented by EPA (USA) and METI (Japan) facility data.

### Step 3: EMRIO Aggregation (`pipeline/03_emrio_aggregate.jl`)
- **SI Reference**: S3 (Main Eq. 3-4)
- **Input**: Step 2 output, EMRIO database
- **Output**: `output/{YEAR}/emrio_agg_{tag}.jld2`
- Loads the full EMRIO transaction matrix, matches Scope 1 estimates
  to subsegments, builds NOS/OS concordance matrices, and aggregates
  unmatched named segments into their sector's "Other Sources" category.

### Step 4: Leontief & Scope 2/3 (`pipeline/04_scope23.jl`)
- **Paper Reference**: Main Eqs. 5-8, SI S4-S5
- **Input**: Step 3 intermediate, country IO tables
- **Output**: `output/{YEAR}/q_est_{tag}.csv`
- Computes the Leontief inverse L = (I-A)⁻¹, total emission multipliers
  e = f×L, identifies energy supply sectors per country (SIC 4911-4925),
  and decomposes total supply chain emissions into Scope 2 (energy) and
  Scope 3 (non-energy supply chain).

## Paper-to-Code Mapping

| Paper | Equation | Code |
|---|---|---|
| Main Eq. 1 | Scope 1 subsegment downscaling | `lib/scope1_cdp.jl` |
| Main Eq. 2 | OS residual | `lib/scope1_generate.jl` |
| Main Eq. 3 | EMRIO transaction matrix T | `lib/load_emrio.jl` |
| Main Eq. 4 | Concordance aggregation | `lib/nos_aggregate.jl` |
| Main Eq. 5 | L = (I-A)⁻¹ Leontief inverse | `lib/scope23_leontief.jl` |
| Main Eq. 6 | e = f×L emission multiplier | `lib/scope23_leontief.jl` |
| Main Eq. 7 | Scope 2 (energy supply chain) | `lib/scope23_leontief.jl` |
| Main Eq. 8 | Scope 3 = S2+3 - S2 | `lib/scope23_leontief.jl` |
| SI S1.1 | IEA CO₂ allocation | `lib/arrange_sector.jl` |
| SI S1.2 | EDGAR non-CO₂ | `lib/arrange_sector.jl` |
| SI S1.4 | RoW emissions | `lib/rest_of_world.jl` |
| SI S2.1 | CDP → subsegment | `lib/scope1_cdp.jl` |
| SI S2.3 | EPA → subsegment | `lib/scope1_epa.jl` |
| SI S3 | Emission intensity f | `lib/nos_aggregate.jl` |
| SI S4-S5 | Scope 2 energy identification | `lib/scope23_leontief.jl` |

## Verification

After running the pipeline, verify results match the original output:

```bash
julia pipeline/verify_step1.jl   # Compare i_x_g CSVs
julia pipeline/verify_step2.jl   # Compare g_S1 CSVs
julia pipeline/verify_step4.jl   # Compare q_est CSV
```

Each verification script reports column-level numerical closeness
(exact match, approximate match within rtol=1e-6, or failure).

## File Organization

```
replication/
├── config.jl                  # Central configuration (paths, parameters)
├── run_all.jl                 # Master pipeline runner
├── README.md                  # This file
├── lib/                       # Library functions
│   ├── utils.jl               # Utilities (file discovery, concordances)
│   ├── load_emissions_data.jl # Data loaders (CDP, IEA, EDGAR, EPA, METI)
│   ├── load_emrio.jl          # EMRIO database loader
│   ├── load_country_io.jl     # Country-level IO data loader
│   ├── rest_of_world.jl       # RoW emissions (SI S1.4)
│   ├── arrange_sector.jl      # Sector GHG computation (SI S1)
│   ├── scope1_cdp.jl          # CDP Scope 1 methodology (SI S2.1)
│   ├── scope1_epa.jl          # EPA Scope 1 methodology (SI S2.3)
│   ├── scope1_generate.jl     # Scope 1 orchestrator (SI S2)
│   ├── nos_aggregate.jl       # NOS/OS aggregation (SI S3)
│   └── scope23_leontief.jl    # Leontief & Scope 2/3 (Eqs. 5-8)
├── pipeline/                  # Pipeline scripts
│   ├── 01_sector_emissions.jl
│   ├── 02_scope1_subsegments.jl
│   ├── 03_emrio_aggregate.jl
│   ├── 04_scope23.jl
│   ├── verify_step1.jl
│   ├── verify_step2.jl
│   └── verify_step4.jl
└── output/                    # All pipeline output (created at runtime)
    ├── i_x_g/{YEAR}/          # Step 1 output
    ├── g_S1_{YEAR}/           # Step 2 output
    └── {YEAR}/                # Steps 3-4 output
```

## Input Contract

This package is **code-decoupled** from the original `module/` and
`controller/` directories: no pipeline step includes or calls code from
those directories.  However, several input files were originally produced
by preprocessing scripts that live outside `replication/`.  The tables
below classify every external file that the pipeline **actually reads
at runtime** (verified by tracing `CSV.read`, `XLSX.readtable`, `@load`,
and `JSON.parsefile` calls in the executed code paths of Steps 1-5).

### Raw / Reference Data (external, not generated by this codebase)

These are authoritative source files from third-party databases or
public concordance tables.  They are legitimate pipeline inputs.

| File | Read by (runtime call site) | Source |
|------|----------------------------|--------|
| `IMPORT_PATH/IO/EIO/EMRIO/{YEAR}/*.jld2` | `lib/load_emrio.jl:48` | EMRIO database (proprietary) |
| `IMPORT_PATH/IO/EIO/DEIO/{country}/{YEAR}/data_*.jld2` | `lib/load_country_io.jl:30` | Country IO/SUT tables (proprietary) |
| `data/GHG/IEA/IEA_all.csv` | `lib/load_emissions_data.jl:99` | IEA World Energy Balances |
| `data/GHG/IEA/concordance_IEA_SIC.csv` | `lib/load_emissions_data.jl:101` | IEA flow-to-SIC concordance |
| `data/GHG/IEA/energy_emission_factor.csv` | `lib/load_emissions_data.jl:108` | IPCC emission factors |
| `data/GHG/Edgar/df_ipcc_sic.csv` | `lib/load_emissions_data.jl:167` | IPCC-to-SIC concordance |
| `data/GHG/Edgar/df_non_CO2.csv` | `lib/load_emissions_data.jl:168` | EDGAR non-CO2 emissions |
| `data/GHG/Edgar/df_EDGAR_CO2.csv` | `lib/load_emissions_data.jl:169` | EDGAR CO2 emissions |
| `data/GHG/GHG_CDP/g_CDP.csv` | `lib/load_emissions_data.jl:35` | CDP company Scope 1 |
| `data/GHG/GHG_CDP/subr_gS1_CDP.csv` | `lib/load_emissions_data.jl:36` | CDP regional Scope 1 |
| `data/GHG/GHG_CDP/subr_gS2_CDP.csv` | `lib/load_emissions_data.jl:37` | CDP regional Scope 2 |
| `data/GHG/GHG_CDP/g_CDP_S3.csv` | `lib/load_emissions_data.jl:38`, `lib/figure_data.jl:397` | CDP Scope 3 (aggregated) |
| `data/GHG/GHG_CDP/g_CDP_S3_upstream.csv` | `lib/figure_data.jl:68` | CDP Scope 3 upstream categories (Step 5 only) |
| `data/GHG/US/f_NAISC.xlsx` | `lib/scope1_epa.jl:52` | EPA facility NAICS codes |
| `data/GHG_related/gistfile1.txt` | `lib/load_emissions_data.jl:115` | ISO3 country code dictionary |
| `data/tmp_files/bea_naics_2012_2017_concordance.csv` | `lib/scope1_epa.jl:49` | BEA-NAICS concordance (US govt public table) |
| `data/tmp_files/df_SIC_desc.jld2` | `lib/figure_data.jl:173` | SIC code descriptions (Step 5 only) |
| `data/for_app/p_SIC_mod.csv` | `lib/figure_data.jl:176` | SIC modification table (Step 5 only) |

### Preprocessed Inputs (generated outside replication, treated as frozen inputs)

These files were produced by preprocessing scripts in `module/` or by
external data pipelines.  They are treated as fixed inputs to the
replication pipeline.  Regenerating them inside `replication/` would
require porting complex Japan-specific, EPA-specific, or FactSet-specific
matching logic that is outside the paper's core methodology.

| File | Read by (runtime call site) | Original generator | Rationale for not porting |
|------|----------------------------|-------------------|--------------------------|
| `IMPORT_PATH/tmp/nt_arranged_base_segment_*.jld2` | `lib/load_emissions_data.jl:226` | External FactSet data pipeline | 1.4 GB compiled segment database; generation requires full FactSet financial data processing |
| `data/GHG/JPN_METI_2015_g_i.csv` | `lib/scope1_generate.jl:48` | `module/arrange_sector/GHG_sector_arrange_JPN.jl` | Japan 3EID IO table has GHG embedded in IO structure; Step 1 general logic does not apply |
| `data/GHG/JPN_METI_2015_gS1.csv` | `lib/load_emissions_data.jl:59` | `module/GHG_footprint/estimate_JPN_METI.jl` | Requires Nistep/Whois matching databases for Japan company identification |
| `data/GHG/US/g_EPA_f_2015.csv` | `lib/scope1_epa.jl:58` | EPA facility data pre-matched to FactSet entity IDs | Matching involves manual curation and facility-name fuzzy matching against FactSet database |
| `data/for_app/sym_entity_mod.csv` | `lib/scope1_epa.jl:37` | FactSet entity name lookup with encoding fixes | 492 MB entity table; referenced by `controller/app_data.jl` as a prerequisite asset |

### Defined but NOT called at runtime

These functions exist in `lib/load_emissions_data.jl` but are never
invoked by any pipeline step (1-5).  Their associated data files are
therefore **not required** for reproduction.

| Function | Data file it would read | Why unused |
|----------|------------------------|------------|
| `load_sec_entity()` | `IMPORT_PATH/FactSet/*/sec_entity.txt` | Entity concordance is accessed through `nt_arranged_base_segment` instead |
| `load_epa_data()` | `data/GHG/US/g_EPA_2015.csv` | Step 2 reads `g_EPA_f_2015.csv` (facility-level) directly in `scope1_epa.jl` |

### Files NOT required at runtime

| Item | Status |
|------|--------|
| `module/` directory | Not included or called by any pipeline step |
| `controller/` directory | Not included or called by any pipeline step |
| `module/functions/rename_func.jl` | Previously included in utils.jl but never called; include removed |

## Notes

- **Memory**: The Leontief inverse (Step 4) requires ~40GB RAM for the
  full 78K×78K matrix inversion. Ensure adequate memory.
- **Julia 1.5 compatibility**: This code uses DataFrames 0.22 syntax.
  Some patterns differ from modern Julia/DataFrames conventions.
- **Reproducibility**: Output file names include a fixed tag (`OUTPUT_TAG`
  in config.jl) to ensure deterministic file names across runs.
