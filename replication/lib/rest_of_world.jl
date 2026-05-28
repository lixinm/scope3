# ============================================================================
# rest_of_world.jl — Estimate Rest-of-World (RoW) GHG emissions.
#
# Original: module/GHG_footprint/g_ROW.jl
# Paper reference: SI S1.4, Eq. S1-6
#
# g_RoW = g_WORLD − Σ_s g_s   (world total minus tracked countries)
# ============================================================================

"""
    Df_emission(df_IEA_subset, DICT_emission_factor)

Compute CO₂ emissions by FLOW from an IEA data subset.
Applies IPCC emission factors to fuel consumption values, then
aggregates by FLOW (energy activity type).

Returns a DataFrame with columns [:FLOW, :Emission] (in kilotons).
"""
function Df_emission(df_IEA_subset, DICT_emission_factor)
    df_country = df_IEA_subset[df_IEA_subset.PRODUCT .∈ (keys(DICT_emission_factor),), :]
    df_country = copy(df_country)
    df_country.emission = df_country.VALUE .* getindex.(Ref(DICT_emission_factor), df_country.PRODUCT)

    df_flow = unstack(df_country[:, [:FLOW, :PRODUCT, :emission]], :PRODUCT, :emission)
    df_flow.Emission = fill(0.0, nrow(df_flow))
    for row in eachrow(df_flow)
        row.Emission = abs(sum(skipmissing(row[2:end]))) / 1000
    end

    return df_flow[:, [:FLOW, :Emission]]
end

"""
    compute_g_RoW(nt_EMRIO, iea_data, yr)

Compute Rest-of-World GHG emissions.

# SI S1.4 Eq. S1-6:
    g_RoW = g_WORLD − Σ_{s ∈ S_IO} g_s

where S_IO is the set of countries in the EMRIO database.

# Arguments
- `nt_EMRIO` : EMRIO NamedTuple (contains att_r with country list)
- `iea_data` : Output of `load_iea_data()` (contains df_IEA, df_con_SIC_temp,
               df_emission_factor, IEA_country)
- `yr`       : Analysis year

# Returns
- `g_RoW` : Scalar, total RoW emissions
"""
function compute_g_RoW(nt_EMRIO, iea_data, yr::Int)
    df_IEA = iea_data.df_IEA
    df_emission_factor = iea_data.df_emission_factor
    df_con_SIC_temp = iea_data.df_con_SIC_temp
    IEA_country = iea_data.IEA_country

    ISO_r_list = nt_EMRIO.att_r.ISO_COUNTRY_r
    ISO_r_list_IEA = uppercase.(getindex.(Ref(IEA_country), ISO_r_list))

    # Filter IEA data for the target year
    df_IEA_y = df_IEA[(df_IEA.YEAR .== yr) .& (df_IEA.COUNTRY .∈ (ISO_r_list_IEA,)), :]
    df_IEA_world = df_IEA[(df_IEA.YEAR .== yr) .& (df_IEA.COUNTRY .== "WORLD"), :]

    # Build emission factor dictionary
    df_ef = dropmissing(copy(df_emission_factor), :PRODUCT)
    DICT_emission_factor_local = Dict(zip(df_ef.PRODUCT, df_ef.CO2))

    # World emissions
    df_emission_world = Df_emission(df_IEA_world, DICT_emission_factor_local)

    # Sum of tracked countries' emissions
    df_r_IEA = DataFrame()
    df_countries = df_IEA_y[df_IEA_y.PRODUCT .∈ (keys(DICT_emission_factor_local),), :]
    for i in groupby(df_countries, :COUNTRY)
        df_r_IEA = vcat(df_r_IEA, Df_emission(i, DICT_emission_factor_local))
    end
    df_r_sum = combine(groupby(df_r_IEA, :FLOW), :Emission => sum => :Emission)

    # FLOWs that map to SIC sectors
    flows = unique(dropmissing(df_con_SIC_temp, :FLOW).FLOW)

    g_world = sum(df_emission_world[df_emission_world.FLOW .∈ (flows,), :Emission])
    g_r_sum = sum(df_r_sum[df_r_sum.FLOW .∈ (flows,), :Emission])

    # Eq. S1-6
    g_RoW = g_world - g_r_sum

    return g_RoW
end
