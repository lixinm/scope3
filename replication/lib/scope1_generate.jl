# ============================================================================
# scope1_generate.jl — Generate subsegment-level Scope 1 for one country.
#
# Original: module/GHG_estimate/q_S1_generate.jl
# Paper reference: SI S2 (full section) + Main text Eq. 1-2
#
# Orchestrates:
#   1. Load sector-level i_x_g → compute DICT_intst
#   2. Run CDP estimation (scope1_cdp.jl)
#   3. If USA: run EPA estimation (scope1_epa.jl)
#   4. If JPN: append METI data
#   5. Compute OS residual (Eq. 2)
#   6. Return df_q with columns: FACTSET_ENTITY_ID_SEGMENT_SUB, g_S1, SOURCE_S1, ISO_COUNTRY
# ============================================================================

"""
    generate_scope1_country(country, yr, country_io, emrio_data,
                            cdp_data, meti_data, base_path, GHG_type)

Generate subsegment-level Scope 1 emissions for one country.

# Arguments
- `country`     : ISO 3-letter country code
- `yr`          : Analysis year
- `country_io`  : Output of `load_country_io()` for this country
- `emrio_data`  : Output of `load_emrio()`
- `cdp_data`    : Output of `load_cdp_data()`
- `meti_data`   : METI DataFrame (or nothing if not JPN)
- `base_path`   : BASE_PATH from config
- `GHG_type`    : "GHG6"

# Returns
`df_q` DataFrame with columns:
  FACTSET_ENTITY_ID_SEGMENT_SUB, g_S1, SOURCE_S1, ISO_COUNTRY
"""
function generate_scope1_country(
    country::String, yr::Int,
    country_io, emrio_data,
    cdp_data, meti_data,
    base_path::String, output_path::String, GHG_type::String,
)
    sales_cpq = country_io.sales_cpq
    col_SIC = country_io.col_SIC

    # --- Load sector-level emissions ---
    if country == "JPN" && yr == 2015
        # Japan uses 3EID data directly
        i_x_g = CSV.read(joinpath(base_path, "data/GHG/JPN_METI_2015_g_i.csv"), DataFrame, types = Dict(:SECTOR_CODE => String))
    else
        # Other countries use Step 1 output
        i_x_g = CSV.read(joinpath(output_path, "i_x_g/$(yr)/$(country).csv"), DataFrame, types = Dict(:SECTOR_CODE => String))
    end

    # Eq. S3-1 (partial): sector emission intensity = GHG6 / output
    i_intst = replace(i_x_g[:, Symbol(GHG_type)] ./ i_x_g.x, NaN => 0)
    DICT_intst = Dict(zip(i_x_g.SECTOR_CODE, i_intst))

    # --- CDP-based Scope 1 estimation (SI S2.1) ---
    df_NOS = estimate_scope1_cdp(
        country, yr, sales_cpq, cdp_data,
        emrio_data.df_p_all, col_SIC, i_x_g, DICT_intst, GHG_type,
    )

    # --- EPA-based Scope 1 for USA (SI S2.3) ---
    if country == "USA"
        df_NOS = estimate_scope1_epa(
            country, yr, sales_cpq, emrio_data.info_qd,
            df_NOS, DICT_intst, i_x_g, cdp_data.g_CDP_c, base_path, output_path,
        )
    end

    # --- Select output columns ---
    df_q = @linq df_NOS |> select(:FACTSET_ENTITY_ID_SEGMENT_SUB, :g_S1, :SOURCE_S1)

    # --- Append METI data for Japan (SI S2.2) ---
    if country == "JPN" && meti_data !== nothing
        df_METI_gS1 = copy(meti_data)
        df_METI_gS1[!, :SOURCE_S1] .= "METI"
        df_q = append!(df_q,
            antijoin(
                df_METI_gS1[:, [:FACTSET_ENTITY_ID_SEGMENT_SUB, :g_S1, :SOURCE_S1]],
                df_q,
                on = :FACTSET_ENTITY_ID_SEGMENT_SUB,
            )
        )
    end

    # --- Eq. 2 (main text): OS residual = sector_total − Σ NOS ---
    j_NOS = combine(groupby(df_NOS, :SECTOR_CODE)) do sdf
        DataFrame(
            g_NOS = sum(sdf.g_S1),
            x_NOS = sum(sdf.FF_SALES_modified_estimated_unconsolidated_cpq),
        )
    end
    Dict_g_NOS = Dict(zip(j_NOS.SECTOR_CODE, j_NOS.g_NOS))
    Dict_x_NOS = Dict(zip(j_NOS.SECTOR_CODE, j_NOS.x_NOS))

    i_x_g.g_OS = replace(
        i_x_g.GHG6 .- [get(Dict_g_NOS, key, 0.0) for key in i_x_g.SECTOR_CODE],
        NaN => 0.0,
    )
    i_x_g.x_OS = i_x_g.x .- [get(Dict_x_NOS, key, 0.0) for key in i_x_g.SECTOR_CODE]

    # Create "Others-{SECTOR_CODE}-S" entries
    df_q_OS = DataFrame(FACTSET_ENTITY_ID_SEGMENT_SUB = String[], g_S1 = Float64[], SOURCE_S1 = String[])
    for row in eachrow(i_x_g)
        names_OS = string("Others-", row.SECTOR_CODE, "-S")
        push!(df_q_OS, [names_OS, row.g_OS, ""])
    end
    append!(df_q, df_q_OS)

    # Add country code
    df_q[!, :ISO_COUNTRY] .= country

    return df_q
end
