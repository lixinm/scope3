# ============================================================================
# load_country_io.jl — Load country-specific IO/SUT data from EMRIO.
#
# Original: module/GHG_footprint/load_tmps.jl
#
# Wraps the original include-based loader into a function that returns
# a NamedTuple instead of injecting global variables.
# ============================================================================
#
# NOTICE: This file depends on external files under import.
# Required import dependencies:
#   load_country_io(country, yr, import_path, ...) reads:
#   - <DATA_ROOT>/IO/EIO/DEIO/{COUNTRY}/{YEAR}/data_*.jld2
#     (e.g., .../DEIO/USA/2015/data_20240224.jld2)
#     71 countries for YEAR=2015; file selected by find_file_with_max_digits()
# Please ensure these files are available when running this replication script.

"""
    load_country_io(country, yr, import_path, info_qd)

Load country-specific Input-Output / Supply-Use Table data.

# Arguments
- `country`     : ISO 3-letter country code (e.g. "USA")
- `yr`          : Analysis year
- `import_path` : Path to external data (IMPORT_PATH from config)
- `info_qd`     : EMRIO column subsegment attributes (nt_EMRIO.att_qd)

# Returns a NamedTuple:
- `nt_data`   : Full country IO NamedTuple from JLD2
- `sales_cpq` : Subsegments in this country with non-missing sales (DataFrame)
- `col_SIC`   : SECTOR_CODE ↔ SIC_CODE concordance for this country (DataFrame)
- `desc_j`    : Customer sector descriptions (DataFrame)
"""
function load_country_io(country::String, yr::Int, import_path::String, info_qd)
    path_y = path_c_y(import_path, country, yr)
    new_data_file = find_file_with_max_digits(path_y)
    @load joinpath(path_y, new_data_file) nt_data_country_r

    # Filter EMRIO column subsegments for this country with valid sales
    mask = (info_qd.ISO_COUNTRY .== country) .& (info_qd.FF_SALES_modified_estimated_unconsolidated_cpq .!== missing)
    sales_cpq = info_qd[mask, :]

    # Build SIC concordance for this country's sectors
    col_SIC = j_SIC(
        nt_data_country_r.C_j_sic,
        nt_data_country_r.num_j.SECTOR_CODE,
        nt_data_country_r.C_j_sic_col.SIC_CODE,
    )

    desc_j = nt_data_country_r.desc_j

    return (
        nt_data   = nt_data_country_r,
        sales_cpq = sales_cpq,
        col_SIC   = col_SIC,
        desc_j    = desc_j,
    )
end
