# Public EMRIO Checkpoint Tables

These CSV files are aggregate, non-reversible checkpoints generated from the
actual EMRIO replication outputs by `replication/pipeline/06_generate_public_checkpoints.jl`.
They are intended for `replication/notebooks/verify_actual_emrio_checkpoints.ipynb` and `replication/notebooks/trace_step4_leontief_scope23.ipynb`.

The checkpoint tables do not contain firm identifiers, segment identifiers,
company names, ISINs, CDP account fields, FactSet keys, or reversible matrix
data. Country/SIC tables apply small-cell suppression; rows with unsafe small
counts are either combined into a suppressed bucket or omitted when a safe
aggregate bucket cannot be formed. For binary reported--benchmark indicators,
secondary subgroup counts and shares are masked when either nonzero side of the
binary split is at or below the small-cell threshold.

## Files

- `01_sector_emissions_by_country_sic.csv`: country/sector-prefix aggregate sector emissions from the Step 1 output.
- `02_scope1_allocation_summary_by_country_sic.csv`: country/SIC aggregate Scope 1 allocation summaries from segment-level private outputs.
- `03_emrio_aggregation_diagnostics.csv`: non-reversible diagnostics from `q_est` and figure-source private outputs.
- `04_scope23_by_country_sic.csv`: country/SIC aggregate Scope 1, Scope 2, Scope 3, and Scope-share summaries.
- `05_reported_benchmark_by_country.csv`: country-level reported-vs-benchmark aggregate comparison with small countries combined.
- `06_reported_benchmark_by_sic.csv`: SIC-level reported-vs-benchmark aggregate comparison, omitting unsafe small SIC cells.
- `07_estimator_definitions_summary.csv`: headline estimator and alternative firm-ratio summaries.
- `08_open_mrio_sic_comparison.csv`: SIC-level EMRIO, EXIOBASE, and GLORIA open-MRIO reference scope shares. The GLORIA values are copied from the audited aggregate SIC1 table only; no GLORIA raw data, zip files, or `scope_vectors.npz` are included. `n_sectors` is an MRIO sector-count diagnostic, not a company count.
- `09_uncertainty_summary.csv`: aggregate Monte Carlo holdout uncertainty intervals.
- `10_representativeness_summary.csv`: aggregate representativeness summaries for available comparison sets.
- `11_step4_loaded_objects.csv`: dimensions and release status for objects loaded by the actual Step 4 run.
- `12_step4_matrix_construction.csv`: public-safe diagnostics for `T_agg`, `A`, `I_EMRIO`, and `I - A`; no matrix entries or nonzero-value quantiles are released.
- `13_step4_leontief_inverse_trace.csv`: stage-by-stage public trace of inverse, multiplier, energy-vector, and Scope propagation diagnostics.
- `14_step4_scope23_equation_checks.csv`: aggregate equation checks for Scope 2+3, Scope 2, Scope 3, negative-value counts, and deterministic inverse residual checks.

## Not Included

The public checkpoint directory does not include raw `<DATA_ROOT>` inputs, firm-level
comparison tables, segment-level rows, company-name tables, or reversible JLD2
intermediate objects. Exact end-to-end reruns from raw inputs require licensed data access.
