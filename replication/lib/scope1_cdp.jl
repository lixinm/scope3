# ============================================================================
# scope1_cdp.jl — CDP-based Scope 1 estimation at subsegment level.
#
# Original: module/GHG_estimate/q_S1_estimate.jl
# Paper reference: SI S2.1 (Eq. S2-1 to S2-5)
#
# 4-step methodology:
#   Step 1 (Eq. S2-2): Company → segment allocation using sales × intensity
#   Step 2 (Eq. S2-3): Consolidated → unconsolidated conversion
#   Step 3 (Eq. S2-4): Segment → subsegment allocation
#   Step 4 (Eq. S2-5): Cap at domestic region breakdown from CDP
# ============================================================================

"""
    estimate_scope1_cdp(country, yr, sales_cpq, cdp_data, df_p_all,
                        col_SIC, i_x_g, DICT_intst, GHG_type)

Estimate subsegment-level Scope 1 emissions using CDP data.

Returns `df_NOS` DataFrame with columns:
  FACTSET_ENTITY_ID_SEGMENT_SUB, SECTOR_CODE, g_S1,
  FF_SALES_modified_estimated_unconsolidated_cpq, SOURCE_S1
"""
function estimate_scope1_cdp(
    country::String, yr::Int,
    sales_cpq, cdp_data, df_p_all,
    col_SIC, i_x_g, DICT_intst, GHG_type::String,
)
    g_CDP_c = cdp_data.g_CDP_c
    g_CDP_r = cdp_data.g_CDP_r

    # --- Match EMRIO companies with CDP reporters ---
    df_CDP_matched = innerjoin(
        sales_cpq[:, [:FACTSET_ENTITY_ID]],
        g_CDP_c[g_CDP_c.accounting_year .=== yr, :],
        on = :FACTSET_ENTITY_ID,
    )
    DICT_c_CDP_matched = Dict(zip(df_CDP_matched.FACTSET_ENTITY_ID, df_CDP_matched.g_S1))

    # --- Segment-level information ---
    df_p = innerjoin(
        df_p_all,
        unique(sales_cpq[:, [:FACTSET_ENTITY_ID, :DATE]]),
        on = [:FACTSET_ENTITY_ID, :DATE],
    )
    df_x_p = deepcopy(df_p)
    df_x_p_country = df_x_p[df_x_p.ISO_COUNTRY .== country, :][:, [
        :FACTSET_ENTITY_ID, :FACTSET_ENTITY_ID_SEGMENT, :PROPER_NAME,
        :SALES, :FF_SIC_CODE,
    ]]
    df_x_p_country = df_x_p_country[df_x_p_country.SALES .!== missing, :]

    df_col_SIC = deepcopy(col_SIC)

    # --- CDP regional breakdown ---
    g_CDP_c_r = g_CDP_r[g_CDP_r.FISCAL_YEAR .=== yr, :]
    g_CDP_r_domestic = g_CDP_c_r[g_CDP_c_r.SUB_COUNTRY_ISO .== country, :]
    df_CDP_matched_r = innerjoin(sales_cpq, g_CDP_c_r, on = :FACTSET_ENTITY_ID)
    df_CDP_matched_domestic = @linq innerjoin(
        sales_cpq, g_CDP_r_domestic, on = :FACTSET_ENTITY_ID
    ) |> unique(:PROPER_NAME) |> dropmissing(:g_S1)
    DICT_CDP_matched_domestic = Dict(zip(
        df_CDP_matched_domestic.FACTSET_ENTITY_ID,
        df_CDP_matched_domestic.g_S1,
    ))

    # Companies reporting no domestic emissions
    delete_list = antijoin(
        unique(df_CDP_matched_r, :FACTSET_ENTITY_ID),
        df_CDP_matched_domestic,
        on = :FACTSET_ENTITY_ID,
    ).FACTSET_ENTITY_ID

    # --- Segment dictionaries ---
    DICT_p_SIC = Dict(zip(
        df_x_p_country.FACTSET_ENTITY_ID_SEGMENT,
        df_x_p_country.FF_SIC_CODE,
    ))
    df_x_p_NOS = unique(
        df_x_p_country[df_x_p_country.FACTSET_ENTITY_ID .∈ (df_CDP_matched.FACTSET_ENTITY_ID,), :],
        :FACTSET_ENTITY_ID_SEGMENT,
    )
    df_p_subsidiary = antijoin(df_x_p_NOS, sales_cpq, on = :FACTSET_ENTITY_ID_SEGMENT)

    df_x_p_NOS.i_p_est = fill(0.0, nrow(df_x_p_NOS))
    df_x_p_NOS.g_p_est = fill(0.0, nrow(df_x_p_NOS))

    # === Eq. S2-2: Segment-level S1 allocation ===
    for g_1 in groupby(df_x_p_NOS, :FACTSET_ENTITY_ID)
        for row in eachrow(g_1)
            p_ID = row.FACTSET_ENTITY_ID_SEGMENT

            if p_ID ∈ df_p_subsidiary.FACTSET_ENTITY_ID_SEGMENT
                # Subsidiary segment: use SIC → sector intensity
                if row.FF_SIC_CODE != 9999
                    sector_p = df_col_SIC[tryparse.(Int64, df_col_SIC.SIC_CODE) .== DICT_p_SIC[p_ID], :SECTOR_CODE]
                    df_sector_p = i_x_g[i_x_g.SECTOR_CODE .∈ (sector_p,), :]
                    row.i_p_est = sum(df_sector_p[:, Symbol(GHG_type)]) / sum(df_sector_p.x)
                end
            else
                # Non-subsidiary: weighted average of subsegment intensities
                x_p_q = sales_cpq[sales_cpq.FACTSET_ENTITY_ID_SEGMENT .== p_ID, :FF_SALES_modified_estimated_unconsolidated_cpq]
                row.i_p_est = sum(
                    x_p_q .* replace(
                        getindex.(Ref(DICT_intst), sales_cpq[sales_cpq.FACTSET_ENTITY_ID_SEGMENT .== p_ID, :SECTOR_CODE]),
                        Inf => 0.0,
                    )
                ) / sum(x_p_q)
            end

            # Eq. S2-2: g_p = (i_p × SALES_p) / Σ(i_p × SALES_p) × g_CDP_c
            g_1.g_p_est .= g_1.i_p_est .* g_1.SALES ./
                sum(g_1.i_p_est .* g_1.SALES) .*
                DICT_c_CDP_matched[g_1.FACTSET_ENTITY_ID[1]]
        end
    end

    replace!(df_x_p_NOS.g_p_est, NaN => 0.0)

    # === Eq. S2-1 + S2-3: Unconsolidated conversion ===
    df_p_uncon = combine(
        groupby(sales_cpq, :FACTSET_ENTITY_ID_SEGMENT),
        :FF_SALES_modified_estimated_unconsolidated_cpq => sum,
    )
    df_x_p_NOS = leftjoin(df_x_p_NOS, df_p_uncon, on = :FACTSET_ENTITY_ID_SEGMENT)
    # Eq. S2-1: r = Σ(SALES◦) / SALES∞
    df_x_p_NOS.r_uncon = replace(
        df_x_p_NOS.FF_SALES_modified_estimated_unconsolidated_cpq_sum, missing => 0,
    ) ./ df_x_p_NOS.SALES

    x_q = Symbol("FF_SALES_modified_estimated_unconsolidated_cpq")
    df_p_matched_CDP = deepcopy(df_x_p_NOS)
    df_p_matched_CDP.g_p_uncon = fill(0.0, nrow(df_p_matched_CDP))
    df_q_matched_CDP = sales_cpq[sales_cpq.FACTSET_ENTITY_ID .∈ (df_CDP_matched.FACTSET_ENTITY_ID,), :]

    # Eq. S2-3: g◦ = g∞ × r
    for c_p in groupby(df_p_matched_CDP, :FACTSET_ENTITY_ID)
        c_p.g_p_uncon .= c_p.g_p_est .* c_p.r_uncon
    end

    DICT_p_CDP_uncon = Dict(zip(
        df_p_matched_CDP.FACTSET_ENTITY_ID_SEGMENT,
        df_p_matched_CDP.g_p_uncon,
    ))
    df_q_matched_CDP.g_S1 = fill(0.0, nrow(df_q_matched_CDP))

    # === Eq. S2-4: Subsegment allocation ===
    for c_q in groupby(df_q_matched_CDP, :FACTSET_ENTITY_ID_SEGMENT)
        c_q.g_S1 .= c_q[!, x_q] .* getindex.(Ref(DICT_intst), c_q.SECTOR_CODE) ./
            sum(c_q[!, x_q] .* getindex.(Ref(DICT_intst), c_q.SECTOR_CODE)) .*
            DICT_p_CDP_uncon[c_q.FACTSET_ENTITY_ID_SEGMENT[1]]
    end

    # === Eq. S2-5: Cap at domestic region breakdown ===
    for i in groupby(df_q_matched_CDP, :FACTSET_ENTITY_ID)
        id = i.FACTSET_ENTITY_ID[1]
        if id in keys(DICT_CDP_matched_domestic) &&
            sum(i.g_S1) > DICT_CDP_matched_domestic[id]
            i.g_S1 .= i.g_S1 ./ sum(i.g_S1) .* DICT_CDP_matched_domestic[id]
        end
    end

    df_NOS = df_q_matched_CDP[
        df_q_matched_CDP.FACTSET_ENTITY_ID .∉ (delete_list,),
        [:FACTSET_ENTITY_ID_SEGMENT_SUB, :SECTOR_CODE, :g_S1, :FF_SALES_modified_estimated_unconsolidated_cpq],
    ]
    df_NOS[!, :SOURCE_S1] .= "CDP"

    return df_NOS
end
