# ============================================================================
# figure_data.jl — Generate figure-ready CSVs from q_est output.
#
# Original: scripts/GHG_scope_analyis/fig_country.ipynb (Cells 0-12)
# Paper reference: Figure 1 (country comparison), Figure 2 (triangle plot)
#
# Two public functions:
#   generate_triangle_data()  — segment-level data with SIC categories
#   generate_country_data()   — company-level estimated vs reported Scope 3
#
# Both share initial processing via _prepare_q_est_with_cdp().
# ============================================================================

# ------------------------------------------------------------------
# Internal: shared pre-processing for both figure data functions
# ------------------------------------------------------------------
"""
    _prepare_q_est_with_cdp(df_q_est, emrio_data, yr, base_path, import_path)

Shared pre-processing: enrich q_est with sales/DATE, allocate CDP Scope 2,
compute g_S2_est and g_S3_est.

Returns (df_g_q, Dict_r_uncon, df_segment, df_g3_CDP_up)
"""
function _prepare_q_est_with_cdp(df_q_est, emrio_data, yr, base_path, import_path)

    # --- Extract sales/DATE from EMRIO att_qd (original Cell 0) ---
    x_qd = dropmissing(
        deepcopy(emrio_data.nt_EMRIO.att_qd)[:, [
            :FACTSET_ENTITY_ID_SEGMENT, :FACTSET_ENTITY_ID_SEGMENT_SUB,
            :FF_SALES_modified_estimated_unconsolidated_cpq, :DATE
        ]],
        :FF_SALES_modified_estimated_unconsolidated_cpq
    )

    # --- Filter q_est: remove OS segments ---
    df_g_q = copy(df_q_est)
    mask_nos = .!(occursin.("Others-", df_g_q.FACTSET_ENTITY_ID))
    df_g_q = df_g_q[mask_nos, :]

    # --- Join with sales/DATE ---
    df_g_q = unique(
        innerjoin(df_g_q, x_qd, on = :FACTSET_ENTITY_ID_SEGMENT_SUB),
        :FACTSET_ENTITY_ID_SEGMENT_SUB
    )

    # --- Load segment data ---
    # Note: emrio_data.df_p_all is nt_arranged_base_segment.segment.ff_segbus_af_watt_sales_va_conv_segment
    # with dropmissing(:FF_SIC_CODE). This is what the original notebook calls "df_segment".
    df_segment = emrio_data.df_p_all

    # --- Aggregate x_qd to segment level (for Dict_r_uncon) ---
    x_p = combine(groupby(x_qd, :FACTSET_ENTITY_ID_SEGMENT)) do sdf
        DataFrame(
            DATE = first(sdf.DATE),
            SALES_p = sum(sdf.FF_SALES_modified_estimated_unconsolidated_cpq)
        )
    end

    # --- Load CDP Scope 2 data (company level) ---
    g_CDP_c = CSV.read(joinpath(base_path, "data/GHG/GHG_CDP/g_CDP.csv"), DataFrame)
    g_CDP_c = g_CDP_c[g_CDP_c.accounting_year .=== yr, :]
    g_CDP_c.g_S2 = map(x -> ismissing(x) ? missing : tryparse(Float64, x), g_CDP_c.g_S2)
    Dict_S2_CDP = Dict(zip(g_CDP_c.FACTSET_ENTITY_ID, g_CDP_c.g_S2))

    # --- Load CDP Scope 3 upstream data ---
    df_g3_CDP_up = CSV.read(
        joinpath(base_path, "data/GHG/GHG_CDP/g_CDP_S3_upstream.csv"), DataFrame
    )

    # --- Build Dict_r_uncon (unconsolidated/consolidated sales ratio, Cell 4) ---
    # df_p1: segment-level with consolidated sales from df_segment
    df_p1 = innerjoin(x_p, df_segment, on = [:FACTSET_ENTITY_ID_SEGMENT, :DATE])

    x_p.FACTSET_ENTITY_ID = [split(s, "_")[1] for s in x_p.FACTSET_ENTITY_ID_SEGMENT]
    df_segment1 = df_segment[(df_segment.DATE .> Date(yr - 1)) .& (df_segment.DATE .< Date(yr + 2)), :]

    df_p2 = innerjoin(
        df_segment1[:, [:FACTSET_ENTITY_ID, :DATE, :SALES]],
        x_p, on = [:FACTSET_ENTITY_ID, :DATE]
    )
    df_p2 = unique(df_p2, :FACTSET_ENTITY_ID_SEGMENT)

    df_con = combine(groupby(df_p2, :FACTSET_ENTITY_ID)) do sdf
        DataFrame(SALES_con = sum(sdf.SALES))
    end
    df_uncon = combine(groupby(df_p1, :FACTSET_ENTITY_ID)) do sdf
        DataFrame(SALES_uncon = sum(sdf.SALES_p))
    end
    df_3 = innerjoin(df_uncon, df_con, on = :FACTSET_ENTITY_ID)
    Dict_r_uncon = Dict(zip(df_3.FACTSET_ENTITY_ID, df_3.SALES_uncon ./ df_3.SALES_con))

    # --- Derive FACTSET_ENTITY_ID from subsegment ID ---
    df_g_q.FACTSET_ENTITY_ID = [split(s, "_")[1] for s in df_g_q.FACTSET_ENTITY_ID_SEGMENT_SUB]
    df_g_q[!, :g_S2_CDP] .= 0.0

    # --- Allocate CDP Scope 2 to subsegments proportional to EMRIO Scope 2 (Cell 4) ---
    for i in groupby(df_g_q, :FACTSET_ENTITY_ID)
        eid = i.FACTSET_ENTITY_ID[1]
        if eid in keys(Dict_S2_CDP) &&
           Dict_S2_CDP[eid] !== missing &&
           Dict_S2_CDP[eid] != nothing &&
           eid in keys(Dict_r_uncon)
            s2_sum = sum(i.g_S2_EMRIO)
            if s2_sum > 0
                i.g_S2_CDP .= i.g_S2_EMRIO ./ s2_sum .* Dict_S2_CDP[eid] .* Dict_r_uncon[eid]
            end
        end
    end

    # --- Compute g_S2_est, g_S3_est (Cell 5) ---
    df_g_q[!, :FACTSET_ENTITY_ID_SEGMENT] .= [s[1:findlast('_', s)-1] for s in df_g_q.FACTSET_ENTITY_ID_SEGMENT_SUB]
    df_g_q[!, :g_S3_est] .= 0.0
    df_g_q[!, :g_S2_est] .= 0.0

    for row in eachrow(df_g_q)
        if row.g_S2_CDP > 0.0
            # Prefer CDP Scope 2 when available
            row.g_S3_est = row.g_S23_EMRIO - row.g_S2_CDP
            row.g_S2_est = row.g_S2_CDP
        else
            # Fallback to EMRIO Scope 2
            row.g_S3_est = row.g_S23_EMRIO - row.g_S2_EMRIO
            row.g_S2_est = row.g_S2_EMRIO
        end
        # Sanity check: if CDP Scope 2 is >10x EMRIO, treat as outlier
        if row.g_S2_CDP > row.g_S2_EMRIO * 10
            row.g_S3_est = row.g_S23_EMRIO - row.g_S2_EMRIO
            row.g_S2_est = row.g_S2_EMRIO
        end
    end

    return (df_g_q, Dict_r_uncon, df_segment, df_g3_CDP_up)
end


# ------------------------------------------------------------------
# Public: generate triangle plot data (segment level)
# ------------------------------------------------------------------
"""
    generate_triangle_data(df_q_est, emrio_data, yr, base_path, import_path)

Generate segment-level data with SIC sector categories for the ternary plot.

Returns DataFrame with columns: FACTSET_ENTITY_ID_SEGMENT, FACTSET_ENTITY_ID,
g_S3, g_S1, g_S2, ISO_COUNTRY, DATE, SALES, YEAR, SIC_CODE, LABEL, SIC_2, SIC_1_desc
"""
function generate_triangle_data(df_q_est, emrio_data, yr, base_path, import_path)
    (df_g_q, _, df_segment, _) = _prepare_q_est_with_cdp(df_q_est, emrio_data, yr, base_path, import_path)

    # --- Aggregate subsegment → segment level (Cell 5) ---
    df_g_p = combine(groupby(df_g_q, :FACTSET_ENTITY_ID_SEGMENT)) do sdf
        DataFrame(
            FACTSET_ENTITY_ID = first(sdf.FACTSET_ENTITY_ID),
            g_S3 = sum(sdf.g_S3_est),
            g_S1 = sum(sdf.g_S1),
            g_S2 = sum(sdf.g_S2_est),
            ISO_COUNTRY = first(sdf.ISO_COUNTRY),
            DATE = first(sdf.DATE),
            SALES = sum(sdf.FF_SALES_modified_estimated_unconsolidated_cpq),
            YEAR = yr
        )
    end

    # --- Join with SIC codes (Cell 10) ---
    df_p = innerjoin(
        df_g_p,
        df_segment[:, [:FACTSET_ENTITY_ID_SEGMENT, :DATE, :FF_SIC_CODE]],
        on = [:FACTSET_ENTITY_ID_SEGMENT, :DATE]
    )

    # --- Apply SIC modifications (Cell 11) ---
    @load joinpath(base_path, "data/tmp_files/df_SIC_desc.jld2") df_SIC_desc

    df_SIC_mod = @linq CSV.read(
        joinpath(base_path, "data/for_app/p_SIC_mod.csv"), DataFrame
    ) |> unique(:FACTSET_ENTITY_ID_SEGMENT)

    # Segments with modified SIC
    df_mod = innerjoin(
        select(df_p, Not(:FF_SIC_CODE)),
        df_SIC_mod[:, [:FACTSET_ENTITY_ID_SEGMENT, :SIC_mod]],
        on = :FACTSET_ENTITY_ID_SEGMENT
    )
    rename!(df_mod, :SIC_mod => :SIC_CODE)

    # Segments with original SIC
    df_unmod = @linq antijoin(
        df_p, df_SIC_mod[:, [:FACTSET_ENTITY_ID_SEGMENT, :SIC_mod]],
        on = :FACTSET_ENTITY_ID_SEGMENT
    ) |> rename!(:FF_SIC_CODE => :SIC_CODE)

    df_out = vcat(df_unmod, df_mod)

    # --- Add SIC descriptions ---
    Dict_SIC = Dict(zip(tryparse.(Int, df_SIC_desc.SIC_CODE), df_SIC_desc.SIC_DESC))
    df_out.LABEL = getindex.(Ref(Dict_SIC), df_out.SIC_CODE)

    # --- Add 2-digit SIC ---
    df_out[!, :SIC_2] .= string.(df_out.SIC_CODE .÷ 100)

    # --- Filter positive emissions ---
    df_out = df_out[df_out.g_S1 .> 0, :]
    df_out = df_out[df_out.g_S2 .> 0, :]
    df_out = df_out[df_out.g_S3 .> 0, :]

    # --- Map to 1-digit SIC sector categories (10 categories) ---
    Dic_1_digit_list = Dict(
        1:9   => "Agriculture, Forestry and Fishing",
        10:14 => "Mining",
        15:19 => "Construction",
        20:39 => "Manufacturing",
        40:49 => "Transportation, Communications, Electric, Gas and Sanitary service",
        50:51 => "Wholesale Trade",
        52:59 => "Retail Trade",
        60:67 => "Finance, Insurance and Real Estate",
        70:89 => "Services",
        91:99 => "Public Administration",
    )
    Dic_single_digit = Dict{String, String}()
    for (range, label) in Dic_1_digit_list
        for num in range
            Dic_single_digit[string(num)] = label
        end
    end

    df_out[!, :SIC_1_desc] = getindex.(Ref(Dic_single_digit), df_out.SIC_2)
    df_out = df_out[df_out.SIC_1_desc .!= "Nonclassifiable", :]

    return df_out
end


# ------------------------------------------------------------------
# Public: generate country comparison data (company level)
# ------------------------------------------------------------------
"""
    generate_country_data(df_q_est, emrio_data, yr, base_path, import_path)

Generate company-level data comparing EMRIO-estimated vs CDP-reported Scope 3.

Returns DataFrame with columns: FACTSET_ENTITY_ID, ISO_COUNTRY, YEAR,
g_S3_est, SALES, accounting_year, g_S3_CDP_c
"""
function generate_country_data(df_q_est, emrio_data, yr, base_path, import_path)
    (df_g_q, Dict_r_uncon, _, df_g3_CDP_up) = _prepare_q_est_with_cdp(
        df_q_est, emrio_data, yr, base_path, import_path
    )

    # --- Aggregate CDP Scope 3 upstream by company (Cell 0) ---
    df_g3_CDP = combine(groupby(df_g3_CDP_up, [:FACTSET_ENTITY_ID, :accounting_year])) do sdf
        DataFrame(g_S3_CDP_c = sum(sdf.value))
    end
    df_g3_CDP = df_g3_CDP[df_g3_CDP.accounting_year .== yr, :]

    # --- Aggregate to company level (Cell 5) ---
    df_g_c = combine(groupby(df_g_q, :FACTSET_ENTITY_ID)) do sdf
        DataFrame(
            g_S3_est = sum(sdf.g_S3_est),
            ISO_COUNTRY = first(sdf.ISO_COUNTRY),
            SALES = sum(sdf.FF_SALES_modified_estimated_unconsolidated_cpq),
            YEAR = yr
        )
    end

    # --- Join estimated with CDP reported (Cell 5) ---
    df_fig = @linq innerjoin(
        df_g_c[:, [:FACTSET_ENTITY_ID, :ISO_COUNTRY, :YEAR, :g_S3_est, :SALES]],
        df_g3_CDP,
        on = [:FACTSET_ENTITY_ID => :FACTSET_ENTITY_ID]
    ) |> unique(:FACTSET_ENTITY_ID)

    # --- Filter ---
    df_fig1 = df_fig[df_fig.g_S3_est .> 1.0, :]
    df_fig1 = df_fig1[df_fig1.g_S3_CDP_c .> 0, :]

    # --- Scale CDP by unconsolidated ratio ---
    df_fig1_ids = df_fig1.FACTSET_ENTITY_ID
    scale_factors = [get(Dict_r_uncon, id, 1.0) for id in df_fig1_ids]
    df_fig1.g_S3_CDP_c = df_fig1.g_S3_CDP_c .* scale_factors

    # --- Keep only companies with row==1 CDP data (purchased goods & services) ---
    df_g3_CDP_row_1 = df_g3_CDP_up[df_g3_CDP_up.row .== 1, :]
    df_g3_CDP_row_1 = df_g3_CDP_row_1[df_g3_CDP_row_1.value .> 0, :]
    df_fig1 = df_fig1[df_fig1.FACTSET_ENTITY_ID .∈ (df_g3_CDP_row_1.FACTSET_ENTITY_ID,), :]

    return df_fig1
end


# ------------------------------------------------------------------
# Public: generate country comparison data for APPENDIX (all CDP reporters)
# ------------------------------------------------------------------
"""
    generate_country_data_appendix(df_q_est, emrio_data, yr, base_path, import_path)

Generate company-level data comparing EMRIO-estimated vs CDP-reported Scope 3
for the appendix figure. Unlike `generate_country_data()`, this function keeps
ALL companies with any CDP Scope 3 data (no row==1 filter).

Returns DataFrame with columns: FACTSET_ENTITY_ID, ISO_COUNTRY, YEAR,
g_S3_est, SALES, g_S3_CDP_c
"""
function generate_country_data_appendix(df_q_est, emrio_data, yr, base_path, import_path)
    (df_g_q, Dict_r_uncon, _, df_g3_CDP_up) = _prepare_q_est_with_cdp(
        df_q_est, emrio_data, yr, base_path, import_path
    )

    # --- Aggregate CDP Scope 3 upstream by company ---
    df_g3_CDP = combine(groupby(df_g3_CDP_up, [:FACTSET_ENTITY_ID, :accounting_year])) do sdf
        DataFrame(g_S3_CDP_c = sum(sdf.value))
    end
    df_g3_CDP = df_g3_CDP[df_g3_CDP.accounting_year .== yr, :]

    # --- Aggregate to company level ---
    df_g_c = combine(groupby(df_g_q, :FACTSET_ENTITY_ID)) do sdf
        DataFrame(
            g_S3_est = sum(sdf.g_S3_est),
            ISO_COUNTRY = first(sdf.ISO_COUNTRY),
            SALES = sum(sdf.FF_SALES_modified_estimated_unconsolidated_cpq),
            YEAR = yr
        )
    end

    # --- Join estimated with CDP reported ---
    df_fig = @linq innerjoin(
        df_g_c[:, [:FACTSET_ENTITY_ID, :ISO_COUNTRY, :YEAR, :g_S3_est, :SALES]],
        df_g3_CDP,
        on = [:FACTSET_ENTITY_ID => :FACTSET_ENTITY_ID]
    ) |> unique(:FACTSET_ENTITY_ID)

    # --- Filter ---
    df_fig1 = df_fig[df_fig.g_S3_est .> 1.0, :]
    df_fig1 = df_fig1[df_fig1.g_S3_CDP_c .> 0, :]

    # --- Scale CDP by unconsolidated ratio ---
    df_fig1_ids = df_fig1.FACTSET_ENTITY_ID
    scale_factors = [get(Dict_r_uncon, id, 1.0) for id in df_fig1_ids]
    df_fig1.g_S3_CDP_c = df_fig1.g_S3_CDP_c .* scale_factors

    # NOTE: No row==1 filter here (unlike generate_country_data).
    # This keeps all companies with any CDP Scope 3 data for the appendix figure.

    # --- Select output columns (no accounting_year) ---
    return df_fig1[:, [:FACTSET_ENTITY_ID, :ISO_COUNTRY, :YEAR, :g_S3_est, :SALES, :g_S3_CDP_c]]
end


# ------------------------------------------------------------------
# Public: generate boxplot data (company level, ALL companies)
# ------------------------------------------------------------------
"""
    generate_boxplot_data(df_q_est, emrio_data, yr, base_path)

Generate company-level emission intensity data for the reporter boxplot.

Unlike generate_country_data(), this function:
  - Does NOT allocate CDP Scope 2 (the original notebook has that code
    commented out in fig_S3_reporter.ipynb Cell 1)
  - Uses g_CDP_S3.csv (aggregated Scope 3), not g_CDP_S3_upstream.csv
  - Uses leftjoin to keep ALL companies, not just CDP reporters
  - Computes S123 = g_S23_EMRIO + g_S1 (total emission intensity metric)

These differences mean this function cannot share _prepare_q_est_with_cdp()
and implements its own preprocessing path.

Original: scripts/GHG_scope_analyis/fig_S3_reporter.ipynb Cells 0-8

# Arguments
- `df_q_est`   : q_est DataFrame from Step 4
- `emrio_data` : Output of load_emrio() (needs nt_EMRIO.att_qd for sales/DATE)
- `yr`         : Analysis year
- `base_path`  : BASE_PATH (for CDP data under data/GHG/GHG_CDP/)

# Returns (df_c, g_CDP_c):
- `df_c`     : Company-level DataFrame with columns:
                FACTSET_ENTITY_ID, ISO_COUNTRY, YEAR, S123, g_S1, g_S3_est,
                g_S23_EMRIO, SALES, accounting_year, g_S3_CDP_c
                (g_S3_CDP_c is missing for companies without CDP Scope 3 data)
- `g_CDP_c`  : CDP company DataFrame filtered for `yr` (used by Python script
                to classify companies into reporter/non-reporter/NA groups)
"""
function generate_boxplot_data(df_q_est, emrio_data, yr, base_path)

    # ------------------------------------------------------------------
    # Step 1: Extract sales/DATE from EMRIO att_qd
    # (Same initial extraction as _prepare_q_est_with_cdp, but we do NOT
    #  proceed to CDP Scope 2 allocation)
    # ------------------------------------------------------------------
    x_qd = dropmissing(
        deepcopy(emrio_data.nt_EMRIO.att_qd)[:, [
            :FACTSET_ENTITY_ID_SEGMENT, :FACTSET_ENTITY_ID_SEGMENT_SUB,
            :FF_SALES_modified_estimated_unconsolidated_cpq, :DATE
        ]],
        :FF_SALES_modified_estimated_unconsolidated_cpq
    )

    # ------------------------------------------------------------------
    # Step 2: Filter q_est — remove OS segments ("Others-")
    # ------------------------------------------------------------------
    df_g_q = copy(df_q_est)
    df_g_q = df_g_q[.!(occursin.("Others-", df_g_q.FACTSET_ENTITY_ID)), :]

    # ------------------------------------------------------------------
    # Step 3: Join with sales/DATE from EMRIO
    # ------------------------------------------------------------------
    df_g_q = unique(
        innerjoin(df_g_q, x_qd, on = :FACTSET_ENTITY_ID_SEGMENT_SUB),
        :FACTSET_ENTITY_ID_SEGMENT_SUB
    )

    # ------------------------------------------------------------------
    # Step 4: Derive entity ID and segment ID
    # ------------------------------------------------------------------
    df_g_q.FACTSET_ENTITY_ID = [split(s, "_")[1] for s in df_g_q.FACTSET_ENTITY_ID_SEGMENT_SUB]
    df_g_q[!, :FACTSET_ENTITY_ID_SEGMENT] .= [
        s[1:findlast('_', s)-1] for s in df_g_q.FACTSET_ENTITY_ID_SEGMENT_SUB
    ]

    # ------------------------------------------------------------------
    # Step 5: Compute g_S3_est using ONLY EMRIO Scope 2
    # (Original notebook fig_S3_reporter.ipynb has CDP S2 allocation
    #  commented out — so g_S3_est = g_S23_EMRIO - g_S2_EMRIO directly)
    # ------------------------------------------------------------------
    df_g_q[!, :g_S3_est] .= df_g_q.g_S23_EMRIO .- df_g_q.g_S2_EMRIO

    # ------------------------------------------------------------------
    # Step 6: Aggregate to company level
    # (Original: fig_S3_reporter.ipynb Cell 4)
    # ------------------------------------------------------------------
    df_g_c = combine(groupby(df_g_q, :FACTSET_ENTITY_ID)) do sdf
        DataFrame(
            g_S1 = sum(sdf.g_S1),
            g_S3_est = sum(sdf.g_S3_est),
            g_S23_EMRIO = sum(sdf.g_S23_EMRIO),
            ISO_COUNTRY = first(sdf.ISO_COUNTRY),
            SALES = sum(sdf.FF_SALES_modified_estimated_unconsolidated_cpq),
            YEAR = yr
        )
    end

    # ------------------------------------------------------------------
    # Step 7: Compute S123 = total EMRIO emissions (Scope 1 + Scope 2+3)
    # and filter for positive values
    # (Original: fig_S3_reporter.ipynb Cell 6)
    # ------------------------------------------------------------------
    df_g_c.S123 = df_g_c.g_S23_EMRIO .+ df_g_c.g_S1
    df_g_c = df_g_c[df_g_c.g_S3_est .> 0, :]

    # ------------------------------------------------------------------
    # Step 8: Load CDP Scope 3 aggregated data (g_CDP_S3.csv)
    # Note: This is the AGGREGATED total, not the per-category upstream file.
    # (Original: fig_S3_reporter.ipynb Cell 1-2)
    # ------------------------------------------------------------------
    df_g3_CDP = CSV.read(joinpath(base_path, "data/GHG/GHG_CDP/g_CDP_S3.csv"), DataFrame)
    df_g3_CDP = df_g3_CDP[df_g3_CDP.g_S3_CDP_c .> 0, :]

    # ------------------------------------------------------------------
    # Step 9: LEFT join with CDP Scope 3
    # Unlike generate_country_data() which uses innerjoin (only reporters),
    # this uses leftjoin to keep ALL companies — the boxplot needs all three
    # groups (reporters, non-reporters in CDP, and non-reporters not in CDP).
    # (Original: fig_S3_reporter.ipynb Cell 6)
    # ------------------------------------------------------------------
    df_c = @linq leftjoin(
        df_g_c[:, [:FACTSET_ENTITY_ID, :ISO_COUNTRY, :YEAR,
                   :S123, :g_S1, :g_S3_est, :g_S23_EMRIO, :SALES]],
        df_g3_CDP[:, [:FACTSET_ENTITY_ID, :g_S3_CDP_c, :accounting_year]],
        on = [:FACTSET_ENTITY_ID => :FACTSET_ENTITY_ID]
    ) |> unique(:FACTSET_ENTITY_ID)

    # Final filter: S123 must be positive
    df_c = df_c[df_c.S123 .> 0, :]

    # Select output columns matching original df_c_2015_3.csv structure
    df_c = df_c[:, [:FACTSET_ENTITY_ID, :ISO_COUNTRY, :YEAR,
                    :S123, :g_S1, :g_S3_est, :g_S23_EMRIO, :SALES,
                    :accounting_year, :g_S3_CDP_c]]

    # ------------------------------------------------------------------
    # Step 10: Load CDP company data for reporter/non-reporter grouping
    # The Python boxplot script needs this to classify companies into:
    #   - Reporters: have g_S3_CDP_c
    #   - Non-reporters (in CDP): no g_S3_CDP_c but FACTSET_ENTITY_ID in g_CDP
    #   - Non-reporters (not in CDP): neither
    # ------------------------------------------------------------------
    g_CDP_c = CSV.read(joinpath(base_path, "data/GHG/GHG_CDP/g_CDP.csv"), DataFrame)
    g_CDP_c = g_CDP_c[g_CDP_c.accounting_year .=== yr, :]

    return (df_c, g_CDP_c)
end
