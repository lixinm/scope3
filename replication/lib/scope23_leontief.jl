# ============================================================================
# scope23_leontief.jl — Leontief inverse & Scope 2/3 calculation.
#
# Original: controller/main.ipynb Cells 5-8
# Paper reference: Main Eq. 5 (Leontief), Eq. 7 (Scope 2), Eq. 8 (Scope 3)
#                  SI S4 (energy sector identification), SI S5 (Scope 2)
#
# This file contains three functions:
#   1. identify_energy_sectors() — Cell 7: identify energy supply sectors
#      per country using SIC codes (4911-4925) and the C_i_j concordance
#   2. build_energy_intensity_vector() — Cell 8 part 1: build f_ener vector
#   3. compute_scope23() — Cells 5-6, 8: full Leontief + Scope 2/3 pipeline
# ============================================================================
#
# NOTICE: This file depends on external files under import.
# Required import dependencies:
#   identify_energy_sectors() and compute_scope23() call load_country_io()
#   for each country, which reads:
#   - <DATA_ROOT>/IO/EIO/DEIO/{COUNTRY}/2015/data_20240224.jld2
#     (71 countries; see config.jl for the full list)
# Please ensure these files are available when running this replication script.

# Energy supply SIC codes (SI S4, Table S4-1)
const ENERGY_SIC_CODES = ["4911", "4922", "4923", "4924", "4925"]

"""
    identify_energy_sectors(country_list, nt_EMRIO, import_path, yr, info_qd)

Identify energy supply sectors for each country in the EMRIO.

For each country, loads the country IO data and identifies:
- `Dict_energy[country]` : list of commodity SECTOR_CODEs that are energy sectors
- `DICT_energy_Cij[(country, consumer_sector)]` : maps consumer → producer energy sector

# Arguments
- `country_list` : Vector of ISO country codes
- `nt_EMRIO`     : Raw EMRIO NamedTuple
- `import_path`  : Path to external data
- `yr`           : Analysis year
- `info_qd`      : EMRIO column subsegment attributes

# Returns (Dict_energy, DICT_energy_Cij)
"""
function identify_energy_sectors(country_list, nt_EMRIO, import_path, yr, info_qd)
    Dict_energy = Dict()
    DICT_energy_Cij = Dict()

    for c in country_list
        country = c

        # Load country IO data (wraps load_tmps.jl)
        cio = load_country_io(country, yr, import_path, info_qd)
        nt_data_country_r = cio.nt_data
        col_SIC = cio.col_SIC
        sic_col_num = nt_data_country_r.C_j_sic_col

        # For "pp" (product-by-product) IO type countries, remap C→I in SECTOR_CODE
        if country ∈ nt_EMRIO.att_r[nt_EMRIO.att_r.IO_TYPE_r .== "pp", :ISO_COUNTRY_r]
            col_SIC.SECTOR_CODE = replace.(col_SIC.SECTOR_CODE, "C" => "I")
        end

        # Identify energy SIC columns
        energy_SIC_col = sic_col_num[sic_col_num.SIC_CODE .∈ (ENERGY_SIC_CODES,), :COL_NUMBER]

        # Industry energy sectors (j-side, producer)
        list_energy_j = unique(col_SIC[col_SIC.SIC_CODE .∈ (ENERGY_SIC_CODES,), :SECTOR_CODE])

        # For each energy producer sector, find its consumer sectors via C_i_j
        for j1 in list_energy_j
            j1_col_idx = findfirst(nt_data_country_r.desc_j.SECTOR_CODE .== j1)
            if !isnothing(j1_col_idx)
                specified_column = nt_data_country_r.C_i_j[:, j1_col_idx]
                rows_with_ones = findall(x -> x == 1, specified_column)
                for i1 in nt_data_country_r.desc_i[rows_with_ones, :SECTOR_CODE]
                    DICT_energy_Cij[(country, i1)] = j1
                end
            end
        end

        # Commodity energy sectors (i-side, consumer)
        i_col = vec(sum(nt_data_country_r.C_i_sic[:, energy_SIC_col], dims=2))
        list_energy_i = nt_data_country_r.desc_i[i_col .> 0, :SECTOR_CODE]

        Dict_energy[country] = list_energy_i
    end

    return (Dict_energy, DICT_energy_Cij)
end


"""
    build_energy_intensity_vector(info_q_agg, f, nt_EMRIO, Dict_energy, DICT_energy_Cij)

Build the energy emission intensity vector f_ener for Scope 2 calculation.

For each row subsegment after aggregation:
- If it's an OS energy sector with a known energy producer mapping → use
  the emission intensity of the corresponding energy producer OS
- If it's a NOS energy sector → use its own emission intensity
- Otherwise → 0 (not an energy sector)

# Arguments
- `info_q_agg`       : Row subsegment attributes after aggregation
- `f`                : Emission intensity vector (1×n from nos_aggregate)
- `nt_EMRIO`         : Raw EMRIO NamedTuple
- `Dict_energy`      : country → energy sector codes
- `DICT_energy_Cij`  : (country, consumer_sector) → producer energy sector

# Returns
- `f_ener` : Vector{Float64} of energy emission intensities (length = nrow(info_q_agg))
"""
function build_energy_intensity_vector(info_q_agg, f, nt_EMRIO, Dict_energy, DICT_energy_Cij)
    # Work on row subsegments (info_q_agg)
    info_q1 = deepcopy(
        info_q_agg[:, [:FACTSET_ENTITY_ID_SEGMENT_SUB, :ROW_SECTOR_CODE, :SECTOR_CODE,
                        :PROPER_NAME, :ISO_COUNTRY]]
    )

    f_ener = []
    for row in eachrow(info_q1)
        if row.ROW_SECTOR_CODE !== missing &&
           row.ROW_SECTOR_CODE ∈ Dict_energy[row.ISO_COUNTRY] &&
           occursin("Others", row.FACTSET_ENTITY_ID_SEGMENT_SUB) &&
           (row.ISO_COUNTRY, row.ROW_SECTOR_CODE) in keys(DICT_energy_Cij)
            # OS energy sector with known producer mapping:
            # use intensity from the corresponding energy producer OS
            push!(f_ener,
                f[1:end-1][
                    (info_q1.FACTSET_ENTITY_ID_SEGMENT_SUB .== string("Others-",
                        DICT_energy_Cij[(row.ISO_COUNTRY, row.ROW_SECTOR_CODE)], "-S")) .&
                    (info_q1.ISO_COUNTRY .== row.ISO_COUNTRY)
                ][1]
            )
        elseif row.ROW_SECTOR_CODE !== missing &&
               row.ROW_SECTOR_CODE ∈ Dict_energy[row.ISO_COUNTRY] &&
               !occursin("Others", row.FACTSET_ENTITY_ID_SEGMENT_SUB)
            # NOS energy sector: use its own emission intensity
            push!(f_ener,
                f[1:end-1][info_q1.FACTSET_ENTITY_ID_SEGMENT_SUB .== row.FACTSET_ENTITY_ID_SEGMENT_SUB][1]
            )
        else
            # Not an energy sector
            push!(f_ener, 0.0)
        end
    end

    f_ener = convert(Vector{Float64}, f_ener)
    return f_ener
end


"""
    compute_scope23(agg, nt_EMRIO, country_list, import_path, yr, info_qd_orig)

Compute Scope 2+3, Scope 2, and Scope 3 emissions using Leontief inverse.

This is the core calculation implementing:
- Main Eq. 5: L = (I - A)^{-1}  (Leontief inverse)
- Main Eq. 6: e = f × L           (total emission multipliers)
- Main Eq. 7: g_S2 = f_ener' × T  (energy supply chain emissions)
- Main Eq. 8: g_S3 = g_S23 - g_S2 (full supply chain minus energy)

# Arguments
- `agg`           : Output of nos_aggregate() (NamedTuple with T_agg, f, A, I_EMRIO, etc.)
- `nt_EMRIO`      : Raw EMRIO NamedTuple
- `country_list`  : Vector of ISO country codes
- `import_path`   : Path to external data
- `yr`            : Analysis year
- `info_qd_orig`  : Original EMRIO column subsegment attributes (before aggregation)

# Returns a NamedTuple:
- `df_q_est`   : DataFrame with columns: ISO_COUNTRY, SECTOR_CODE, FACTSET_ENTITY_ID,
                  FACTSET_ENTITY_ID_SEGMENT_SUB, g_S1, g_S2_EMRIO, g_S23_EMRIO, g_S3_T
- `t_Leon_full`: Leontief inverse matrix (for verification)
- `e_g23`      : Total emission multiplier vector (for verification)
- `f_ener`     : Energy intensity vector (for verification)
"""
function compute_scope23(agg, nt_EMRIO, country_list, import_path, yr, info_qd_orig)

    T_agg       = agg.T_agg
    f           = agg.f
    A           = agg.A
    I_EMRIO     = agg.I_EMRIO
    info_qd_agg = agg.info_qd_agg
    info_q_agg  = agg.info_q_agg
    g_agg       = agg.g_agg

    # ------------------------------------------------------------------
    # Leontief inverse (Main Eq. 5)
    #   L = (I - A)^{-1}
    # ------------------------------------------------------------------
    println("  Computing Leontief inverse...")
    IA = Matrix(I_EMRIO - A)
    t_Leon_full = inv(IA)
    println("  Leontief inverse computed. Size: ", size(t_Leon_full))

    # ------------------------------------------------------------------
    # Total emission multiplier (Main Eq. 6)
    #   e = f × L
    # ------------------------------------------------------------------
    e_g23 = f * t_Leon_full
    n_neg = count(x -> x < 0, e_g23)
    n_neg > 0 && println("  Warning: $n_neg negative values in e_g23")

    # ------------------------------------------------------------------
    # Identify energy sectors (SI S4)
    # ------------------------------------------------------------------
    println("  Identifying energy sectors across $(length(country_list)) countries...")
    (Dict_energy, DICT_energy_Cij) = identify_energy_sectors(
        country_list, nt_EMRIO, import_path, yr, info_qd_orig
    )

    # ------------------------------------------------------------------
    # Build energy emission intensity vector (SI S5)
    # ------------------------------------------------------------------
    println("  Building energy intensity vector...")
    f_ener = build_energy_intensity_vector(
        info_q_agg, f, nt_EMRIO, Dict_energy, DICT_energy_Cij
    )

    # ------------------------------------------------------------------
    # Zero out SUT country rows in e_g23
    # (Original: Cell 8, lines with list_ind)
    # Countries with Supply-Use Tables (SUT) have industry sectors that
    # should not propagate emissions through the Leontief multiplier.
    # ------------------------------------------------------------------
    list_ind = []
    info_q_agg_tmp = deepcopy(info_q_agg)
    info_q_agg_tmp[!, :row_num_agg] = collect(1:nrow(info_q_agg_tmp))
    for row in eachrow(info_q_agg_tmp)
        if row.ISO_COUNTRY ∈ nt_EMRIO.att_r[nt_EMRIO.att_r.IO_TYPE_r .== "SUT", :ISO_COUNTRY_r] &&
           row.SECTOR_CODE !== missing
            push!(list_ind, row.row_num_agg)
        end
    end
    e_g23[list_ind] .= 0.0

    # ------------------------------------------------------------------
    # Scope 2+3: propagate through transaction matrix (Main Eq. 6-7)
    #   g_S23 = e × T_agg  (column vector of total supply chain emissions)
    # ------------------------------------------------------------------
    s23 = vec(e_g23 * T_agg)[1:end-1]
    info_qd_agg.g_S23_EMRIO = s23

    # ------------------------------------------------------------------
    # Scope 2: energy supply chain emissions (Main Eq. 7)
    #   g_S2 = f_ener' × T_agg[1:end-1, 1:end-1]
    # ------------------------------------------------------------------
    g_S2_EMRIO = transpose(transpose(f_ener) * T_agg[1:end-1, 1:end-1])
    info_qd_agg[!, :g_S1] = g_agg[1:end-1]
    info_qd_agg.g_S2_EMRIO = g_S2_EMRIO
    # Recompute g_S23 after SUT zeroing (overwrites with post-zeroing values)
    info_qd_agg.g_S23_EMRIO = vec(e_g23 * T_agg)[1:end-1]

    # ------------------------------------------------------------------
    # Assemble output DataFrame
    # ------------------------------------------------------------------
    df_q_est = info_qd_agg[:, [
        :ISO_COUNTRY, :SECTOR_CODE,
        :FACTSET_ENTITY_ID,
        :FACTSET_ENTITY_ID_SEGMENT_SUB,
        :g_S1, :g_S2_EMRIO, :g_S23_EMRIO
    ]]

    # ------------------------------------------------------------------
    # Scope 3 (Main Eq. 8): g_S3 = g_S23 - g_S2
    # ------------------------------------------------------------------
    df_q_est[!, :g_S2_EMRIO] = transpose(transpose(f_ener) * T_agg[1:end-1, 1:end-1])
    df_q_est.g_S3_T = df_q_est.g_S23_EMRIO .- df_q_est.g_S2_EMRIO

    n_neg_s3 = count(x -> x < 0.0, df_q_est.g_S3_T)
    n_neg_s3 > 0 && println("  Note: $n_neg_s3 subsegments with negative Scope 3")

    return (
        df_q_est    = df_q_est,
        t_Leon_full = t_Leon_full,
        e_g23       = e_g23,
        f_ener      = f_ener,
    )
end
