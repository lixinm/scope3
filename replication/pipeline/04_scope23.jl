# ============================================================================
# 04_scope23.jl — Step 4: Leontief inverse & Scope 2/3 computation.
#
# Original: controller/main.ipynb Cells 5-9
# Paper reference: Main Eq. 5-8, SI S4-S5
#
# This step:
#   1. Loads intermediate results from Step 3 (or recomputes if needed)
#   2. Computes Leontief inverse L = (I - A)^{-1}
#   3. Identifies energy sectors per country
#   4. Computes Scope 2+3 (g_S23), Scope 2 (g_S2), Scope 3 (g_S3)
#   5. Outputs q_est_{OUTPUT_TAG}.csv
#
# Prerequisites: Step 3 output (emrio_agg_{OUTPUT_TAG}.jld2)
# Output: OUTPUT_PATH/{YEAR}/q_est_{OUTPUT_TAG}.csv
# ============================================================================

# NOTICE: This file depends on external files under import.
# Required import dependencies:
#   - <DATA_ROOT>/IO/EIO/EMRIO/2015/20240228.jld2
#     (only if intermediate Step 3 file is missing and recomputation is needed)
#   - <DATA_ROOT>/IO/EIO/DEIO/{COUNTRY}/2015/data_20240224.jld2
#     (71 countries; loaded by compute_scope23 → identify_energy_sectors)
#   - <DATA_ROOT>/FactSet/Financial/ff_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Shipping/sc_ship_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Supplychain/ent_scr_sec_entity.txt
#   - <DATA_ROOT>/tmp/nt_arranged_base_segment_20231210.jld2
#     (FactSet and tmp files only if intermediate Step 3 file is missing)
# Please ensure these files are available when running this replication script.

println("=" ^ 70)
println("Step 4: Leontief Inverse & Scope 2/3 Computation")
println("=" ^ 70)

# ---- Load dependencies ----
using CSV, DataFrames, DataFramesMeta, JSON, JLD2, SparseArrays, LinearAlgebra, Statistics

include(joinpath(@__DIR__, "..", "config.jl"))
include(joinpath(@__DIR__, "..", "lib", "utils.jl"))
include(joinpath(@__DIR__, "..", "lib", "rest_of_world.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emissions_data.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_emrio.jl"))
include(joinpath(@__DIR__, "..", "lib", "load_country_io.jl"))
include(joinpath(@__DIR__, "..", "lib", "nos_aggregate.jl"))
include(joinpath(@__DIR__, "..", "lib", "scope23_leontief.jl"))

yr = YEAR

const PUBLIC_CHECKPOINT_DIR = joinpath(REPLICATION_DIR, "public_data", "checkpoints")

function rounded_density(M; digits::Int=4)
    nr, nc = size(M)
    total = nr * nc
    total == 0 && return missing
    return round(100 * nnz(M) / total; digits=digits)
end

function finite_check(x)
    vals = collect(skipmissing(vec(x)))
    return all(isfinite, vals)
end

function rounded_sum(x; digits::Int=6)
    vals = [Float64(v) for v in skipmissing(vec(x)) if isfinite(v)]
    isempty(vals) && return missing
    return round(sum(vals); digits=digits)
end

function finite_vector_sum(x; digits::Int=6)
    vals = [Float64(v) for v in skipmissing(vec(x)) if isfinite(v)]
    isempty(vals) && return missing
    return round(sum(vals); digits=digits)
end

function rounded_quantile(x, p; digits::Int=6)
    vals = sort([Float64(v) for v in skipmissing(vec(x)) if isfinite(v)])
    isempty(vals) && return missing
    return round(quantile(vals, p); digits=digits)
end

function rounded_count(n; base::Int=100)
    return Int(base * round(Int, n / base))
end

function selected_inverse_check_columns(n::Int)
    first_cols = collect(1:min(5, n))
    mid = max(1, min(n, fld(n, 2)))
    mid_start = max(1, mid - 2)
    mid_stop = min(n, mid_start + 4)
    mid_cols = collect(mid_start:mid_stop)
    last_cols = collect(max(1, n - 4):n)
    return sort(unique(vcat(first_cols, mid_cols, last_cols)))
end

function inverse_residual_summary(IA, L)
    n = size(IA, 1)
    cols = selected_inverse_check_columns(n)
    residual = IA * L[:, cols]
    for (j, col) in enumerate(cols)
        residual[col, j] -= 1.0
    end
    vals = abs.(vec(residual))
    return (
        n_checked_columns = length(cols),
        max_abs_residual = round(maximum(vals); digits=12),
        median_abs_residual = round(median(vals); digits=12),
    )
end

function vector_summary(stage, artifact, v; active_count=nothing, note="")
    vals = [Float64(x) for x in skipmissing(vec(v)) if isfinite(x)]
    n_neg = count(x -> x < 0, vals)
    return (
        stage = stage,
        artifact = artifact,
        rows = missing,
        cols = missing,
        length = length(vals),
        rounded_active_count = active_count === nothing ? missing : rounded_count(active_count),
        total = isempty(vals) ? missing : round(sum(vals); digits=6),
        min = isempty(vals) ? missing : round(minimum(vals); digits=6),
        p50 = isempty(vals) ? missing : rounded_quantile(vals, 0.50),
        p90 = isempty(vals) ? missing : rounded_quantile(vals, 0.90),
        p99 = isempty(vals) ? missing : rounded_quantile(vals, 0.99),
        max = isempty(vals) ? missing : round(maximum(vals); digits=6),
        n_negative = n_neg,
        check_value = missing,
        note = note,
    )
end

function write_public_step4_trace_checkpoints(agg, result, df_q_est; output_dir::AbstractString=PUBLIC_CHECKPOINT_DIR)
    mkpath(output_dir)

    T_agg = agg.T_agg
    f = agg.f
    A = agg.A
    I_EMRIO = agg.I_EMRIO
    IA = I_EMRIO - A
    L = result.t_Leon_full
    e_g23 = result.e_g23
    f_ener = result.f_ener

    loaded = DataFrame(
        stage = fill("load_step3_aggregate", 7),
        object = ["T_agg", "f", "A", "I_EMRIO", "info_qd_agg", "info_q_agg", "g_agg"],
        rows = [size(T_agg, 1), missing, size(A, 1), size(I_EMRIO, 1), nrow(agg.info_qd_agg), nrow(agg.info_q_agg), missing],
        cols = [size(T_agg, 2), missing, size(A, 2), size(I_EMRIO, 2), ncol(agg.info_qd_agg), ncol(agg.info_q_agg), missing],
        length = [missing, length(f), missing, missing, missing, missing, length(agg.g_agg)],
        orientation = ["matrix", "row_vector", "matrix", "matrix", "table", "table", "vector"],
        source_step = fill("03_emrio_aggregate.jl", 7),
        public_release_status = fill("aggregate diagnostics only; object not released", 7),
        note = [
            "Aggregated transaction matrix loaded by Step 4.",
            "Emission intensity row vector used in e = fL.",
            "Technical coefficient matrix used to construct I - A.",
            "Identity matrix matching A.",
            "Destination/subsegment metadata; row-level metadata not released.",
            "Source/subsegment metadata; row-level metadata not released.",
            "Aggregated Scope 1 vector loaded by Step 4.",
        ],
    )
    CSV.write(joinpath(output_dir, "11_step4_loaded_objects.csv"), loaded)

    diag_IA = diag(IA)
    matrix_diagnostics = DataFrame(
        stage = ["load", "load", "load", "construct"],
        artifact = ["T_agg", "A", "I_EMRIO", "I_minus_A"],
        rows = [size(T_agg, 1), size(A, 1), size(I_EMRIO, 1), size(IA, 1)],
        cols = [size(T_agg, 2), size(A, 2), size(I_EMRIO, 2), size(IA, 2)],
        rounded_density_pct = [rounded_density(T_agg), rounded_density(A), rounded_density(I_EMRIO), rounded_density(IA)],
        finite_value_check = [finite_check(nonzeros(T_agg)), finite_check(nonzeros(A)), true, finite_check(nonzeros(IA))],
        sum_total = [rounded_sum(nonzeros(T_agg)), rounded_sum(nonzeros(A)), rounded_sum(nonzeros(I_EMRIO)), rounded_sum(nonzeros(IA))],
        diag_min = [missing, missing, 1.0, round(minimum(diag_IA); digits=6)],
        diag_median = [missing, missing, 1.0, rounded_quantile(diag_IA, 0.50)],
        diag_max = [missing, missing, 1.0, round(maximum(diag_IA); digits=6)],
        note = [
            "No matrix entries or nonzero-value quantiles released.",
            "No matrix entries or nonzero-value quantiles released.",
            "Identity matrix diagnostic.",
            "Constructed as I_EMRIO - A; no matrix entries released.",
        ],
    )
    CSV.write(joinpath(output_dir, "12_step4_matrix_construction.csv"), matrix_diagnostics)

    residual = inverse_residual_summary(IA, L)
    trace = DataFrame([
        (
            stage = "construct_IA",
            artifact = "I_minus_A",
            rows = size(IA, 1),
            cols = size(IA, 2),
            length = missing,
            rounded_active_count = rounded_count(nnz(IA)),
            total = missing,
            min = missing,
            p50 = missing,
            p90 = missing,
            p99 = missing,
            max = missing,
            n_negative = missing,
            check_value = missing,
            note = "Sparse diagnostic only; matrix cells not released.",
        ),
        (
            stage = "compute_inverse",
            artifact = "Leontief_inverse",
            rows = size(L, 1),
            cols = size(L, 2),
            length = missing,
            rounded_active_count = missing,
            total = missing,
            min = missing,
            p50 = missing,
            p90 = missing,
            p99 = missing,
            max = residual.max_abs_residual,
            n_negative = missing,
            check_value = residual.median_abs_residual,
            note = "Dense inverse not released; max=maximum absolute residual and check_value=median absolute residual for fixed checked columns.",
        ),
        vector_summary("compute_multiplier_e_after_sut_zeroing", "emission_multiplier_after_sut_zeroing", e_g23; note="Computed as e = fL, then SUT rows are set to zero before propagation; row-level vector not released."),
        vector_summary("build_f_ener", "energy_intensity_vector", f_ener; active_count=count(!iszero, f_ener), note="Aggregate summary only; row-level vector not released."),
        vector_summary("propagate_scope23", "scope2plus3_output", df_q_est.g_S23_EMRIO; note="Aggregate summary of Step 4 output."),
        vector_summary("extract_scope2", "scope2_output", df_q_est.g_S2_EMRIO; note="Aggregate summary of Step 4 output."),
        vector_summary("compute_scope3_residual", "scope3_output", df_q_est.g_S3_T; note="Aggregate summary of Step 4 output."),
    ])
    CSV.write(joinpath(output_dir, "13_step4_leontief_inverse_trace.csv"), trace)

    total_s1 = finite_vector_sum(df_q_est.g_S1)
    total_s2 = finite_vector_sum(df_q_est.g_S2_EMRIO)
    total_s23 = finite_vector_sum(df_q_est.g_S23_EMRIO)
    total_s3 = finite_vector_sum(df_q_est.g_S3_T)
    equation_checks = DataFrame(
        check = [
            "scope1_total",
            "scope2_total",
            "scope23_total",
            "scope3_total",
            "scope23_minus_scope2_minus_scope3_abs",
            "n_negative_multiplier_e_g23",
            "n_negative_scope3_total",
            "inverse_residual_checked_columns",
            "inverse_residual_max_abs",
            "inverse_residual_median_abs",
        ],
        value = [
            total_s1,
            total_s2,
            total_s23,
            total_s3,
            round(abs(total_s23 - total_s2 - total_s3); digits=12),
            count(x -> x < 0.0, vec(e_g23)),
            count(x -> x < 0.0, df_q_est.g_S3_T),
            residual.n_checked_columns,
            residual.max_abs_residual,
            residual.median_abs_residual,
        ],
        equation = [
            "finite_sum(g_S1)",
            "finite_sum(g_S2)",
            "finite_sum(g_S23)",
            "finite_sum(g_S3)",
            "abs(finite_sum(g_S23) - finite_sum(g_S2) - finite_sum(g_S3))",
            "count(e_g23 < 0)",
            "count(g_S3 < 0)",
            "fixed first/middle/last columns",
            "max(abs((I-A)L_selected - I_selected))",
            "median(abs((I-A)L_selected - I_selected))",
        ],
        note = [
            "Aggregate finite Scope 1 output from Step 4.",
            "Aggregate finite Scope 2 output from Step 4.",
            "Aggregate finite Scope 2+3 output from Step 4.",
            "Aggregate finite Scope 3 residual from Step 4.",
            "Numerical decomposition check.",
            "Multiplier-vector numerical diagnostic after SUT zeroing.",
            "Scope 3 output diagnostic.",
            "Deterministic inverse check.",
            "Deterministic inverse check.",
            "Deterministic inverse check.",
        ],
    )
    CSV.write(joinpath(output_dir, "14_step4_scope23_equation_checks.csv"), equation_checks)

    println("Public Step 4 trace checkpoints written to: ", output_dir)
end


# ---- Load intermediate results from Step 3 ----
agg_file = joinpath(OUTPUT_PATH, string(yr), "emrio_agg_$(OUTPUT_TAG).jld2")
if isfile(agg_file)
    println("Loading intermediate results from Step 3...")
    @load agg_file agg emrio_att_r emrio_country_list emrio_info_qd
    println("  Loaded: T_agg $(size(agg.T_agg)), f length $(length(agg.f))")
    # Reconstruct a minimal nt_EMRIO stub with just att_r
    # (compute_scope23 only accesses nt_EMRIO.att_r for SUT/pp checks)
    nt_EMRIO_stub    = (att_r = emrio_att_r,)
    country_list_ref = emrio_country_list
    info_qd_ref      = emrio_info_qd
else
    # Recompute if intermediate file is missing
    println("Intermediate file not found, recomputing Step 3...")
    iea_data = load_iea_data(BASE_PATH)
    emrio = load_emrio(EMRIO_PATH, IMPORT_PATH, iea_data, yr; version=EMRIO_VERSION)

    g_S1_dir = joinpath(OUTPUT_PATH, "g_S1_$(yr)")
    files_yr = [f for f in readdir(g_S1_dir) if occursin(r"\.csv$", f)]
    dfs = [DataFrame(CSV.File(joinpath(g_S1_dir, f))) for f in files_yr]
    df_q = vcat(dfs...)

    agg = nos_aggregate(emrio.nt_EMRIO, emrio.T, df_q, emrio.g_RoW)
    nt_EMRIO_stub    = emrio.nt_EMRIO
    country_list_ref = emrio.country_list
    info_qd_ref      = emrio.info_qd
end

# ---- Compute Scope 2/3 ----
println("Computing Scope 2/3...")
result = compute_scope23(
    agg,
    nt_EMRIO_stub,
    country_list_ref,
    IMPORT_PATH,
    yr,
    info_qd_ref    # original info_qd (before aggregation)
)

df_q_est = result.df_q_est

# ---- Write public-safe Step 4 trace checkpoints ----
write_public_step4_trace_checkpoints(agg, result, df_q_est)

# ---- Summary statistics ----
println("\n--- Summary ---")
println("  Total subsegments: ", nrow(df_q_est))
println("  Scope 1 total:  ", round(finite_vector_sum(df_q_est.g_S1), digits=2))
println("  Scope 2 total:  ", round(finite_vector_sum(df_q_est.g_S2_EMRIO), digits=2))
println("  Scope 23 total: ", round(finite_vector_sum(df_q_est.g_S23_EMRIO), digits=2))
println("  Scope 3 total:  ", round(finite_vector_sum(df_q_est.g_S3_T), digits=2))
n_neg = count(x -> x < 0.0, df_q_est.g_S3_T)
println("  Negative Scope 3: $n_neg subsegments")

# ---- Write output ----
output_yr_dir = joinpath(OUTPUT_PATH, string(yr))
mkpath(output_yr_dir)
outfile = joinpath(output_yr_dir, "q_est_$(OUTPUT_TAG).csv")
CSV.write(outfile, df_q_est, bom=true)
println("\nOutput written to: ", outfile)

println("\nStep 4 complete.")
println("=" ^ 70)
