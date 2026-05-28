# ============================================================================
# scope1_epa.jl — EPA-based Scope 1 estimation for US companies.
#
# Original: module/GHG_estimate/q_S1_EPA_estimate.jl
# Paper reference: SI S2.3 (Methods 1-4, Eq. S2-11 to S2-20)
#
# This module handles the complex case analysis (Cases I, II, III)
# for matching EPA facility emissions to EMRIO subsegments.
# ============================================================================

"""
    estimate_scope1_epa(country, yr, sales_cpq, info_qd, df_NOS,
                        DICT_intst, i_x_g, g_CDP_c, base_path)

Augment `df_NOS` with EPA facility-based Scope 1 for US companies.

# SI S2.3 Cases:
- Case I   (Eq. S2-14 to S2-16): EMRIO sectors ⊆ EPA sectors
- Case II  (Eq. S2-17, S2-20):   EPA sectors ⊆ EMRIO sectors
- Case III (Eq. S2-17 to S2-19): Partial overlap

Returns updated `df_NOS` DataFrame with EPA companies appended.
"""
function estimate_scope1_epa(
    country::String, yr::Int,
    sales_cpq, info_qd, df_NOS,
    DICT_intst, i_x_g, g_CDP_c, base_path::String, output_path::String,
)
    # --- Reload sales_cpq for USA with proper name correction ---
    # Note: The original q_S1_EPA_estimate.jl re-reads sales_cpq from info_qd
    # rather than using the one passed in.  We reproduce this behavior for
    # regression consistency, even though the function already receives sales_cpq.
    mask_usa = (info_qd.ISO_COUNTRY .== country) .& (info_qd.FF_SALES_modified_estimated_unconsolidated_cpq .!== missing)
    sales_cpq = info_qd[mask_usa, :]

    # NOTE: sym_entity_mod.csv was loaded to update sales_cpq.PROPER_NAME,
    # but PROPER_NAME is never used downstream in this function (the EPA
    # facility name-matching code that consumed it is commented out).
    # Commented out to avoid an unnecessary 286MB file dependency.
    # file_path_mod = joinpath(base_path, "data/for_app/sym_entity_mod.csv")
    # sym_entity = CSV.read(file_path_mod, DataFrame)
    # Dict_PROPER_NAME = Dict(zip(sym_entity.FACTSET_ENTITY_ID, sym_entity.ENTITY_PROPER_NAME))
    #
    # for row in eachrow(sales_cpq)
    #     if row.FACTSET_ENTITY_ID in keys(Dict_PROPER_NAME)
    #         row.PROPER_NAME = Dict_PROPER_NAME[row.FACTSET_ENTITY_ID]
    #     end
    # end
    # Note: sales_cpq_replace was computed in the original but only used by
    # commented-out EPA facility name matching code.  Removed as dead code.

    # --- Load BEA-NAICS concordance and EPA facility NAICS ---
    con_BEA_NAICS = CSV.read(joinpath(base_path, "data/tmp_files/bea_naics_2012_2017_concordance.csv"), DataFrame)
    file_path = joinpath(base_path, "data/GHG/US/f_NAISC.xlsx")
    sheet_name = string(yr)
    dt = XLSX.readtable(file_path, sheet_name)
    df_NAISC = DataFrame(dt)

    con_BEA_NAICS[!, :NAICS_2012] = string.(con_BEA_NAICS.NAICS_2012)

    # --- Load EPA facility emissions ---
    df_EPA = CSV.read(joinpath(base_path, "data/GHG/US/g_EPA_f_$(yr).csv"), DataFrame)
    df_EPA = unique(innerjoin(df_EPA, df_NAISC, on = :GHGRP_ID), [:GHGRP_ID, :GHG_type])

    # Exclude companies already covered by CDP
    df_EPA_add = antijoin(df_EPA, g_CDP_c[g_CDP_c.accounting_year .== yr, :], on = :FACTSET_ENTITY_ID)
    df_EPA_add = df_EPA_add[df_EPA_add.GHG_type .!== "GHG6", :]

    df_EPA = combine(groupby(df_EPA_add, [:GHGRP_ID, :FACTSET_ENTITY_ID])) do sdf
        DataFrame(GHG6 = sum(sdf.g_f), NAICS_CODE = first(sdf.NAICS_CODE))
    end

    # --- NAICS → BEA mapping ---
    Dict_NAICS_BEA = Dict{String,Any}()
    for grp in groupby(con_BEA_NAICS, :NAICS_2012)
        Dict_NAICS_BEA[grp.NAICS_2012[1]] = grp.BEA
    end

    Dict_c_f_BEA = Dict{String,Any}()
    for grp in groupby(df_EPA, :FACTSET_ENTITY_ID)
        new_list = []
        for key in grp.NAICS_CODE
            values = get(Dict_NAICS_BEA, key, [key])
            append!(new_list, values)
        end
        Dict_c_f_BEA[grp.FACTSET_ENTITY_ID[1]] = unique(new_list)
    end

    # --- Reload i_x_g for USA ---
    # Note: The original q_S1_EPA_estimate.jl re-reads i_x_g from disk (line 136)
    # rather than using the one already in memory.  We reproduce this for
    # regression consistency.
    i_x_g = CSV.read(joinpath(output_path, "i_x_g/$(yr)/$(country).csv"), DataFrame)
    Dict_j_g = Dict(zip(i_x_g.SECTOR_CODE, i_x_g.GHG6))

    Dict_c_q = Dict{String,Any}()
    for grp in groupby(dropmissing(sales_cpq, :SECTOR_CODE), :FACTSET_ENTITY_ID)
        Dict_c_q[grp.FACTSET_ENTITY_ID[1]] = unique(grp.SECTOR_CODE)
    end

    # --- Build sales_EPA with case classification ---
    sales_EPA = dropmissing(
        deepcopy(sales_cpq[sales_cpq.FACTSET_ENTITY_ID .∈ (keys(Dict_c_f_BEA),),
            [:FACTSET_ENTITY_ID, :FACTSET_ENTITY_ID_SEGMENT_SUB, :SECTOR_CODE, :FF_SALES_modified_estimated_unconsolidated_cpq]]),
        :SECTOR_CODE,
    )
    sales_EPA[!, :case] .= ""

    # SI S2.3.4: Classify into Cases I, II, III
    for row in eachrow(sales_EPA)
        CODE_f = Dict_c_f_BEA[row.FACTSET_ENTITY_ID]
        CODE_EIO = Dict_c_q[row.FACTSET_ENTITY_ID]
        if issubset(CODE_EIO, CODE_f)
            row.case = "I"
        elseif issubset(CODE_f, CODE_EIO)
            row.case = row.SECTOR_CODE ∈ intersect(CODE_EIO, CODE_f) ? "II-1" : "II-2"
        else
            row.case = row.SECTOR_CODE ∈ intersect(CODE_EIO, CODE_f) ? "III-1" : "III-2"
        end
    end

    # --- Allocate facility emissions to sectors (Eq. S2-12, S2-13) ---
    empty_lists = Vector{Any}(undef, nrow(df_EPA))
    for i in 1:length(empty_lists); empty_lists[i] = []; end
    df_EPA[!, :BEA_CODE] = empty_lists
    for row in eachrow(df_EPA)
        row.BEA_CODE = get(Dict_NAICS_BEA, row.NAICS_CODE, [row.NAICS_CODE])
    end

    df_EPA_SECTOR = DataFrame(FACTSET_ENTITY_ID = String[], BEA_CODE = String[], GHG6 = Float64[])
    for row in eachrow(df_EPA)
        if length(row.BEA_CODE) == 1
            push!(df_EPA_SECTOR, Dict(:FACTSET_ENTITY_ID => row.FACTSET_ENTITY_ID, :BEA_CODE => row.BEA_CODE[1], :GHG6 => row.GHG6))
        else
            j_g_list = map(key -> get(Dict_j_g, key, []), row.BEA_CODE)
            g_s = row.GHG6 .* j_g_list ./ sum(j_g_list)
            for i in 1:length(row.BEA_CODE)
                push!(df_EPA_SECTOR, Dict(:FACTSET_ENTITY_ID => row.FACTSET_ENTITY_ID, :BEA_CODE => row.BEA_CODE[i], :GHG6 => g_s[i]))
            end
        end
    end

    df_EPA_SECTOR = combine(groupby(df_EPA_SECTOR, [:FACTSET_ENTITY_ID, :BEA_CODE])) do sdf
        DataFrame(GHG6 = sum(sdf.GHG6))
    end

    # --- Methods 1 & 2 (Cases I, II-1, III-1): Eq. S2-14, S2-17 ---
    sales_EPA[:, :g_S1] .= 0.0
    for grp in groupby(sales_EPA, :FACTSET_ENTITY_ID)
        CODE_f = Dict_c_f_BEA[grp.FACTSET_ENTITY_ID[1]]
        CODE_EIO = Dict_c_q[grp.FACTSET_ENTITY_ID[1]]

        # Method 1 (Case I)
        if grp.case[1] == "I"
            g_c = sum(df_EPA_SECTOR[df_EPA_SECTOR.FACTSET_ENTITY_ID .== grp.FACTSET_ENTITY_ID[1], :GHG6])
            grp.g_S1 .= g_c .*
                grp.FF_SALES_modified_estimated_unconsolidated_cpq .*
                getindex.(Ref(DICT_intst), grp.SECTOR_CODE) ./
                sum(grp.FF_SALES_modified_estimated_unconsolidated_cpq .*
                    getindex.(Ref(DICT_intst), grp.SECTOR_CODE))

        # Method 2 (Cases II-1, III-1)
        elseif any(occursin("-1", ce) for ce in grp.case)
            g_c = sum(df_EPA_SECTOR[
                (df_EPA_SECTOR.FACTSET_ENTITY_ID .== grp.FACTSET_ENTITY_ID[1]) .&
                (df_EPA_SECTOR.BEA_CODE .∈ (intersect(CODE_EIO, CODE_f),)), :GHG6])
            mask1 = occursin.("-1", grp.case)
            grp[mask1, :g_S1] .= g_c .*
                grp[mask1, :FF_SALES_modified_estimated_unconsolidated_cpq] .*
                getindex.(Ref(DICT_intst), grp[mask1, :SECTOR_CODE]) ./
                sum(grp[mask1, :FF_SALES_modified_estimated_unconsolidated_cpq] .*
                    getindex.(Ref(DICT_intst), grp[mask1, :SECTOR_CODE]))
        end
    end

    # --- Method 3 (Case III-2): Eq. S2-18, S2-19 ---
    for row in eachrow(sales_EPA)
        CODE_f = Dict_c_f_BEA[row.FACTSET_ENTITY_ID]
        CODE_EIO = Dict_c_q[row.FACTSET_ENTITY_ID]
        if row.case == "III-2"
            # Note: setdiff(intersect(A,B), B) is mathematically always empty
            # since intersect(A,B) ⊆ B.  This is a quirk in the original code
            # (q_S1_EPA_estimate.jl L244).  Reproduced as-is for regression.
            excluded_codes = setdiff(intersect(CODE_EIO, CODE_f), CODE_f)
            filtered_rows_EPA = filter(r -> r.FACTSET_ENTITY_ID == row.FACTSET_ENTITY_ID && !(r.BEA_CODE in excluded_codes), df_EPA_SECTOR)
            filtered_rows_SALES = filter(r -> r.FACTSET_ENTITY_ID == row.FACTSET_ENTITY_ID && r.case == "III-2", sales_EPA)
            g_c_EPA = sum(filtered_rows_EPA.GHG6)
            g_c_q = map(key -> get(DICT_intst, key, 0.0), filtered_rows_SALES.SECTOR_CODE) .* filtered_rows_SALES.FF_SALES_modified_estimated_unconsolidated_cpq
            g_c_star = sum(g_c_q)
            g_c = max(g_c_EPA, g_c_star)
            row.g_S1 = g_c * get(DICT_intst, row.SECTOR_CODE, 0.0) * row.FF_SALES_modified_estimated_unconsolidated_cpq / g_c_star
        end
    end

    # --- Compute residual intensity for Method 4 ---
    df_NOS_1 = append!(
        select(df_NOS, [:FACTSET_ENTITY_ID_SEGMENT_SUB, :SECTOR_CODE, :g_S1, :FF_SALES_modified_estimated_unconsolidated_cpq]),
        select(sales_EPA[sales_EPA.g_S1 .!== 0.0, :], [:FACTSET_ENTITY_ID_SEGMENT_SUB, :SECTOR_CODE, :g_S1, :FF_SALES_modified_estimated_unconsolidated_cpq]),
    )
    j_Q = combine(groupby(df_NOS_1, :SECTOR_CODE)) do sdf
        DataFrame(g_Q = sum(sdf.g_S1), x_Q = sum(sdf.FF_SALES_modified_estimated_unconsolidated_cpq))
    end
    df_Q = leftjoin(j_Q, i_x_g, on = :SECTOR_CODE)
    j_intst_3 = replace((df_Q.GHG6 .- df_Q.g_Q) ./ (df_Q.x .- df_Q.x_Q), NaN => 0)
    Dict_j_3 = Dict(zip(df_Q.SECTOR_CODE, j_intst_3))

    for (key, value) in DICT_intst
        if !haskey(Dict_j_3, key)
            Dict_j_3[key] = value
        end
    end

    # --- Method 4 (Case II-2): Eq. S2-20 ---
    for row in eachrow(sales_EPA)
        if row.case == "II-2"
            row.g_S1 = row.FF_SALES_modified_estimated_unconsolidated_cpq * Dict_j_3[row.SECTOR_CODE]
        end
    end

    sales_EPA[:, :SOURCE_S1] .= "USEPA"

    # Append EPA results to df_NOS
    df_NOS = append!(df_NOS, select(sales_EPA, names(df_NOS)))

    return df_NOS
end
