# ============================================================================
# load_emissions_data.jl — Load emission source data from CDP, EPA, METI,
#                           IEA, EDGAR, and FactSet entity concordance.
#
# Consolidated from:
#   module/load_modified_GHG/load_CDP.jl
#   module/load_modified_GHG/load_EPA.jl
#   module/load_modified_GHG/load_METI.jl
#   module/load_modified_GHG/load_IEA.jl
#   module/load_modified_GHG/load_EDGAR.jl
#   module/functions/load_sec_entity.jl
#   module/functions/load_df_segment.jl (partially)
#
# Paper reference: Section 3.2 "Data Sources"
#
# All functions accept explicit path arguments and return NamedTuples.
# No global variables are injected.
# ============================================================================
#
# NOTICE: This file depends on external files under import.
# Required import dependencies:
#   load_sec_entity(import_path) reads:
#   - <DATA_ROOT>/FactSet/Financial/ff_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Shipping/sc_ship_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Supplychain/ent_scr_sec_entity.txt
#   load_segment_base(import_path) reads:
#   - <DATA_ROOT>/tmp/nt_arranged_base_segment_20231210.jld2
# Please ensure these files are available when running this replication script.

# ---- CDP ---- (SI S2.1) ---------------------------------------------------

"""
    load_cdp_data(base_path)

Load CDP company-level and regional GHG emission data.

Returns a NamedTuple:
- `g_CDP_c`    : Company-level Scope 1 emissions (DataFrame)
- `g_CDP_r`    : Regional Scope 1 breakdown (DataFrame)
- `g_CDP_r_S2` : Regional Scope 2 breakdown (DataFrame)
- `g_CDP_S3`   : Company-level Scope 3 emissions (DataFrame)
"""
function load_cdp_data(base_path::String)
    data_dir = joinpath(base_path, "data/GHG/GHG_CDP")
    g_CDP_c    = CSV.read(joinpath(data_dir, "g_CDP.csv"), DataFrame)
    g_CDP_r    = CSV.read(joinpath(data_dir, "subr_gS1_CDP.csv"), DataFrame)
    g_CDP_r_S2 = CSV.read(joinpath(data_dir, "subr_gS2_CDP.csv"), DataFrame)
    g_CDP_S3   = CSV.read(joinpath(data_dir, "g_CDP_S3.csv"), DataFrame)
    return (
        g_CDP_c    = g_CDP_c,
        g_CDP_r    = g_CDP_r,
        g_CDP_r_S2 = g_CDP_r_S2,
        g_CDP_S3   = g_CDP_S3,
    )
end

# ---- Japan MOE / METI ---- (SI S2.2) --------------------------------------

"""
    load_meti_data(base_path, year)

Load preprocessed Japan METI (Ministry of the Environment) Scope 1 data.

Returns:
- `df_METI_gS1` : DataFrame with columns FACTSET_ENTITY_ID_SEGMENT_SUB,
                   SECTOR_CODE, g_S1
"""
function load_meti_data(base_path::String, year::Int)
    filepath = joinpath(base_path, "data/GHG/JPN_METI_$(year)_gS1.csv")
    df = CSV.read(filepath, DataFrame)
    df = df[:, [:FACTSET_ENTITY_ID_SEGMENT_SUB, :SECTOR_CODE, :g_S1]]
    df.SECTOR_CODE = string.(df.SECTOR_CODE)
    # Pad SECTOR_CODE to 6 characters if needed (e.g., "12345" → "012345")
    df[!, :SECTOR_CODE] = map(x -> length(x) == 5 ? "0" * x : x, df[!, :SECTOR_CODE])
    return df
end

# ---- U.S. EPA ---- (SI S2.3) ----------------------------------------------

"""
    load_epa_data(base_path, year)

Load U.S. EPA facility-level GHG emission data.

Returns:
- `df_EPA_g` : DataFrame with facility emissions
"""
function load_epa_data(base_path::String, year::Int)
    filepath = joinpath(base_path, "data/GHG/US/g_EPA_$(year).csv")
    return CSV.read(filepath, DataFrame)
end

# ---- IEA ---- (SI S1.1) ---------------------------------------------------

"""
    load_iea_data(base_path)

Load IEA World Energy Balances data and concordance tables.

Returns a NamedTuple:
- `df_IEA`           : IEA energy balance data (DataFrame)
- `df_con_SIC_temp`  : IEA flow → SIC concordance (DataFrame)
- `df_emission_factor`: IPCC CO₂ emission factors by product (DataFrame)
- `IEA_country`      : Dict mapping ISO3 country code → IEA country name
"""
function load_iea_data(base_path::String)
    data_dir = joinpath(base_path, "data/GHG/IEA")

    df_IEA = CSV.read(joinpath(data_dir, "IEA_all.csv"), DataFrame)

    df_con_SIC_temp = CSV.read(
        joinpath(data_dir, "concordance_IEA_SIC.csv"),
        DataFrame,
        types = Dict(:SIC_CODE => String),
    )
    df_con_SIC_temp = df_con_SIC_temp[1:1127, :]  # Original truncation

    df_emission_factor = CSV.read(
        joinpath(data_dir, "energy_emission_factor.csv"),
        DataFrame,
        silencewarnings = true,
    )

    # Build IEA country name dictionary from ISO 3-letter codes
    j_country = JSON.parsefile(joinpath(base_path, "data/GHG_related/gistfile1.txt"))
    IEA_country = Dict{String,String}()
    for i in 1:length(j_country)
        IEA_country[j_country[i]["alpha3Code"]] = uppercase(j_country[i]["name"])
    end
    # Manual overrides for IEA-specific country naming
    IEA_country["USA"] = "USA"
    IEA_country["KOR"] = "KOREA"
    IEA_country["GBR"] = "UK"
    IEA_country["AUS"] = "AUSTRALI"
    IEA_country["NOR"] = "NORWAY"
    IEA_country["NLD"] = "NETHLAND"
    IEA_country["CHE"] = "SWITLAND"
    IEA_country["NZL"] = "NZ"
    IEA_country["ZAF"] = "SOUTHAFRIC"
    IEA_country["HKG"] = "HONGKONG"
    IEA_country["TWN"] = "TAIPEI"
    IEA_country["CZE"] = "CZECH"
    IEA_country["CRI"] = "COSTARICA"
    IEA_country["LUX"] = "LUXEMBOU"
    IEA_country["CYP"] = "CYPRUS"
    IEA_country["ALB"] = "ALBANIA"
    IEA_country["ARM"] = "ARMENIA"
    IEA_country["BOL"] = "BOLIVIA"
    IEA_country["CIV"] = "COTEIVOIRE"
    IEA_country["MKD"] = "NORTHMACED"
    IEA_country["DOM"] = "DOMINICANR"
    IEA_country["LKA"] = "SRILANKA"
    IEA_country["RUS"] = "RUSSIA"

    return (
        df_IEA            = df_IEA,
        df_con_SIC_temp   = df_con_SIC_temp,
        df_emission_factor = df_emission_factor,
        IEA_country       = IEA_country,
    )
end

# ---- EDGAR ---- (SI S1.2) -------------------------------------------------

"""
    load_edgar_data(base_path)

Load EDGAR emission data (CO₂ and non-CO₂) and IPCC→SIC concordance.

Returns a NamedTuple:
- `df_ipcc_sic`  : IPCC code → SIC code concordance (DataFrame)
- `df_non_CO2`   : Non-CO₂ GHG emissions by country/IPCC sector (DataFrame)
- `df_EDGAR_CO2` : CO₂ emissions by country/IPCC sector (DataFrame)
"""
function load_edgar_data(base_path::String)
    data_dir = joinpath(base_path, "data/GHG/Edgar")
    df_ipcc_sic  = CSV.read(joinpath(data_dir, "df_ipcc_sic.csv"), DataFrame, types = Dict("SIC_CODE" => String))
    df_non_CO2   = CSV.read(joinpath(data_dir, "df_non_CO2.csv"), DataFrame)
    df_EDGAR_CO2 = CSV.read(joinpath(data_dir, "df_EDGAR_CO2.csv"), DataFrame)
    return (
        df_ipcc_sic  = df_ipcc_sic,
        df_non_CO2   = df_non_CO2,
        df_EDGAR_CO2 = df_EDGAR_CO2,
    )
end

# ---- FactSet Entity Concordance -------------------------------------------

"""
    load_sec_entity(import_path)

Load FactSet entity concordance tables (FSYM_ID ↔ FACTSET_ENTITY_ID).

Returns a NamedTuple:
- `full`              : Combined concordance DataFrame
- `ff_sec_entity`     : Financial data concordance
- `sc_ship_sec_entity`: Shipping data concordance
- `ent_scr_sec_entity`: Supply-chain data concordance
"""
function load_sec_entity(import_path::String)
    ff = CSV.read(
        joinpath(import_path, "FactSet/Financial/ff_sec_entity.txt"),
        DataFrame, delim = "|",
    )
    sc = CSV.read(
        joinpath(import_path, "FactSet/Shipping/sc_ship_sec_entity.txt"),
        DataFrame, delim = "|",
    )
    ent = CSV.read(
        joinpath(import_path, "FactSet/Supplychain/ent_scr_sec_entity.txt"),
        DataFrame, delim = "|",
    )
    full = unique([sc; ent; ff])
    return (
        full              = full,
        ff_sec_entity     = ff,
        sc_ship_sec_entity = sc,
        ent_scr_sec_entity = ent,
    )
end

# ---- Segment Base Data ----------------------------------------------------

"""
    load_segment_base(import_path)

Load the arranged base segment data (company segments, sales, SIC codes).

Returns a NamedTuple:
- `nt_arranged_base_segment` : Full NamedTuple from JLD2
- `df_segment`               : Industry mapping DataFrame
"""
function load_segment_base(import_path::String)
    path_p = joinpath(import_path, "tmp/")
    filename = find_tmp_p(path_p)
    @load joinpath(path_p, filename) nt_arranged_base_segment
    df_segment = deepcopy(nt_arranged_base_segment.industry_mapping.full)
    return (
        nt_arranged_base_segment = nt_arranged_base_segment,
        df_segment = df_segment,
    )
end
