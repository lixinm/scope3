# ============================================================================
# nos_aggregate.jl — Aggregate NOS (Named Operating Segments) with EMRIO.
#
# Original: module/GHG_footprint/NOS_aggregate.jl (184 lines)
# Paper reference: SI S3 "NOS/OS aggregation", Main Eq. 3-4
#
# This function takes the full EMRIO transaction matrix T and the estimated
# Scope 1 emissions (df_q from Step 2), then:
#   1. Matches subsegments to the df_q Scope 1 data
#   2. Separates NOS (named) vs OS ("other companies") segments
#   3. Builds emission intensity dictionaries for NOS and OS
#   4. Constructs the full emission vector g (length = ncol(T))
#   5. Builds concordance matrices to aggregate unmatched NOS → OS
#   6. Aggregates T, x, g using the concordance matrices
#   7. Computes A = T_agg / diag(x_agg) and f = g_agg / x_agg
#
# The concordance matrices implement Eq. 4 in the main paper:
#   T_agg = C_row × T × C_col
# where unmatched subsegments are mapped to their sector's OS row/column.
# ============================================================================

"""
    nos_aggregate(nt_EMRIO, T, df_q, g_RoW)

Aggregate unmatched NOS subsegments into corresponding OS sectors.

# Arguments
- `nt_EMRIO`  : Raw EMRIO NamedTuple (from JLD2)
- `T`         : Full world transaction matrix (with RoW row/col appended)
- `df_q`      : DataFrame of all Scope 1 estimates (concatenated from Step 2)
                Must have columns: FACTSET_ENTITY_ID_SEGMENT_SUB, ISO_COUNTRY, g_S1
- `g_RoW`     : Rest-of-World total emissions (scalar, SI S1.4 Eq. S1-6)

# Returns a NamedTuple:
- `T_agg`         : Aggregated transaction matrix
- `x_agg`         : Aggregated total output vector (column, 1×n_agg)
- `g_agg`         : Aggregated emission vector (1×n_agg)
- `f`             : Emission intensity f = g_agg / x_agg (1×n_agg)
- `A`             : Technical coefficient matrix A = T_agg .* (1/x_agg)'
- `I_EMRIO`       : Identity matrix of size(A)
- `info_qd_agg`   : Column subsegment attributes after aggregation
- `info_q_agg`    : Row subsegment attributes after aggregation
- `matrix_q_agg`  : Row concordance matrix (for verification/reuse)
- `matrix_qd_agg` : Column concordance matrix (for verification/reuse)
- `x_row_agg`     : Aggregated row output vector
"""
function nos_aggregate(nt_EMRIO, T, df_q, g_RoW)

    # ------------------------------------------------------------------
    # Step 1: Match subsegments to Scope 1 data (df_q)
    # ------------------------------------------------------------------
    # Deep copy to avoid mutating the EMRIO attributes
    info_q  = deepcopy(nt_EMRIO.att_q)   # row subsegments
    info_qd = deepcopy(nt_EMRIO.att_qd)  # col subsegments

    # Inner join: subsegments that have Scope 1 estimates
    dfq_m = innerjoin(
        dropmissing(info_qd, :SECTOR_CODE), df_q,
        on = [:FACTSET_ENTITY_ID_SEGMENT_SUB, :ISO_COUNTRY],
        makeunique = true
    )

    # Anti join: subsegments with SECTOR_CODE but no Scope 1 match
    dfq_nomatch_NOS = antijoin(
        dropmissing(info_qd, :SECTOR_CODE), df_q,
        on = [:FACTSET_ENTITY_ID_SEGMENT_SUB, :ISO_COUNTRY],
        makeunique = true
    )

    # ------------------------------------------------------------------
    # Step 2: Separate NOS (named firms) and OS ("other companies")
    # ------------------------------------------------------------------
    # NOS = Named Operating Segments (actual company subsegments)
    dfq_NOS = @linq dfq_m[dfq_m.PROPER_NAME .!== "other companies", :] |>
        dropmissing(:FF_SALES_modified_estimated_unconsolidated_cpq)

    # OS = Other Sources (sector-level residual subsegments)
    dfq_OS_1 = @linq dfq_m[dfq_m.PROPER_NAME .=== "other companies", :] |>
        dropmissing([:g_S1, :FF_SALES_modified_estimated_unconsolidated_cpq])

    # Unmatched subsegments: assign g_S1 = 0 and treat as OS
    dfq_nomatch_NOS = dfq_nomatch_NOS[:, [
        :FACTSET_ENTITY_ID_SEGMENT_SUB, :SECTOR_CODE, :ISO_COUNTRY,
        :FF_SALES_modified_estimated_unconsolidated_cpq
    ]]
    dfq_nomatch_NOS[!, :g_S1] .= 0.0

    # Combine OS matched + unmatched
    dfq_OS = append!(
        dfq_OS_1[:, [
            :FACTSET_ENTITY_ID_SEGMENT_SUB, :SECTOR_CODE, :ISO_COUNTRY,
            :FF_SALES_modified_estimated_unconsolidated_cpq, :g_S1
        ]],
        dfq_nomatch_NOS
    )

    # Aggregate OS by (SECTOR_CODE, ISO_COUNTRY)
    df_OS = combine(groupby(dfq_OS, [:SECTOR_CODE, :ISO_COUNTRY])) do sdf
        DataFrame(
            FF_SALES_modified_estimated_unconsolidated_cpq =
                sum(sdf.FF_SALES_modified_estimated_unconsolidated_cpq),
            g_S1 = sum(sdf.g_S1)
        )
    end

    # ------------------------------------------------------------------
    # Step 3: Build emission intensity dictionaries
    # ------------------------------------------------------------------
    # NOS intensity: subsegment ID → g_S1 / sales
    DICT_intst_NOS = Dict(zip(
        dfq_NOS.FACTSET_ENTITY_ID_SEGMENT_SUB,
        dfq_NOS.g_S1 ./ dfq_NOS.FF_SALES_modified_estimated_unconsolidated_cpq
    ))

    # OS intensity: (SECTOR_CODE, ISO_COUNTRY) → g_S1 / sales
    DICT_intst_OS = Dict(
        (row[:SECTOR_CODE], row[:ISO_COUNTRY]) =>
            row[:g_S1] / row[:FF_SALES_modified_estimated_unconsolidated_cpq]
        for row in eachrow(df_OS)
    )

    # NOS absolute emissions: subsegment ID → g_S1
    DICT_g_NOS = Dict(zip(
        dfq_NOS.FACTSET_ENTITY_ID_SEGMENT_SUB,
        dfq_NOS.g_S1
    ))

    # OS absolute emissions: (SECTOR_CODE, ISO_COUNTRY) → g_S1
    DICT_g_OS = Dict(
        (row[:SECTOR_CODE], row[:ISO_COUNTRY]) => row[:g_S1]
        for row in eachrow(df_OS)
    )

    # ------------------------------------------------------------------
    # Step 4: Build the full emission vector g
    # ------------------------------------------------------------------
    # For each column subsegment in info_qd, assign emissions based on:
    #   1. Missing SECTOR_CODE (commodity) → 0
    #   2. Matched NOS → use direct g_S1
    #   3. Matched OS intensity → intensity × sales
    #   4. Otherwise → 0
    g = Float32[]
    for row in eachrow(info_qd)
        if row.SECTOR_CODE === missing
            # Commodity sectors: emission = 0
            push!(g, 0.0)
        elseif row.FACTSET_ENTITY_ID_SEGMENT_SUB in keys(DICT_g_NOS)
            # NOS: direct Scope 1 emission
            push!(g, DICT_g_NOS[row.FACTSET_ENTITY_ID_SEGMENT_SUB])
        elseif (row.SECTOR_CODE, row.ISO_COUNTRY) in keys(DICT_intst_OS)
            # OS: emission = intensity × sales
            push!(g, DICT_intst_OS[(row.SECTOR_CODE, row.ISO_COUNTRY)] *
                     row[:FF_SALES_modified_estimated_unconsolidated_cpq])
        else
            push!(g, 0.0)
        end
    end

    # Append RoW emission as the last element (SI S1.4)
    push!(g, g_RoW)

    # ------------------------------------------------------------------
    # Step 5: Mark industry vs commodity subsegments
    # ------------------------------------------------------------------
    info_qd[!, :industry] = ifelse.(ismissing.(info_qd[!, :SECTOR_CODE]), 0, 1)
    info_q[!, :industry]  = ifelse.(ismissing.(info_q[!, :SECTOR_CODE]), 0, 1)

    # ------------------------------------------------------------------
    # Step 6: Build lookup dictionaries for concordance matrix construction
    # ------------------------------------------------------------------
    # Column subsegment → COL_NUM
    DICT_qd_col_num = Dict(
        (row.FACTSET_ENTITY_ID_SEGMENT_SUB, row.ISO_COUNTRY, row.industry) =>
            row.COL_NUM
        for row in eachrow(info_qd)
    )

    # Row subsegment → ROW_NUM
    DICT_q_row_num = Dict(
        (row.FACTSET_ENTITY_ID_SEGMENT_SUB, row.ISO_COUNTRY, row.industry) =>
            row.ROW_NUM
        for row in eachrow(info_q)
    )

    # ------------------------------------------------------------------
    # Step 7: Identify non-matched subsegments that need aggregation to OS
    # ------------------------------------------------------------------
    # Non-matched rows/cols (in info_q/qd but not in df_q)
    df_row_to_agg = antijoin(info_q, df_q, on = :FACTSET_ENTITY_ID_SEGMENT_SUB)
    df_col_to_agg = antijoin(info_qd, df_q, on = :FACTSET_ENTITY_ID_SEGMENT_SUB)

    # Row concordance: map non-matched NOS to their sector's OS
    df_row_to_agg.OS_to_go = [split(s, "_")[end] for s in df_row_to_agg.FACTSET_ENTITY_ID_SEGMENT_SUB]
    # Keep only NOS (not "other companies" which are already OS)
    df_row_to_agg = df_row_to_agg[df_row_to_agg.PROPER_NAME .!== "other companies", :]

    # Build row aggregation dictionary: ROW_NUM → target OS ROW_NUM
    DICT_q_agg = Dict()
    for row1 in eachrow(df_row_to_agg)
        if row1.SECTOR_CODE !== missing
            OS_row1 = string("Others-", row1.SECTOR_CODE, "-S")
        else
            OS_row1 = string("Others-", row1.ROW_SECTOR_CODE, "-S")
        end
        DICT_q_agg[row1.ROW_NUM] = DICT_q_row_num[OS_row1, row1.ISO_COUNTRY, row1.industry]
    end

    # Column concordance: same logic for columns
    df_col_to_agg = df_col_to_agg[df_col_to_agg.PROPER_NAME .!== "other companies", :]

    DICT_qd_agg = Dict()
    for row1 in eachrow(df_col_to_agg)
        if row1.SECTOR_CODE !== missing
            OS_row1 = string("Others-", row1.SECTOR_CODE, "-S")
        else
            OS_row1 = string("Others-", row1.ROW_SECTOR_CODE, "-S")
        end
        DICT_qd_agg[row1.COL_NUM] = DICT_qd_col_num[OS_row1, row1.ISO_COUNTRY, row1.industry]
    end

    # ------------------------------------------------------------------
    # Step 8: Build concordance matrices (Main Eq. 4)
    # ------------------------------------------------------------------
    n_row = size(T, 1)
    n_col = size(T, 2)

    # Row concordance matrix: start with identity, remap aggregated rows
    matrix = spdiagm(0 => ones(n_row))
    for (key, value) in DICT_q_agg
        matrix[key, key] = 0       # Zero out original position
        matrix[value, key] = 1     # Map to OS position
    end
    row_sums = vec(sum(matrix, dims=2))
    rows_to_keep = findall(x -> x != 0, row_sums)
    matrix_q_agg = matrix[rows_to_keep, :]

    # Column concordance matrix: same logic, transposed
    matrix = spdiagm(0 => ones(n_col))
    for (key, value) in DICT_qd_agg
        matrix[key, key] = 0
        matrix[value, key] = 1
    end
    col_sums = vec(sum(matrix, dims=2))
    cols_to_keep = findall(x -> x != 0, col_sums)
    matrix_qd_agg = transpose(matrix[cols_to_keep, :])

    # ------------------------------------------------------------------
    # Step 9: Apply aggregation (Main Eq. 4)
    #   T_agg = C_row × T × C_col
    # ------------------------------------------------------------------
    T_agg = matrix_q_agg * T * matrix_qd_agg

    # Aggregate column output vector x
    xqd = deepcopy(nt_EMRIO.EMRIO_xqd)
    x = hcat(xqd, nt_EMRIO.xRoWd)
    x_agg = x * matrix_qd_agg

    # Aggregate emission vector g
    g_agg = transpose(g) * matrix_qd_agg

    # ------------------------------------------------------------------
    # Step 10: Compute technical coefficients A and emission intensity f
    # ------------------------------------------------------------------
    # A = T_agg / diag(x_agg)  (element-wise column scaling)
    x_inv = replace(vec(inv.(x_agg)), NaN => 0.0)
    A = replace(T_agg .* transpose(x_inv), NaN => 0, Inf => 0, -Inf => 0)

    # Identity matrix for Leontief calculation
    I_EMRIO = sparse(I, size(A, 1), size(A, 2))

    # Emission intensity vector: f = g / x (SI S3)
    f = replace(g_agg ./ x_agg, NaN => 0, Inf => 0, -Inf => 0)

    # ------------------------------------------------------------------
    # Step 11: Aggregate row output vector (for info_q_agg)
    # ------------------------------------------------------------------
    x_row = deepcopy(nt_EMRIO.EMRIO_xq)
    x_row = vcat(x_row, deepcopy(nt_EMRIO.xRoW))
    x_row_agg = matrix_q_agg * x_row

    # ------------------------------------------------------------------
    # Step 12: Build aggregated attribute DataFrames
    # ------------------------------------------------------------------
    # Filter out aggregated columns (keep only non-remapped subsegments)
    info_qd_agg = filter(row -> !(row.COL_NUM in keys(DICT_qd_agg)), info_qd)
    info_qd_agg.x_qd  = vec(x_agg)[1:end-1]
    info_qd_agg.g_agg  = vec(g_agg)[1:end-1]

    # Row attributes (refresh from original nt_EMRIO to avoid mutation)
    info_q = nt_EMRIO.att_q
    info_q_agg = filter(row -> !(row.ROW_NUM in keys(DICT_q_agg)), info_q)
    info_q_agg.x_q = vec(x_row_agg)[1:end-1]

    return (
        T_agg         = T_agg,
        x_agg         = x_agg,
        g_agg         = g_agg,
        f             = f,
        A             = A,
        I_EMRIO       = I_EMRIO,
        info_qd_agg   = info_qd_agg,
        info_q_agg    = info_q_agg,
        matrix_q_agg  = matrix_q_agg,
        matrix_qd_agg = matrix_qd_agg,
        x_row_agg     = x_row_agg,
    )
end
