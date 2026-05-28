# ============================================================================
# arrange_sector.jl — Estimate sector-level GHG emissions per country.
#
# Original: module/arrange_sector/arrange_sector.jl
#           module/functions/arrange_sector_EDGAR.jl
# Paper reference: SI S1.1 (IEA CO₂, Eq. S1-2),
#                  SI S1.2 (EDGAR non-CO₂, Eq. S1-4),
#                  SI S1.3 (zero correction, Eq. S1-5)
#
# For each country, this module:
#   1. Builds a FLOW→sector concordance matrix
#   2. Allocates IEA CO₂ emissions to IO sectors (Eq. S1-2)
#   3. Allocates EDGAR non-CO₂ emissions to IO sectors (Eq. S1-4)
#   4. Corrects zero CO₂ with EDGAR fallback (Eq. S1-5)
#   5. Produces i_x_g DataFrame: SECTOR_CODE, x, CO2, non_CO2, GHG6
# ============================================================================

"""
    g_non_CO2_j(nt_data_country_r, country, edgar_data)

Allocate EDGAR non-CO₂ emissions to IO customer sectors for a country.

# SI S1.2 Eq. S1-4:
    g_j,t = Σ_{j_IPCC} g_{j_IPCC,t} × (C_{j_IPCC,j} × x_j) / Σ_j(C_{j_IPCC,j} × x_j)

Returns: Vector of non-CO₂ emissions per sector (length = num_j).
"""
function g_non_CO2_j(nt_data_country_r, country::String, edgar_data)
    df_ipcc_sic = edgar_data.df_ipcc_sic
    df_non_CO2 = edgar_data.df_non_CO2

    con_j_sic = nt_data_country_r.C_j_sic
    col_sic = nt_data_country_r.C_j_sic_col
    x_j = deepcopy(nt_data_country_r.IOT_SUT.x_j)

    list1 = unique(df_ipcc_sic.IPCC_CODE)
    list2 = col_sic.SIC_CODE

    # Build IPCC → SIC concordance matrix
    con_IPCC_SIC = zeros(Int, length(list1), length(list2))
    for row in eachrow(df_ipcc_sic)
        i = findfirst(isequal(row[:IPCC_CODE]), list1)
        j = findfirst(isequal(row[:SIC_CODE]), list2)
        if i !== nothing && j !== nothing
            con_IPCC_SIC[i, j] = 1
        end
    end

    # IPCC → IO sector concordance
    con_IPCC_j = con_IPCC_SIC * transpose(con_j_sic)
    con_IPCC_j[con_IPCC_j .> 0] .= 1

    # Country-specific non-CO₂ emissions by IPCC code
    df_non_CO2_country = df_non_CO2[df_non_CO2.ISO_COUNTRY .== country, :]
    Dict_non_CO2_country = Dict(zip(df_non_CO2_country.IPCC_CODE, df_non_CO2_country.non_CO2))

    g_non_CO2_country = Float64[]
    for i in list1
        push!(g_non_CO2_country, get(Dict_non_CO2_country, i, 0.0))
    end

    # Allocate to sectors using output-weighted concordance (Eq. S1-4)
    A_values = g_non_CO2_country
    B_output = vec(x_j)
    B_values = zeros(Float64, length(B_output))

    for (i, a_value) in enumerate(A_values)
        b_indices = findall(x -> x == 1, con_IPCC_j[i, :])
        if length(b_indices) == 1
            B_values[b_indices[1]] += a_value
        elseif length(b_indices) > 1
            total_output = sum(B_output[b_indices])
            for j in b_indices
                B_values[j] += a_value * (B_output[j] / total_output)
            end
        end
    end

    return B_values
end

"""
    g_EDGAR_CO2_j(nt_data_country_r, country, edgar_data)

Allocate EDGAR CO₂ emissions to IO sectors (used as fallback in Eq. S1-5).
Same logic as `g_non_CO2_j` but for CO₂.
"""
function g_EDGAR_CO2_j(nt_data_country_r, country::String, edgar_data)
    df_ipcc_sic = edgar_data.df_ipcc_sic
    df_EDGAR_CO2 = edgar_data.df_EDGAR_CO2

    con_j_sic = nt_data_country_r.C_j_sic
    col_sic = nt_data_country_r.C_j_sic_col
    x_j = deepcopy(nt_data_country_r.IOT_SUT.x_j)

    list1 = unique(df_ipcc_sic.IPCC_CODE)
    list2 = col_sic.SIC_CODE

    con_IPCC_SIC = zeros(Int, length(list1), length(list2))
    for row in eachrow(df_ipcc_sic)
        i = findfirst(isequal(row[:IPCC_CODE]), list1)
        j = findfirst(isequal(row[:SIC_CODE]), list2)
        if i !== nothing && j !== nothing
            con_IPCC_SIC[i, j] = 1
        end
    end

    con_IPCC_j = con_IPCC_SIC * transpose(con_j_sic)
    con_IPCC_j[con_IPCC_j .> 0] .= 1

    df_EDGAR_CO2_country = df_EDGAR_CO2[df_EDGAR_CO2.ISO_COUNTRY .== country, :]
    Dict_EDGAR_CO2_country = Dict(zip(df_EDGAR_CO2_country.IPCC_CODE, df_EDGAR_CO2_country.CO2))

    g_vals = Float64[]
    for i in list1
        push!(g_vals, get(Dict_EDGAR_CO2_country, i, 0.0))
    end

    A_values = g_vals
    B_output = vec(x_j)
    B_values = zeros(Float64, length(B_output))

    for (i, a_value) in enumerate(A_values)
        b_indices = findall(x -> x == 1, con_IPCC_j[i, :])
        if length(b_indices) == 1
            B_values[b_indices[1]] += a_value
        elseif length(b_indices) > 1
            total_output = sum(B_output[b_indices])
            for j in b_indices
                B_values[j] += a_value * (B_output[j] / total_output)
            end
        end
    end

    return B_values
end

"""
    compute_sector_ghg(country, yr, country_io, iea_data, edgar_data)

Compute sector-level GHG emissions for one country.

# Steps (SI S1):
1. Build FLOW→sector concordance (IEA → SIC → IO sector)
2. Allocate IEA CO₂ to sectors (Eq. S1-2)
3. Allocate EDGAR non-CO₂ to sectors (Eq. S1-4)
4. Correct zero CO₂ with EDGAR fallback (Eq. S1-5)
5. Compute GHG6 = CO₂ + non-CO₂

# Arguments
- `country`    : ISO 3-letter country code
- `yr`         : Analysis year
- `country_io` : Output of `load_country_io()` for this country
- `iea_data`   : Output of `load_iea_data()`
- `edgar_data` : Output of `load_edgar_data()`

# Returns
- `i_x_g` : DataFrame with columns SECTOR_CODE, x, CO2, non_CO2, GHG6, ISO_COUNTRY
"""
function compute_sector_ghg(country::String, yr::Int, country_io, iea_data, edgar_data)
    nt_data_country_r = country_io.nt_data

    df_IEA = iea_data.df_IEA
    df_emission_factor = iea_data.df_emission_factor
    df_con_SIC_temp = iea_data.df_con_SIC_temp
    IEA_country = iea_data.IEA_country

    con_j_sic = nt_data_country_r.C_j_sic
    col_sic = nt_data_country_r.C_j_sic_col
    x_j = deepcopy(nt_data_country_r.IOT_SUT.x_j)

    # --- Build FLOW → sector concordance ---
    df = df_con_SIC_temp[:, [:FLOW, :SIC_CODE]]
    list1 = unique(df_con_SIC_temp.FLOW)
    list2 = col_sic.SIC_CODE

    con_FLOW_SIC = zeros(Int, length(list1), length(list2))
    for row in eachrow(df)
        i = findfirst(isequal(row[:FLOW]), list1)
        j = findfirst(isequal(row[:SIC_CODE]), list2)
        if i !== nothing && j !== nothing
            con_FLOW_SIC[i, j] = 1
        end
    end
    con_FLOW_j = con_FLOW_SIC * transpose(con_j_sic)
    con_FLOW_j[con_FLOW_j .> 0] .= 1

    # --- IEA CO₂ allocation (Eq. S1-2) ---
    mask_iea = (df_IEA.COUNTRY .== uppercase(IEA_country[country])) .& (df_IEA.YEAR .== yr)
    df_country = df_IEA[mask_iea, :]

    df_ef = dropmissing(copy(df_emission_factor), :PRODUCT)
    DICT_ef = Dict(zip(df_ef.PRODUCT, df_ef.CO2))

    df_country = df_country[df_country.PRODUCT .∈ (keys(DICT_ef),), :]
    df_country = copy(df_country)
    df_country.emission = df_country.VALUE .* getindex.(Ref(DICT_ef), df_country.PRODUCT)

    df_flow = combine(groupby(df_country, :FLOW)) do sdf
        DataFrame(FLOW = first(sdf.FLOW), emission = abs(sum(sdf.emission)) / 1000)
    end

    g_CO2_country = Float64[]
    Dict_CO2_country = Dict(zip(df_flow.FLOW, df_flow.emission))
    for i in list1
        push!(g_CO2_country, get(Dict_CO2_country, i, 0.0))
    end

    # Output-weighted allocation to sectors (Eq. S1-2)
    B_output = vec(x_j)
    B_values = zeros(Float64, length(B_output))
    for (i, a_value) in enumerate(g_CO2_country)
        b_indices = findall(x -> x == 1, con_FLOW_j[i, :])
        if length(b_indices) == 1
            B_values[b_indices[1]] += a_value
        elseif length(b_indices) > 1
            total_output = sum(B_output[b_indices])
            for j in b_indices
                B_values[j] += a_value * (B_output[j] / total_output)
            end
        end
    end

    # --- Build i_x_g DataFrame ---
    i_x_g = DataFrame(
        SECTOR_CODE = vec(nt_data_country_r.desc_j.SECTOR_CODE),
        x = vec(x_j),
        CO2 = vec(B_values),
        non_CO2 = g_non_CO2_j(nt_data_country_r, country, edgar_data),  # Eq. S1-4
    )
    i_x_g.GHG6 = i_x_g.CO2 .+ i_x_g.non_CO2
    i_x_g[!, :ISO_COUNTRY] .= country

    # --- EDGAR CO₂ fallback (Eq. S1-5) ---
    # Note: In the original code, GHG6 is computed BEFORE the EDGAR CO₂
    # correction (line 109 of original arrange_sector.jl).  The correction
    # updates the CO2 column but does NOT recalculate GHG6.  We reproduce
    # this behavior exactly for regression consistency.
    i_x_g.CO2_EDGAR = g_EDGAR_CO2_j(nt_data_country_r, country, edgar_data)
    for row in eachrow(i_x_g)
        if row.CO2 == 0.0 && row.x > 0.0
            row.CO2 = row.CO2_EDGAR
        end
    end

    return i_x_g
end
