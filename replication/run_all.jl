# ============================================================================
# run_all.jl — Master script to run the full replication pipeline.
#
# Usage:
#   cd supplychain/replication
#   julia run_all.jl
#
# This script executes all pipeline steps in sequence:
#   Step 1: Sector-level emissions (IEA + EDGAR)    → output/i_x_g/{YEAR}/
#   Step 2: Scope 1 subsegment estimates (CDP+EPA+METI) → output/g_S1_{YEAR}/
#   Step 3: EMRIO aggregation (NOS → OS concordance)  → output/{YEAR}/emrio_agg_*.jld2
#   Step 4: Leontief inverse & Scope 2/3 computation  → output/{YEAR}/q_est_*.csv
#
# Each step is self-contained: it loads its own dependencies and reads
# inputs from disk.  Steps communicate only via output files.
#
# Prerequisites:
#   - Julia 1.5.4 with packages: CSV, DataFrames, DataFramesMeta, JLD2,
#     SparseArrays, LinearAlgebra, XLSX
#   - Access to proprietary data (EMRIO, CDP, IEA, EDGAR, EPA, METI)
#     at paths specified in config.jl
#
# IMPORTANT: This script writes ONLY to replication/output/.
#            It does NOT modify any original files or results.
# ============================================================================
#
# NOTICE: This file depends on external files under import.
# Required import dependencies (via Steps 1-4):
#   - <DATA_ROOT>/IO/EIO/EMRIO/2015/20240228.jld2
#   - <DATA_ROOT>/IO/EIO/DEIO/{COUNTRY}/2015/data_20240224.jld2
#     (71 countries; see config.jl for the full list)
#   - <DATA_ROOT>/FactSet/Financial/ff_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Shipping/sc_ship_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Supplychain/ent_scr_sec_entity.txt
#   - <DATA_ROOT>/tmp/nt_arranged_base_segment_20231210.jld2
# Please ensure these files are available when running this replication script.

println("=" ^ 70)
println("Replication Pipeline — Full Run")
println("=" ^ 70)
println()

t_start = time()

# ---- Step 1: Sector-level emissions ----
println(">>> Running Step 1: Sector-level emissions...")
t1 = time()
include(joinpath(@__DIR__, "pipeline", "01_sector_emissions.jl"))
println("  Step 1 completed in $(round(time() - t1, digits=1))s\n")

# ---- Step 2: Scope 1 subsegment estimates ----
println(">>> Running Step 2: Scope 1 subsegment estimates...")
t2 = time()
include(joinpath(@__DIR__, "pipeline", "02_scope1_subsegments.jl"))
println("  Step 2 completed in $(round(time() - t2, digits=1))s\n")

# ---- Step 3: EMRIO aggregation ----
println(">>> Running Step 3: EMRIO aggregation...")
t3 = time()
include(joinpath(@__DIR__, "pipeline", "03_emrio_aggregate.jl"))
println("  Step 3 completed in $(round(time() - t3, digits=1))s\n")

# ---- Step 4: Leontief & Scope 2/3 ----
println(">>> Running Step 4: Leontief & Scope 2/3...")
t4 = time()
include(joinpath(@__DIR__, "pipeline", "04_scope23.jl"))
println("  Step 4 completed in $(round(time() - t4, digits=1))s\n")

# ---- Summary ----
total = round(time() - t_start, digits=1)
println("=" ^ 70)
println("All steps completed in $(total)s")
println()
println("Outputs:")
println("  Sector emissions:  replication/output/i_x_g/$(YEAR)/")
println("  Scope 1 estimates: replication/output/g_S1_$(YEAR)/")
println("  EMRIO aggregation: replication/output/$(YEAR)/emrio_agg_$(OUTPUT_TAG).jld2")
println("  Final q_est:       replication/output/$(YEAR)/q_est_$(OUTPUT_TAG).csv")
println()
println("To verify against original results, run:")
println("  julia pipeline/verify_step1.jl")
println("  julia pipeline/verify_step2.jl")
println("  julia pipeline/verify_step4.jl")
println("=" ^ 70)
