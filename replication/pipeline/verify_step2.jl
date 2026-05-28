# ============================================================================
# verify_step2.jl — Regression check for Step 2 (Scope 1 subsegments).
#
# Compares the output of the new replication lib against the original
# output files in output/g_S1_2015/*.csv.
#
# Usage:
#   cd replication/
#   julia pipeline/verify_step2.jl
#
# Expected result: ALL countries match (rows + g_S1 sum, rtol=1e-6).
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
println("  Regression Check: Step 2 (Scope 1 Subsegments)")
println("=" ^ 60)

# ---- Load all source data ----
println("Loading IEA...")
iea_data = load_iea_data(BASE_PATH)
println("Loading EMRIO...")
emrio = load_emrio(EMRIO_PATH, IMPORT_PATH, iea_data, YEAR)
println("Loading CDP...")
cdp_data = load_cdp_data(BASE_PATH)
println("Loading METI...")
meti_data = load_meti_data(BASE_PATH, YEAR)

# ---- Find all countries with original output ----
orig_dir = joinpath(ORIG_OUTPUT_PATH, "g_S1_$(YEAR)")
orig_files = filter(f -> endswith(f, ".csv"), readdir(orig_dir))
countries = [replace(f, ".csv" => "") for f in orig_files]
println("\nVerifying $(length(countries)) countries against original output...\n")

# ---- Compare each country ----
pass = 0
fail = 0
skip_n = 0
fail_details = String[]

for c in countries
    try
        # Compute using new lib
        cio = load_country_io(c, YEAR, IMPORT_PATH, emrio.info_qd)
        c_meti = (c == "JPN") ? meti_data : nothing
        # Use ORIG_OUTPUT_PATH so verify can read Step 1 output without
        # requiring pipeline Step 1 to have been run into replication/output/
        new_q = generate_scope1_country(c, YEAR, cio, emrio, cdp_data, c_meti, BASE_PATH, ORIG_OUTPUT_PATH, GHG_TYPE)

        # Load original
        orig_q = CSV.read(joinpath(orig_dir, "$(c).csv"), DataFrame)

        # Check 1: row count
        rows_ok = nrow(new_q) == nrow(orig_q)

        # Check 2: g_S1 sum (handle NaN with isequal)
        new_sum = sum(skipmissing(new_q.g_S1))
        orig_sum = sum(skipmissing(orig_q.g_S1))
        sum_ok = isequal(new_sum, orig_sum) || isapprox(new_sum, orig_sum, rtol=1e-6)

        if rows_ok && sum_ok
            global pass += 1
            print(".")  # progress dot
        else
            global fail += 1
            detail = "$c: rows=$(nrow(new_q))/$(nrow(orig_q)) g_S1=$(round(new_sum,digits=2))/$(round(orig_sum,digits=2))"
            push!(fail_details, detail)
            print("✗")
        end
    catch e
        global skip_n += 1
        push!(fail_details, "$c: ERROR — $(sprint(showerror, e))")
        print("E")
    end
end

# ---- Report ----
println("\n\n" * "=" ^ 60)
println("RESULT: $pass passed, $fail failed, $skip_n errors / $(length(countries)) total")

if !isempty(fail_details)
    println("\nDetails:")
    for d in fail_details
        println("  $d")
    end
end

if fail == 0 && skip_n == 0
    println("\n✓ ALL $(length(countries)) COUNTRIES VERIFIED IDENTICAL")
else
    println("\n✗ SOME CHECKS FAILED — investigate above")
end
println("=" ^ 60)
