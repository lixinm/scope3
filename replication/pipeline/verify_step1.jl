# ============================================================================
# verify_step1.jl — Regression check for Step 1 (Sector-level GHG).
#
# Compares new lib output against original output/i_x_g/2015/*.csv.
#
# Usage:
#   cd replication/
#   julia pipeline/verify_step1.jl
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

using DataFrames, DataFramesMeta, CSV, JSON, JLD2, SparseArrays, Statistics

include(joinpath(@__DIR__, "..", "config.jl"))
include(joinpath(@__DIR__, "..", "lib", "utils.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emissions_data.jl"))
include(joinpath(@__DIR__, "..", "lib", "rest_of_world.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_country_io.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emrio.jl"))
include(joinpath(@__DIR__, "..", "lib", "arrange_sector.jl"))

println("=" ^ 60)
println("  Regression Check: Step 1 (Sector-Level GHG)")
println("=" ^ 60)

println("Loading data...")
iea_data = load_iea_data(BASE_PATH)
edgar_data = load_edgar_data(BASE_PATH)
emrio = load_emrio(EMRIO_PATH, IMPORT_PATH, iea_data, YEAR)

orig_dir = joinpath(ORIG_OUTPUT_PATH, "i_x_g", string(YEAR))
countries = [replace(f, ".csv" => "") for f in filter(f -> endswith(f, ".csv"), readdir(orig_dir))]
println("Verifying $(length(countries)) countries...\n")

pass = 0; fail = 0; skip_n = 0
fail_details = String[]

for c in countries
    try
        cio = load_country_io(c, YEAR, IMPORT_PATH, emrio.info_qd)
        new_ghg = compute_sector_ghg(c, YEAR, cio, iea_data, edgar_data)
        orig_ghg = CSV.read(joinpath(orig_dir, "$c.csv"), DataFrame)

        rows_ok = nrow(new_ghg) == nrow(orig_ghg)
        new_sum = sum(new_ghg.GHG6)
        orig_sum = sum(orig_ghg.GHG6)
        sum_ok = isequal(new_sum, orig_sum) || isapprox(new_sum, orig_sum, rtol=1e-8)

        if rows_ok && sum_ok
            global pass += 1; print(".")
        else
            global fail += 1
            push!(fail_details, "$c: rows=$(nrow(new_ghg))/$(nrow(orig_ghg)) GHG6=$(round(new_sum,digits=2))/$(round(orig_sum,digits=2))")
            print("✗")
        end
    catch e
        global skip_n += 1
        push!(fail_details, "$c: ERROR — $(sprint(showerror, e))")
        print("E")
    end
end

println("\n\n" * "=" ^ 60)
println("RESULT: $pass passed, $fail failed, $skip_n errors / $(length(countries)) total")
if !isempty(fail_details)
    println("\nDetails:")
    for d in fail_details; println("  $d"); end
end
if fail == 0 && skip_n == 0
    println("\n✓ ALL $(length(countries)) COUNTRIES VERIFIED IDENTICAL")
end
println("=" ^ 60)
