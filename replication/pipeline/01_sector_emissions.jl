# ============================================================================
# 01_sector_emissions.jl — Pipeline Step 1: Sector-level GHG emissions.
#
# Paper reference: SI S1 (Eq. S1-2, S1-4, S1-5)
#
# For each country in the EMRIO, computes sector-level GHG emissions
# by combining IEA CO₂ and EDGAR non-CO₂ data, then writes per-country
# CSV files to output/i_x_g/{YEAR}/.
#
# Input:  IEA, EDGAR, country IO data (all proprietary)
# Output: output/i_x_g/{YEAR}/{country}.csv
#         Columns: SECTOR_CODE, x, CO2, non_CO2, GHG6, ISO_COUNTRY, CO2_EDGAR
#
# This step is self-contained: it loads all required data internally.
# No dependency on prior pipeline steps.
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
using DataFrames, DataFramesMeta, CSV, JSON, JLD2, SparseArrays, Statistics

include(joinpath(@__DIR__, "..", "config.jl"))
include(joinpath(@__DIR__, "..", "lib", "utils.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emissions_data.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_country_io.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emrio.jl"))
include(joinpath(@__DIR__, "..", "lib", "rest_of_world.jl"))
include(joinpath(@__DIR__, "..", "lib", "arrange_sector.jl"))

println("=" ^ 60)
println("  Step 1: Sector-Level GHG Emissions (SI S1)")
println("=" ^ 60)

# ---- Load source data ----
println("Loading IEA data...")
iea_data = load_iea_data(BASE_PATH)
println("Loading EDGAR data...")
edgar_data = load_edgar_data(BASE_PATH)

# ---- Load EMRIO (to get country list and info_qd) ----
println("Loading EMRIO...")
emrio = load_emrio(EMRIO_PATH, IMPORT_PATH, iea_data, YEAR)

# ---- Determine country list ----
if COUNTRY_LIST_OVERRIDE === nothing
    country_list = emrio.country_list
else
    country_list = COUNTRY_LIST_OVERRIDE
end
println("Processing $(length(country_list)) countries...")

# ---- Ensure output directory exists ----
outdir = joinpath(OUTPUT_PATH, "i_x_g", string(YEAR))
mkpath(outdir)

# ---- Process each country ----
results = String[]    # collect successfully processed countries
failures = String[]   # collect failed countries

for country in country_list
    try
        # Load country-specific IO data
        country_io = load_country_io(country, YEAR, IMPORT_PATH, emrio.info_qd)

        # Compute sector GHG (SI S1.1-S1.3, Eq. S1-2, S1-4, S1-5)
        i_x_g = compute_sector_ghg(country, YEAR, country_io, iea_data, edgar_data)

        # Write output
        outpath = joinpath(outdir, "$(country).csv")
        CSV.write(outpath, i_x_g, bom = true)
        push!(results, country)
    catch e
        println("  WARNING: $country failed — $(sprint(showerror, e))")
        push!(failures, country)
    end
end

# ---- Validation summary ----
println("\n=== Step 1 Validation ===")
println("  Countries processed: $(length(results))")
println("  Countries failed:    $(length(failures))")

# Spot-check a few countries
for c in ["USA", "JPN", "GBR"]
    f = joinpath(outdir, "$c.csv")
    if isfile(f)
        df = CSV.read(f, DataFrame)
        println("  $c: $(nrow(df)) sectors, GHG6 sum = $(round(sum(df.GHG6), digits=2))")
    end
end

println("\nStep 1 complete. Output: $outdir")
