# ============================================================================
# 02_scope1_subsegments.jl — Pipeline Step 2: Subsegment-level Scope 1.
#
# Paper reference: SI S2 (Eq. S2-1 to S2-20) + Main text Eq. 1-2
#
# For each country, estimates subsegment-level Scope 1 emissions by
# combining CDP, EPA (USA), and METI (JPN) data with sector-level GHG.
# Computes OS (Other Sources) residual for each sector.
#
# Input:  output/i_x_g/{YEAR}/*.csv (Step 1 output),
#         CDP/METI/EPA data, EMRIO segment data (all proprietary)
# Output: output/g_S1_{YEAR}/{country}.csv
#         Columns: FACTSET_ENTITY_ID_SEGMENT_SUB, g_S1, SOURCE_S1, ISO_COUNTRY
#
# This step is self-contained: loads all required data internally.
# ============================================================================
#
# NOTICE: This file depends on external files under import.
# Required import dependencies:
#   - <DATA_ROOT>/IO/EIO/EMRIO/2015/20240228.jld2
#   - <DATA_ROOT>/IO/EIO/DEIO/{COUNTRY}/2015/data_20240224.jld2
#     (71 countries; see config.jl for the full list)
#   - <DATA_ROOT>/FactSet/Financial/ff_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Shipping/sc_ship_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Supplychain/ent_scr_sec_entity.txt
#   - <DATA_ROOT>/tmp/nt_arranged_base_segment_20231210.jld2
# Please ensure these files are available when running this replication script.

# ---- Setup ----
using DataFrames, DataFramesMeta, CSV, JSON, JLD2, SparseArrays
using Statistics, XLSX, Unicode

include(joinpath(@__DIR__, "..", "config.jl"))
include(joinpath(@__DIR__, "..", "lib", "utils.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emissions_data.jl"))
include(joinpath(@__DIR__, "..", "lib", "rest_of_world.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_country_io.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emrio.jl"))
include(joinpath(@__DIR__, "..", "lib", "arrange_sector.jl"))
include(joinpath(@__DIR__, "..", "lib", "scope1_cdp.jl"))
include(joinpath(@__DIR__, "..", "lib", "scope1_epa.jl"))
include(joinpath(@__DIR__, "..", "lib", "scope1_generate.jl"))

println("=" ^ 60)
println("  Step 2: Subsegment-Level Scope 1 Emissions (SI S2)")
println("=" ^ 60)

# ---- Load source data ----
println("Loading IEA data...")
iea_data = load_iea_data(BASE_PATH)
println("Loading EMRIO...")
emrio = load_emrio(EMRIO_PATH, IMPORT_PATH, iea_data, YEAR)
println("Loading CDP data...")
cdp_data = load_cdp_data(BASE_PATH)
println("Loading METI data (Japan)...")
meti_data = load_meti_data(BASE_PATH, YEAR)

# ---- Determine country list ----
if COUNTRY_LIST_OVERRIDE === nothing
    country_list = emrio.country_list
else
    country_list = COUNTRY_LIST_OVERRIDE
end
println("Processing $(length(country_list)) countries...")

# ---- Ensure output directory exists ----
outdir = joinpath(OUTPUT_PATH, "g_S1_$(YEAR)")
mkpath(outdir)

# ---- Process each country ----
results = String[]
failures = String[]

for country in country_list
    try
        # Load country-specific IO data
        country_io = load_country_io(country, YEAR, IMPORT_PATH, emrio.info_qd)

        # Determine METI data for Japan
        country_meti = (country == "JPN") ? meti_data : nothing

        # Generate subsegment Scope 1 (SI S2.1-S2.3 + Eq. 2)
        df_q = generate_scope1_country(
            country, YEAR, country_io, emrio, cdp_data,
            country_meti, BASE_PATH, OUTPUT_PATH, GHG_TYPE,
        )

        # Write output
        outpath = joinpath(outdir, "$(country).csv")
        CSV.write(outpath, df_q, bom = true)
        push!(results, country)
    catch e
        println("  WARNING: $country failed — $(sprint(showerror, e))")
        push!(failures, country)
    end
end

# ---- Validation summary ----
println("\n=== Step 2 Validation ===")
println("  Countries processed: $(length(results))")
println("  Countries failed:    $(length(failures))")

for c in ["USA", "JPN", "GBR"]
    f = joinpath(outdir, "$c.csv")
    if isfile(f)
        df = CSV.read(f, DataFrame)
        println("  $c: $(nrow(df)) subsegments, g_S1 sum = $(round(sum(skipmissing(df.g_S1)), digits=2))")
    end
end

println("\nStep 2 complete. Output: $outdir")
