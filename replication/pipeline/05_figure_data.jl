# ============================================================================
# 05_figure_data.jl — Step 5: Generate figure-ready CSVs.
#
# Original: scripts/GHG_scope_analyis/fig_country.ipynb
# Paper reference: Figure 1 (country comparison), Figure 2 (triangle plot)
#
# This step:
#   1. Loads q_est from Step 4
#   2. Loads EMRIO (for att_qd sales/DATE and df_segment SIC codes)
#   3. Generates segment-level data for triangle plot (df_p_SIC_S123.csv)
#   4. Generates company-level data for country comparison (df_fig1_{tag}.csv)
#
# Prerequisites: Step 4 output (q_est_{OUTPUT_TAG}.csv)
# Output: OUTPUT_PATH/figures/df_p_SIC_S123.csv
#         OUTPUT_PATH/figures/df_fig1_{OUTPUT_TAG}.csv
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
println("Step 5: Figure Data Generation")
println("=" ^ 70)

# ---- Load dependencies ----
using CSV, DataFrames, DataFramesMeta, JSON, JLD2, SparseArrays, LinearAlgebra
using Dates

include(joinpath(@__DIR__, "..", "config.jl"))
include(joinpath(@__DIR__, "..", "lib", "utils.jl"))
include(joinpath(@__DIR__, "..", "lib", "rest_of_world.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emissions_data.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emrio.jl"))
include(joinpath(@__DIR__, "..", "lib", "figure_data.jl"))

yr = YEAR

# ---- Create output directory ----
fig_dir = joinpath(OUTPUT_PATH, "figures")
mkpath(fig_dir)

# ---- Load EMRIO (needed for att_qd and df_segment) ----
println("Loading IEA data...")
iea_data = load_iea_data(BASE_PATH)

println("Loading EMRIO database...")
emrio = load_emrio(EMRIO_PATH, IMPORT_PATH, iea_data, yr; version=EMRIO_VERSION)
println("  Countries: ", length(emrio.country_list))

# ---- Load q_est from Step 4 ----
q_est_file = joinpath(OUTPUT_PATH, string(yr), "q_est_$(OUTPUT_TAG).csv")
println("Loading q_est from: ", q_est_file)
df_q_est = DataFrame(CSV.File(q_est_file))
println("  Rows: ", nrow(df_q_est))

# ---- Generate triangle plot data (segment level) ----
println("\nGenerating triangle plot data...")
df_triangle = generate_triangle_data(df_q_est, emrio, yr, BASE_PATH, IMPORT_PATH)
println("  Segments: ", nrow(df_triangle))
println("  SIC categories: ", length(unique(df_triangle.SIC_1_desc)))
println("  Sum g_S1: ", round(sum(df_triangle.g_S1), digits=2))
println("  Sum g_S2: ", round(sum(df_triangle.g_S2), digits=2))
println("  Sum g_S3: ", round(sum(df_triangle.g_S3), digits=2))

outfile1 = joinpath(fig_dir, "df_p_SIC_S123.csv")
CSV.write(outfile1, df_triangle, bom=true)
println("  Written to: ", outfile1)

# ---- Generate country comparison data (company level) ----
println("\nGenerating country comparison data...")
df_country = generate_country_data(df_q_est, emrio, yr, BASE_PATH, IMPORT_PATH)
println("  Companies: ", nrow(df_country))
println("  Countries: ", length(unique(df_country.ISO_COUNTRY)))
println("  Sum g_S3_est: ", round(sum(df_country.g_S3_est), digits=2))
println("  Sum g_S3_CDP: ", round(sum(df_country.g_S3_CDP_c), digits=2))
println("  Ratio est/CDP: ", round(sum(df_country.g_S3_est) / sum(df_country.g_S3_CDP_c), digits=4))

outfile2 = joinpath(fig_dir, "df_fig1_$(OUTPUT_TAG).csv")
CSV.write(outfile2, df_country, bom=true)
println("  Written to: ", outfile2)

# ---- Generate boxplot data (company level, all companies) ----
println("\nGenerating boxplot data...")
(df_boxplot, g_CDP_c) = generate_boxplot_data(df_q_est, emrio, yr, BASE_PATH)
println("  Total companies: ", nrow(df_boxplot))
println("  Countries: ", length(unique(df_boxplot.ISO_COUNTRY)))
println("  Sum S123: ", round(sum(df_boxplot.S123), digits=2))

# Compute group sizes for summary (same logic as the Python plotting script)
n_reporters = count(!ismissing, df_boxplot.g_S3_CDP_c)
n_in_cdp_no_s3 = count(
    ismissing.(df_boxplot.g_S3_CDP_c) .&
    (df_boxplot.FACTSET_ENTITY_ID .∈ (g_CDP_c.FACTSET_ENTITY_ID,))
)
n_not_in_cdp = nrow(df_boxplot) - n_reporters - n_in_cdp_no_s3
println("  Reporters (have S3): ", n_reporters)
println("  In CDP, no S3:       ", n_in_cdp_no_s3)
println("  Not in CDP:          ", n_not_in_cdp)

outfile3 = joinpath(fig_dir, "df_c_$(OUTPUT_TAG).csv")
CSV.write(outfile3, df_boxplot, bom=true)
println("  Written to: ", outfile3)

# Also copy g_CDP.csv reference for the boxplot Python script
# (the script needs it to classify companies into 3 groups)
outfile4 = joinpath(fig_dir, "g_CDP_$(yr).csv")
CSV.write(outfile4, g_CDP_c, bom=true)
println("  g_CDP reference: ", outfile4)

# ---- Generate country comparison data for appendix (all CDP reporters) ----
println("\nGenerating country comparison data (appendix, all CDP reporters)...")
df_country_appendix = generate_country_data_appendix(df_q_est, emrio, yr, BASE_PATH, IMPORT_PATH)
println("  Companies: ", nrow(df_country_appendix))
println("  Countries: ", length(unique(df_country_appendix.ISO_COUNTRY)))
println("  Sum g_S3_est: ", round(sum(df_country_appendix.g_S3_est), digits=2))
println("  Sum g_S3_CDP: ", round(sum(df_country_appendix.g_S3_CDP_c), digits=2))
println("  Ratio est/CDP: ", round(sum(df_country_appendix.g_S3_est) / sum(df_country_appendix.g_S3_CDP_c), digits=4))

outfile_appendix = joinpath(fig_dir, "df_fig1_country_appendix_$(OUTPUT_TAG).csv")
CSV.write(outfile_appendix, df_country_appendix, bom=true)
println("  Written to: ", outfile_appendix)

println("\nStep 5 complete.")
println("=" ^ 70)
