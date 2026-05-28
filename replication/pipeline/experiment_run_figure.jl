# ============================================================================
# experiment_run_figure.jl — Run the EMRIO reduction experiment end-to-end
# and generate figure-ready CSV for the country ratio plot.
#
# INTERNAL EXPERIMENT ONLY. No production files are modified.
#
# Memory-optimized: loads nt_EMRIO once, subsets immediately, frees original
# before assembling the world T matrix. Peak memory ≈ 1× EMRIO size.
#
# Usage:
#   cd supplychain/replication
#   julia pipeline/experiment_run_figure.jl
# ============================================================================

println("=" ^ 70)
println("EXPERIMENT: Full Pipeline → Figure Data (Reduced EMRIO)")
println("=" ^ 70)
println()

using CSV, DataFrames, DataFramesMeta, JSON, JLD2, SparseArrays, LinearAlgebra
using Dates

include(joinpath(@__DIR__, "..", "config.jl"))
include(joinpath(@__DIR__, "..", "lib", "utils.jl"))
include(joinpath(@__DIR__, "..", "lib", "rest_of_world.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emissions_data.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emrio.jl"))
include(joinpath(@__DIR__, "..", "lib", "nos_aggregate.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_country_io.jl"))
include(joinpath(@__DIR__, "..", "lib", "scope23_leontief.jl"))
include(joinpath(@__DIR__, "..", "lib", "figure_data.jl"))
include(joinpath(@__DIR__, "..", "lib", "experiment_emrio_reduce.jl"))

# ============================================================================
# EXPERIMENT PARAMETERS
# ============================================================================
const EXPERIMENT_DROP_IDX = 100:119

yr = YEAR

# ============================================================================
# STEP 1: Load IEA data (small, needed for g_RoW)
# ============================================================================
println("Loading IEA data...")
iea_data = load_iea_data(BASE_PATH)

# ============================================================================
# STEP 2: Load nt_EMRIO directly from JLD2 (avoid load_emrio's extra copies)
# ============================================================================
println("Loading EMRIO JLD2 directly...")
emrio_filename = get_file_with_highest_number(EMRIO_PATH)
@load joinpath(EMRIO_PATH, emrio_filename) nt_EMRIO
println("  EMRIO_T size: ", size(nt_EMRIO.EMRIO_T))

# Compute g_RoW before reduction (uses att_r which is unchanged)
println("  Computing g_RoW...")
g_RoW = compute_g_RoW(nt_EMRIO, iea_data, yr)
country_list = unique(nt_EMRIO.att_r.ISO_COUNTRY_r)

# Save att_qd reference for figure generation (before reduction, small copy)
println("  Saving att_qd reference for figures...")
att_qd_full = deepcopy(nt_EMRIO.att_qd)

# Load segment base data (needed for figure generation)
println("  Loading segment base data...")
seg = load_segment_base(IMPORT_PATH)
df_p_all = @linq deepcopy(
    seg.nt_arranged_base_segment.segment.ff_segbus_af_watt_sales_va_conv_segment
) |> dropmissing(:FF_SIC_CODE)

# ============================================================================
# STEP 3: Apply reduction (subsets directly, no deepcopy of large matrices)
# ============================================================================
println("\n--- Applying EMRIO reduction ---")
exp_result = reduce_emrio(nt_EMRIO; enabled=true, drop_idx=EXPERIMENT_DROP_IDX)
nt_EMRIO_exp = exp_result.nt_EMRIO_reduced

# Free original nt_EMRIO to reclaim memory
nt_EMRIO = nothing
GC.gc()
println("  Original nt_EMRIO freed.")

# Rebuild world T matrix from reduced EMRIO
println("  Assembling reduced world T matrix...")
T_exp = [nt_EMRIO_exp.EMRIO_T    nt_EMRIO_exp.T_q_RoWd;
         nt_EMRIO_exp.T_RoW_qd   nt_EMRIO_exp.T_RoW_RoWd]
println("  Reduced T matrix size: ", size(T_exp))

# ============================================================================
# STEP 4: Load Scope 1 & run NOS aggregation
# ============================================================================
println("\nLoading Scope 1 results...")
g_S1_dir = joinpath(OUTPUT_PATH, "g_S1_$(yr)")
files_yr = [f for f in readdir(g_S1_dir) if occursin(r"\.csv$", f)]
dfs = [DataFrame(CSV.File(joinpath(g_S1_dir, f))) for f in files_yr]
df_q = vcat(dfs...)
println("  Loaded $(length(files_yr)) files, $(nrow(df_q)) subsegments")

println("\nRunning NOS aggregation on reduced EMRIO...")
agg_exp = nos_aggregate(nt_EMRIO_exp, T_exp, df_q, g_RoW)
println("  T_agg size: ", size(agg_exp.T_agg))

# Free T_exp (large matrix no longer needed)
T_exp = nothing
GC.gc()

# ============================================================================
# STEP 5: Scope 2/3
# ============================================================================
println("\nComputing Scope 2/3...")
nt_stub = (att_r = nt_EMRIO_exp.att_r,)
info_qd_exp = deepcopy(nt_EMRIO_exp.att_qd)

result_exp = compute_scope23(
    agg_exp, nt_stub, country_list, IMPORT_PATH, yr, info_qd_exp
)
df_q_est_exp = result_exp.df_q_est
println("  Subsegments: ", nrow(df_q_est_exp))
println("  Scope 1 total:  ", round(sum(skipmissing(df_q_est_exp.g_S1)), digits=2))
println("  Scope 23 total: ", round(sum(skipmissing(df_q_est_exp.g_S23_EMRIO)), digits=2))

# Free heavy step 4 objects
result_exp = nothing
agg_exp = nothing
nt_EMRIO_exp = nothing
GC.gc()

# ============================================================================
# STEP 6: Generate figure data
#   Build a minimal emrio_data stub with att_qd_full (original, for sales/DATE)
# ============================================================================
println("\nGenerating country comparison figure data...")

# generate_country_data needs emrio_data with these fields:
#   .nt_EMRIO.att_qd  (for sales/DATE lookup)
#   .df_p_all          (for SIC codes / segment data)
emrio_stub = (
    nt_EMRIO = (att_qd = att_qd_full,),
    df_p_all = df_p_all,
)

df_country_exp = generate_country_data(df_q_est_exp, emrio_stub, yr, BASE_PATH, IMPORT_PATH)
println("  Companies: ", nrow(df_country_exp))
println("  Countries: ", length(unique(df_country_exp.ISO_COUNTRY)))
println("  Sum g_S3_est: ", round(sum(df_country_exp.g_S3_est), digits=2))
println("  Sum g_S3_CDP: ", round(sum(df_country_exp.g_S3_CDP_c), digits=2))

# ============================================================================
# STEP 7: Write outputs
# ============================================================================
exp_fig_dir = joinpath(OUTPUT_PATH, "figures", "experiment")
mkpath(exp_fig_dir)

outfile = joinpath(exp_fig_dir, "df_fig1_reduced_$(OUTPUT_TAG).csv")
CSV.write(outfile, df_country_exp, bom=true)
println("\n  Written to: ", outfile)

# Also save q_est for reference
exp_data_dir = joinpath(OUTPUT_PATH, string(yr), "experiment")
mkpath(exp_data_dir)
q_est_outfile = joinpath(exp_data_dir, "q_est_reduced_$(OUTPUT_TAG).csv")
CSV.write(q_est_outfile, df_q_est_exp, bom=true)
println("  q_est written to: ", q_est_outfile)

println("\n", "=" ^ 70)
println("Experiment pipeline complete.")
println("=" ^ 70)
