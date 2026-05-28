# ============================================================================
# verify_step4.jl — Verify Step 4 output against original q_est CSV.
#
# Compares replication/output/{YEAR}/q_est_{OUTPUT_TAG}.csv against
# the original output/{YEAR}/q_est_{OUTPUT_TAG}.csv.
#
# Checks: row count, column names, join on FACTSET_ENTITY_ID_SEGMENT_SUB,
#          numerical closeness of g_S1, g_S2_EMRIO, g_S23_EMRIO, g_S3_T.
# ============================================================================

println("=" ^ 70)
println("Verify Step 4: q_est output comparison")
println("=" ^ 70)

using CSV, DataFrames

include(joinpath(@__DIR__, "..", "config.jl"))

yr = YEAR

# ---- Load both CSVs ----
new_file = joinpath(OUTPUT_PATH, string(yr), "q_est_$(OUTPUT_TAG).csv")
orig_file = joinpath(ORIG_OUTPUT_PATH, string(yr), "q_est_$(OUTPUT_TAG).csv")

println("New:  ", new_file)
println("Orig: ", orig_file)

if !isfile(new_file)
    error("New file not found: $new_file")
end
if !isfile(orig_file)
    error("Original file not found: $orig_file")
end

df_new  = DataFrame(CSV.File(new_file))
df_orig = DataFrame(CSV.File(orig_file))

println("  New rows:  ", nrow(df_new))
println("  Orig rows: ", nrow(df_orig))

# ---- Check columns ----
cols_to_check = [:g_S1, :g_S2_EMRIO, :g_S23_EMRIO, :g_S3_T]
for c in cols_to_check
    if !(string(c) in names(df_new))
        error("Column $c missing from new output")
    end
    if !(string(c) in names(df_orig))
        error("Column $c missing from original output")
    end
end

# ---- Sort both DataFrames by subsegment ID for row-aligned comparison ----
sort!(df_new, :FACTSET_ENTITY_ID_SEGMENT_SUB)
sort!(df_orig, :FACTSET_ENTITY_ID_SEGMENT_SUB)

if nrow(df_new) != nrow(df_orig)
    @warn "Row count mismatch: new $(nrow(df_new)) vs original $(nrow(df_orig))"
end

# Verify subsegment IDs match after sorting
if df_new.FACTSET_ENTITY_ID_SEGMENT_SUB != df_orig.FACTSET_ENTITY_ID_SEGMENT_SUB
    @warn "Subsegment IDs do not match exactly after sorting"
end

# ---- Compare numerical columns ----
all_pass = true
for col in cols_to_check
    v_new  = Float64.(df_new[:, col])
    v_orig = Float64.(df_orig[:, col])

    # Count exact matches, NaN matches, and close matches
    n_exact = 0
    n_nan   = 0
    n_close = 0
    n_fail  = 0
    max_reldiff = 0.0

    for i in 1:length(v_new)
        if isequal(v_new[i], v_orig[i])
            n_exact += 1
        elseif isnan(v_new[i]) && isnan(v_orig[i])
            n_nan += 1
        elseif isapprox(v_new[i], v_orig[i], rtol=1e-6, atol=1e-10)
            n_close += 1
        else
            n_fail += 1
            if v_orig[i] != 0.0
                rd = abs(v_new[i] - v_orig[i]) / abs(v_orig[i])
                max_reldiff = max(max_reldiff, rd)
            end
        end
    end

    status = n_fail == 0 ? "PASS" : "FAIL"
    if n_fail > 0
        global all_pass = false
    end

    println("  $col: $status (exact=$n_exact, close=$n_close, nan=$n_nan, fail=$n_fail",
            n_fail > 0 ? ", max_reldiff=$(round(max_reldiff, sigdigits=4))" : "", ")")
end

println()
if all_pass
    println("✓ Step 4 verification PASSED — all columns match original output.")
else
    println("✗ Step 4 verification FAILED — see details above.")
end
println("=" ^ 70)
