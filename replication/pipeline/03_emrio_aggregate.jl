# ============================================================================
# 03_emrio_aggregate.jl — Step 3: Load Scope 1 results & aggregate EMRIO.
#
# Original: controller/main.ipynb Cell 3
# Paper reference: SI S3, Main Eq. 3-4
#
# This step:
#   1. Loads all per-country g_S1 CSV files from Step 2
#   2. Loads the full EMRIO database
#   3. Calls nos_aggregate() to build concordance matrices and aggregate
#   4. Saves intermediate results (T_agg, f, etc.) to JLD2 for Step 4
#
# Prerequisites: Step 2 output in OUTPUT_PATH/g_S1_{YEAR}/
# Output: OUTPUT_PATH/{YEAR}/emrio_agg_{OUTPUT_TAG}.jld2
# ============================================================================

# NOTICE: This file depends on external files under import.
# Required import dependencies:
#   - <DATA_ROOT>/IO/EIO/EMRIO/2015/20240228.jld2
#   - <DATA_ROOT>/FactSet/Financial/ff_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Shipping/sc_ship_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Supplychain/ent_scr_sec_entity.txt
#   - <DATA_ROOT>/tmp/nt_arranged_base_segment_20231210.jld2
# Please ensure these files are available when running this replication script.

println("=" ^ 70)
println("Step 3: EMRIO Aggregation (NOS → OS concordance)")
println("=" ^ 70)

# ---- Load dependencies ----
using CSV, DataFrames, DataFramesMeta, JSON, JLD2, SparseArrays, LinearAlgebra

include(joinpath(@__DIR__, "..", "config.jl"))
include(joinpath(@__DIR__, "..", "lib", "utils.jl"))
include(joinpath(@__DIR__, "..", "lib", "rest_of_world.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emissions_data.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emrio.jl"))
include(joinpath(@__DIR__, "..", "lib", "nos_aggregate.jl"))

# ---- Create output directory ----
yr = YEAR
output_yr_dir = joinpath(OUTPUT_PATH, string(yr))
mkpath(output_yr_dir)

# ---- Load emissions data (needed for g_RoW) ----
println("Loading IEA data...")
iea_data = load_iea_data(BASE_PATH)

# ---- Load EMRIO ----
println("Loading EMRIO database...")
emrio = load_emrio(EMRIO_PATH, IMPORT_PATH, iea_data, yr; version=EMRIO_VERSION)
println("  T matrix size: ", size(emrio.T))
println("  Countries: ", length(emrio.country_list))

# ---- Load all Scope 1 results from Step 2 ----
println("Loading Scope 1 results from Step 2...")
g_S1_dir = joinpath(OUTPUT_PATH, "g_S1_$(yr)")
files_yr = [f for f in readdir(g_S1_dir) if occursin(r"\.csv$", f)]
dfs = [DataFrame(CSV.File(joinpath(g_S1_dir, f))) for f in files_yr]
df_q = vcat(dfs...)
println("  Loaded $(length(files_yr)) country files, $(nrow(df_q)) subsegments")

# ---- Run NOS aggregation ----
println("Running NOS aggregation...")
agg = nos_aggregate(emrio.nt_EMRIO, emrio.T, df_q, emrio.g_RoW)
println("  T_agg size: ", size(agg.T_agg))
println("  f vector length: ", length(agg.f))
println("  info_qd_agg rows: ", nrow(agg.info_qd_agg))
println("  info_q_agg rows: ", nrow(agg.info_q_agg))

# ---- Sanity checks ----
# f should have no Inf values
n_inf = count(isinf, vec(agg.f))
n_inf > 0 && @warn "f contains $n_inf Inf values"

# g_agg should be non-negative in aggregate
total_g = sum(filter(!isnan, vec(agg.g_agg)))
println("  Total aggregated emissions: ", round(total_g, digits=2))

# ---- Save intermediate results ----
# Only save what Step 4 needs: agg + lightweight emrio metadata.
# Do NOT save the full nt_EMRIO (which contains the 78K×78K T matrix).
if WRITE_INTERMEDIATE
    outfile = joinpath(output_yr_dir, "emrio_agg_$(OUTPUT_TAG).jld2")
    println("Saving intermediate results to: ", outfile)
    # Step 4 only accesses nt_EMRIO.att_r (for SUT/pp type checks)
    emrio_att_r      = emrio.nt_EMRIO.att_r
    emrio_country_list = emrio.country_list
    emrio_info_qd    = emrio.info_qd
    @save outfile agg emrio_att_r emrio_country_list emrio_info_qd
    println("  Saved successfully ($(round(filesize(outfile)/1e6, digits=1)) MB)")
end

println("\nStep 3 complete.")
println("=" ^ 70)
