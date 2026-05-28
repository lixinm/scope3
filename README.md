# scope3

Replication code for the paper **"Large Missing Emissions in Corporate Scope 3 Disclosures."**

This repository contains the Julia / Python pipeline used to compute
Scope 1, 2, and 3 greenhouse-gas (GHG) emissions for ~9,500 companies
across 121 countries by combining an enterprise-level Multi-Regional
Input-Output (EMRIO) model with firm-level disclosure data (CDP, EPA,
METI) and FactSet financial / supply-chain data.

## Repository layout

```
replication/
├── config.jl           Central configuration (paths read from ENV vars)
├── run_all.jl          Master pipeline runner
├── lib/                Reusable library functions
├── pipeline/           Pipeline steps 1–6 and verification scripts
├── plots/              Figure generation (matplotlib / Julia)
├── notebooks/          Diagnostic and trace notebooks
├── public_data/        Public-safe aggregated checkpoint CSVs
└── output/             All pipeline output (created at runtime)
data/                   Local data root (populated by user; not tracked)
```

See [`replication/README.md`](replication/README.md) for the full pipeline
description, paper-to-code mapping, and verification procedure.

## Requirements

- **Julia 1.5.4** with CSV, DataFrames 0.22, DataFramesMeta, JLD2,
  SparseArrays, LinearAlgebra, XLSX
- **Python 3.9+** with NumPy, Pandas, Matplotlib (for plotting and
  EXIOBASE comparison; see `replication/requirements.txt`)
- ~40 GB RAM for the Step 4 Leontief inverse on the full 78K × 78K matrix

## Data access

The pipeline depends on proprietary datasets (EMRIO, CDP, FactSet) and
public databases (IEA, EDGAR, EPA, METI, EXIOBASE). See
[`replication/DATA_ROOT_DEPENDENCIES.md`](replication/DATA_ROOT_DEPENDENCIES.md)
and [`replication/DATA_DEPENDENCIES.md`](replication/DATA_DEPENDENCIES.md)
for the full list of required files. Proprietary datasets must be obtained
from the original providers; this repository does not redistribute them.

A set of public-safe aggregated checkpoints is provided in
[`replication/public_data/checkpoints/`](replication/public_data/checkpoints/)
to allow inspection of intermediate pipeline state without access to the
proprietary raw data.

## Quick start

```bash
export SCOPE3_BASE_PATH=/path/to/this/repo
export SCOPE3_DATA_ROOT=/path/to/data

cd replication/
julia run_all.jl
```

Or run individual steps; see [`replication/README.md`](replication/README.md).

## Citation

If you use this code, please cite the paper (citation details to be added
upon publication).
