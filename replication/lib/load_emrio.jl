# ============================================================================
# load_emrio.jl — Load the EMRIO (Enterprise-level MRIO) database.
#
# Original: module/GHG_footprint/load_EMRIO.jl
# Paper reference: Main text Eq. 3 (EMRIO transaction matrix T structure),
#                  Section 3.1 "Construction of firm-level footprints"
#
# The EMRIO transaction matrix T has the block structure:
#   T = [ T1         T_q_RoWd   ]
#       [ T_RoW_qd   T_RoW_RoWd ]
#
# where T1 is the bilateral trade matrix between tracked countries,
# and the RoW row/column captures Rest-of-World flows.
# ============================================================================
#
# NOTICE: This file depends on external files under import.
# Required import dependencies:
#   load_emrio(emrio_path, import_path, ...) reads:
#   - <DATA_ROOT>/IO/EIO/EMRIO/2015/20240228.jld2
#     (EMRIO database; file selected by get_file_with_highest_number())
#   - <DATA_ROOT>/FactSet/Financial/ff_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Shipping/sc_ship_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Supplychain/ent_scr_sec_entity.txt
#   - <DATA_ROOT>/tmp/nt_arranged_base_segment_20231210.jld2
#     (via load_segment_base → load_sec_entity in load_emissions_data.jl)
# Please ensure these files are available when running this replication script.

"""
    load_emrio(emrio_path, import_path, iea_data, yr; version="auto")

Load the full EMRIO database and compute derived quantities.

# Arguments
- `emrio_path`  : Path to EMRIO JLD2 directory (e.g. `.../EMRIO/2015`)
- `import_path` : Path to external data root
- `iea_data`    : Output of `load_iea_data()` (needed for RoW computation)
- `yr`          : Analysis year
- `version`     : `"auto"` to pick highest-numbered file, or specific version

# Returns a NamedTuple:
- `nt_EMRIO`    : Raw EMRIO NamedTuple from JLD2
- `T`           : Full world transaction matrix (Eq. 3)
- `info_q`      : Row subsegment attributes (producers/suppliers)
- `info_qd`     : Column subsegment attributes (consumers/customers)
- `g_RoW`       : Rest-of-World emissions (SI S1.4 Eq. S1-6)
- `intst_RoW`   : RoW emission intensity (g_RoW / xRoWd)
- `country_list`: List of countries in the EMRIO
- `df_p_all`    : Segment-level data with SIC codes (from arranged base)
- `df_segment`  : Industry mapping DataFrame
- `nt_arranged_base_segment` : Full arranged segment NamedTuple
"""
function load_emrio(emrio_path::String, import_path::String, iea_data, yr::Int;
                    version::String="auto")
    # --- Find and load EMRIO JLD2 ---
    if version == "auto"
        filename = get_file_with_highest_number(emrio_path)
    else
        filename = version * ".jld2"
    end
    @load joinpath(emrio_path, filename) nt_EMRIO

    # --- Extract core matrices ---
    T1 = nt_EMRIO.EMRIO_T                    # Bilateral trade matrix
    T_RoW_qd = nt_EMRIO.T_RoW_qd            # RoW → tracked countries
    T_q_RoWd = nt_EMRIO.T_q_RoWd            # Tracked countries → RoW
    T_RoW_RoWd = nt_EMRIO.T_RoW_RoWd        # RoW → RoW

    # Eq. 3: Assemble full world transaction matrix
    T = [T1 T_q_RoWd; T_RoW_qd T_RoW_RoWd]

    # --- Subsegment attributes ---
    info_q = deepcopy(nt_EMRIO.att_q)        # Row subsegments (suppliers)
    info_qd = deepcopy(nt_EMRIO.att_qd)      # Column subsegments (customers)

    # --- Country list ---
    # Defensive unique() in case att_r has duplicate entries
    country_list = unique(nt_EMRIO.att_r.ISO_COUNTRY_r)

    # --- RoW emissions (SI S1.4 Eq. S1-6) ---
    g_RoW = compute_g_RoW(nt_EMRIO, iea_data, yr)
    intst_RoW = g_RoW / nt_EMRIO.xRoWd

    # --- Segment base data ---
    seg = load_segment_base(import_path)
    df_segment = seg.df_segment
    nt_arranged_base_segment = seg.nt_arranged_base_segment

    df_p_all = @linq deepcopy(
        nt_arranged_base_segment.segment.ff_segbus_af_watt_sales_va_conv_segment
    ) |> dropmissing(:FF_SIC_CODE)

    return (
        nt_EMRIO     = nt_EMRIO,
        T            = T,
        info_q       = info_q,
        info_qd      = info_qd,
        g_RoW        = g_RoW,
        intst_RoW    = intst_RoW,
        country_list = country_list,
        df_p_all     = df_p_all,
        df_segment   = df_segment,
        nt_arranged_base_segment = nt_arranged_base_segment,
    )
end
