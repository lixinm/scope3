# ============================================================================
# 06_generate_public_checkpoints.jl
#
# Generate public-safe aggregate checkpoint tables for reviewer-facing
# notebooks. This script reads verified pipeline outputs and writes aggregate,
# non-reversible CSVs under replication/public_data/checkpoints/.
#
# Public-release boundary:
#   - Do not write firm identifiers, segment identifiers, company names, ISINs,
#     CDP account fields, FactSet keys, or reversible matrix data.
#   - Apply small-cell suppression before writing country/SIC summaries.
#   - Write only aggregate, non-reversible checkpoint CSVs.
# ============================================================================

using CSV
using DataFrames
using Statistics

const REPLICATION_DIR = normpath(joinpath(@__DIR__, ".."))
const PROJECT_DIR = normpath(joinpath(REPLICATION_DIR, ".."))
const WORKSPACE_DIR = normpath(joinpath(PROJECT_DIR, ".."))
const OUTPUT_DIR = joinpath(REPLICATION_DIR, "output")
const FIGURE_DIR = joinpath(OUTPUT_DIR, "figures")
const EXPERIMENT_DIR = joinpath(FIGURE_DIR, "experiment")
const CHECKPOINT_DIR = joinpath(REPLICATION_DIR, "public_data", "checkpoints")
const UNCERTAINTY_DIR = joinpath(WORKSPACE_DIR, "ghg71_scope3_uncertainty_share_2015_20260518")
const GLORIA_SIC1_PATH = joinpath(WORKSPACE_DIR, "scope_paper_rev", "gloria", "out", "sic1_scope_table.csv")

const FORBIDDEN_COLUMN_PATTERNS = [
    r"FACTSET"i,
    r"ENTITY"i,
    r"PROPER"i,
    r"ACCOUNT"i,
    r"ISIN"i,
    r"NAME"i,
]

safe_div(num, den) = (ismissing(den) || den == 0 || ismissing(num) || !isfinite(num) || !isfinite(den)) ? missing : num / den
finite_sum(x) = sum(v for v in skipmissing(x) if isfinite(v))

function ensure_dir(path::AbstractString)
    isdir(path) || mkpath(path)
end

function read_csv(path::AbstractString)
    return CSV.read(path, DataFrame)
end

function write_checkpoint(filename::AbstractString, df::DataFrame; output_dir::AbstractString=CHECKPOINT_DIR)
    ensure_dir(output_dir)
    path = joinpath(output_dir, filename)
    audit_checkpoint_schema(df, filename)
    CSV.write(path, df)
    println("wrote ", path, " (", nrow(df), " rows)")
    return path
end

function audit_checkpoint_schema(df::DataFrame, label::AbstractString)
    bad = String[]
    for col in names(df)
        for pat in FORBIDDEN_COLUMN_PATTERNS
            if occursin(pat, col)
                push!(bad, col)
            end
        end
    end
    if !isempty(unique(bad))
        error("Unsafe public checkpoint $label contains restricted columns: $(join(unique(bad), ", "))")
    end
    return true
end

function suppress_small_groups!(df::DataFrame, group_col::Symbol, count_col::Symbol, threshold::Int)
    df[!, group_col] = string.(df[!, group_col])
    for i in 1:nrow(df)
        if !ismissing(df[i, count_col]) && df[i, count_col] <= threshold
            df[i, group_col] = "Other / suppressed small cells"
        end
    end
    return df
end

function suppress_small_groups_2d!(df::DataFrame, group_col1::Symbol, group_col2::Symbol, count_col::Symbol, threshold::Int)
    df[!, group_col1] = string.(df[!, group_col1])
    df[!, group_col2] = string.(df[!, group_col2])
    for i in 1:nrow(df)
        if !ismissing(df[i, count_col]) && df[i, count_col] <= threshold
            df[i, group_col1] = "Other / suppressed small cells"
            df[i, group_col2] = "Other / suppressed small cells"
        end
    end
    return df
end

function mask_small_binary_subgroups!(df::DataFrame, total_col::Symbol, subgroup_col::Symbol, share_col::Symbol, threshold::Int)
    df[!, subgroup_col] = Union{Missing, Int}[ismissing(x) ? missing : Int(x) for x in df[!, subgroup_col]]
    df[!, share_col] = Union{Missing, Float64}[ismissing(x) ? missing : Float64(x) for x in df[!, share_col]]
    for i in 1:nrow(df)
        if ismissing(df[i, total_col]) || ismissing(df[i, subgroup_col])
            continue
        end
        total = Int(df[i, total_col])
        subgroup = Int(df[i, subgroup_col])
        complement = total - subgroup
        small_nonzero_subgroup = (subgroup > 0 && subgroup <= threshold) || (complement > 0 && complement <= threshold)
        if small_nonzero_subgroup
            df[i, subgroup_col] = missing
            df[i, share_col] = missing
        end
    end
    return df
end

function read_all_country_csvs(dir::AbstractString)
    files = sort(filter(f -> endswith(f, ".csv"), readdir(dir; join=true)))
    frames = DataFrame[]
    for f in files
        push!(frames, read_csv(f))
    end
    return vcat(frames...; cols=:union)
end

function checkpoint_sector_emissions(; output_dir::AbstractString=CHECKPOINT_DIR, threshold::Int=3)
    df = read_all_country_csvs(joinpath(OUTPUT_DIR, "i_x_g", "2015"))
    df[!, :sector_prefix] = [length(string(x)) >= 2 ? string(x)[1:2] : "NA" for x in df.SECTOR_CODE]
    g = combine(groupby(df, [:ISO_COUNTRY, :sector_prefix]),
        :SECTOR_CODE => length => :n_source_sectors,
        :x => (x -> finite_sum(x)) => :sector_output_total,
        :CO2 => (x -> finite_sum(x)) => :co2_total,
        :non_CO2 => (x -> finite_sum(x)) => :non_co2_total,
        :GHG6 => (x -> finite_sum(x)) => :ghg6_total,
    )
    suppress_small_groups!(g, :sector_prefix, :n_source_sectors, threshold)
    g = combine(groupby(g, [:ISO_COUNTRY, :sector_prefix]),
        :n_source_sectors => sum => :n_source_sectors,
        :sector_output_total => (x -> finite_sum(x)) => :sector_output_total,
        :co2_total => (x -> finite_sum(x)) => :co2_total,
        :non_co2_total => (x -> finite_sum(x)) => :non_co2_total,
        :ghg6_total => (x -> finite_sum(x)) => :ghg6_total,
    )
    rename!(g, :ISO_COUNTRY => :country)
    return write_checkpoint("01_sector_emissions_by_country_sic.csv", g; output_dir=output_dir)
end

function checkpoint_scope1_allocation(; output_dir::AbstractString=CHECKPOINT_DIR, threshold::Int=3)
    df = read_csv(joinpath(FIGURE_DIR, "df_p_SIC_S123.csv"))
    df[!, :scope1_intensity] = [safe_div(row.g_S1, row.SALES) for row in eachrow(df)]
    g = combine(groupby(df, [:ISO_COUNTRY, :SIC_1_desc]),
        :g_S1 => length => :n_segments,
        :g_S1 => sum => :scope1_total,
        :SALES => sum => :sales_total,
        :scope1_intensity => (x -> median(skipmissing(x))) => :scope1_intensity_median,
        :scope1_intensity => (x -> mean(skipmissing(x))) => :scope1_intensity_mean,
    )
    suppress_small_groups_2d!(g, :ISO_COUNTRY, :SIC_1_desc, :n_segments, threshold)
    g = combine(groupby(g, [:ISO_COUNTRY, :SIC_1_desc]),
        :n_segments => sum => :n_segments,
        :scope1_total => sum => :scope1_total,
        :sales_total => sum => :sales_total,
        :scope1_intensity_median => mean => :scope1_intensity_median_group_mean,
        :scope1_intensity_mean => mean => :scope1_intensity_mean_group_mean,
    )
    rename!(g, :ISO_COUNTRY => :country, :SIC_1_desc => :sic_division)
    return write_checkpoint("02_scope1_allocation_summary_by_country_sic.csv", g; output_dir=output_dir)
end

function checkpoint_emrio_diagnostics(; output_dir::AbstractString=CHECKPOINT_DIR)
    q = read_csv(joinpath(OUTPUT_DIR, "2015", "q_est_20240406.csv"))
    p = read_csv(joinpath(FIGURE_DIR, "df_p_SIC_S123.csv"))
    n_other = count(startswith("Others-"), String.(q.FACTSET_ENTITY_ID))
    n_named = nrow(q) - n_other
    total_s1 = finite_sum(q.g_S1)
    total_s2 = finite_sum(q.g_S2_EMRIO)
    total_s23 = finite_sum(q.g_S23_EMRIO)
    total_s3 = finite_sum(q.g_S3_T)
    df = DataFrame(
        diagnostic = [
            "q_est_rows",
            "q_est_countries",
            "q_est_sector_codes",
            "named_rows",
            "other_source_rows",
            "figure_segment_rows",
            "figure_countries",
            "scope1_total",
            "scope2_total",
            "scope23_total",
            "scope3_total",
            "scope23_minus_scope2_minus_scope3_abs",
        ],
        value = [
            nrow(q),
            length(unique(q.ISO_COUNTRY)),
            length(unique(q.SECTOR_CODE)),
            n_named,
            n_other,
            nrow(p),
            length(unique(p.ISO_COUNTRY)),
            total_s1,
            total_s2,
            total_s23,
            total_s3,
            abs(total_s23 - total_s2 - total_s3),
        ],
        note = [
            "Rows in private q_est output; no row-level data released here.",
            "Unique countries represented in q_est.",
            "Unique sector codes represented in q_est.",
            "Rows not classified as residual Other Source accounts.",
            "Residual Other Source rows identified by Others- prefix.",
            "Rows in private figure segment source; only count is released.",
            "Unique countries in private figure segment source.",
            "Aggregate Scope 1 total from q_est.",
            "Aggregate Scope 2 total from q_est.",
            "Aggregate Scope 2+3 total from q_est.",
            "Aggregate Scope 3 residual from q_est.",
            "Numerical consistency check for Scope 3 = Scope 2+3 - Scope 2.",
        ],
    )
    return write_checkpoint("03_emrio_aggregation_diagnostics.csv", df; output_dir=output_dir)
end

function checkpoint_scope23(; output_dir::AbstractString=CHECKPOINT_DIR, threshold::Int=3)
    df = read_csv(joinpath(FIGURE_DIR, "df_p_SIC_S123.csv"))
    g = combine(groupby(df, [:ISO_COUNTRY, :SIC_1_desc]),
        :g_S1 => length => :n_segments,
        :g_S1 => sum => :scope1_total,
        :g_S2 => sum => :scope2_total,
        :g_S3 => sum => :scope3_total,
    )
    suppress_small_groups_2d!(g, :ISO_COUNTRY, :SIC_1_desc, :n_segments, threshold)
    g = combine(groupby(g, [:ISO_COUNTRY, :SIC_1_desc]),
        :n_segments => sum => :n_segments,
        :scope1_total => sum => :scope1_total,
        :scope2_total => sum => :scope2_total,
        :scope3_total => sum => :scope3_total,
    )
    g[!, :scope23_total] = g.scope2_total .+ g.scope3_total
    g[!, :scope123_total] = g.scope1_total .+ g.scope23_total
    g[!, :share_scope1] = [safe_div(r.scope1_total, r.scope123_total) for r in eachrow(g)]
    g[!, :share_scope2] = [safe_div(r.scope2_total, r.scope123_total) for r in eachrow(g)]
    g[!, :share_scope3] = [safe_div(r.scope3_total, r.scope123_total) for r in eachrow(g)]
    rename!(g, :ISO_COUNTRY => :country, :SIC_1_desc => :sic_division)
    return write_checkpoint("04_scope23_by_country_sic.csv", g; output_dir=output_dir)
end

function checkpoint_reported_benchmark_country(; output_dir::AbstractString=CHECKPOINT_DIR, threshold::Int=3)
    df = read_csv(joinpath(FIGURE_DIR, "df_fig1_20240406.csv"))
    df[!, :benchmark_exceeds_report] = df.g_S3_est .> df.g_S3_CDP_c
    g = combine(groupby(df, :ISO_COUNTRY),
        :g_S3_est => length => :n_reporting_companies,
        :g_S3_est => sum => :benchmark_scope3_total,
        :g_S3_CDP_c => sum => :reported_scope3_total,
        :benchmark_exceeds_report => sum => :n_benchmark_exceeds_report,
    )
    suppress_small_groups!(g, :ISO_COUNTRY, :n_reporting_companies, threshold)
    g = combine(groupby(g, :ISO_COUNTRY),
        :n_reporting_companies => sum => :n_reporting_companies,
        :benchmark_scope3_total => sum => :benchmark_scope3_total,
        :reported_scope3_total => sum => :reported_scope3_total,
        :n_benchmark_exceeds_report => sum => :n_benchmark_exceeds_report,
    )
    g[!, :benchmark_to_reported_ratio] = [safe_div(r.benchmark_scope3_total, r.reported_scope3_total) for r in eachrow(g)]
    g[!, :share_benchmark_exceeds_report] = [safe_div(r.n_benchmark_exceeds_report, r.n_reporting_companies) for r in eachrow(g)]
    mask_small_binary_subgroups!(g, :n_reporting_companies, :n_benchmark_exceeds_report, :share_benchmark_exceeds_report, threshold)
    rename!(g, :ISO_COUNTRY => :country)
    return write_checkpoint("05_reported_benchmark_by_country.csv", g; output_dir=output_dir)
end

function primary_sic_by_company(p::DataFrame)
    sorted = sort(p, [:FACTSET_ENTITY_ID, :SALES], rev=[false, true])
    first_rows = combine(groupby(sorted, :FACTSET_ENTITY_ID), first)
    return first_rows[:, [:FACTSET_ENTITY_ID, :SIC_1_desc]]
end

function checkpoint_reported_benchmark_sic(; output_dir::AbstractString=CHECKPOINT_DIR, threshold::Int=3)
    fig = read_csv(joinpath(FIGURE_DIR, "df_fig1_20240406.csv"))
    p = read_csv(joinpath(FIGURE_DIR, "df_p_SIC_S123.csv"))
    sic = primary_sic_by_company(p)
    df = leftjoin(fig, sic, on=:FACTSET_ENTITY_ID)
    df[!, :SIC_1_desc] = coalesce.(df.SIC_1_desc, "Unknown")
    df[!, :benchmark_exceeds_report] = df.g_S3_est .> df.g_S3_CDP_c
    g = combine(groupby(df, :SIC_1_desc),
        :g_S3_est => length => :n_reporting_companies,
        :g_S3_est => sum => :benchmark_scope3_total,
        :g_S3_CDP_c => sum => :reported_scope3_total,
        :benchmark_exceeds_report => sum => :n_benchmark_exceeds_report,
    )
    g = g[g.n_reporting_companies .> threshold, :]
    g[!, :benchmark_to_reported_ratio] = [safe_div(r.benchmark_scope3_total, r.reported_scope3_total) for r in eachrow(g)]
    g[!, :share_benchmark_exceeds_report] = [safe_div(r.n_benchmark_exceeds_report, r.n_reporting_companies) for r in eachrow(g)]
    mask_small_binary_subgroups!(g, :n_reporting_companies, :n_benchmark_exceeds_report, :share_benchmark_exceeds_report, threshold)
    rename!(g, :SIC_1_desc => :sic_division)
    return write_checkpoint("06_reported_benchmark_by_sic.csv", g; output_dir=output_dir)
end

function checkpoint_estimator_defs(; output_dir::AbstractString=CHECKPOINT_DIR)
    df = read_csv(joinpath(FIGURE_DIR, "df_fig1_20240406.csv"))
    ratio = df.g_S3_est ./ df.g_S3_CDP_c
    total_benchmark = finite_sum(df.g_S3_est)
    total_reported = finite_sum(df.g_S3_CDP_c)
    rows = [
        ("n_reporting_companies", nrow(df), "Number of company-level observations used in Figure 1 denominator comparison."),
        ("aggregate_benchmark_scope3", total_benchmark, "Aggregate EMRIO-based Scope 3 benchmark for the comparison set."),
        ("aggregate_reported_scope3", total_reported, "Aggregate company-reported Scope 3 for the comparison set."),
        ("ratio_of_aggregate_totals", safe_div(total_benchmark, total_reported), "Headline estimator used in the manuscript."),
        ("mean_firm_level_ratio", mean(skipmissing(ratio)), "Mean of firm-level benchmark/reported ratios."),
        ("median_firm_level_ratio", median(skipmissing(ratio)), "Median of firm-level benchmark/reported ratios."),
        ("share_benchmark_exceeds_report", mean(skipmissing(df.g_S3_est .> df.g_S3_CDP_c)), "Share of companies for which benchmark exceeds report."),
    ]
    out = DataFrame(metric = [r[1] for r in rows], value = [r[2] for r in rows], note = [r[3] for r in rows])
    return write_checkpoint("07_estimator_definitions_summary.csv", out; output_dir=output_dir)
end

function checkpoint_open_mrio(; output_dir::AbstractString=CHECKPOINT_DIR)
    p = read_csv(joinpath(FIGURE_DIR, "df_p_SIC_S123.csv"))
    emrio = combine(groupby(p, :SIC_1_desc),
        :g_S1 => length => :n_sectors,
        :g_S1 => sum => :s1,
        :g_S2 => sum => :s2,
        :g_S3 => sum => :s3,
    )
    emrio[!, :database] .= "EMRIO"
    emrio[!, :share_S1] = [safe_div(r.s1, r.s1 + r.s2 + r.s3) for r in eachrow(emrio)]
    emrio[!, :share_S2] = [safe_div(r.s2, r.s1 + r.s2 + r.s3) for r in eachrow(emrio)]
    emrio[!, :share_S3] = [safe_div(r.s3, r.s1 + r.s2 + r.s3) for r in eachrow(emrio)]
    emrio = emrio[:, [:database, :SIC_1_desc, :n_sectors, :share_S1, :share_S2, :share_S3]]
    rename!(emrio, :SIC_1_desc => :sic_division)

    exio_path = joinpath(EXPERIMENT_DIR, "exiobase2015_sic1_s1s2s3_breakdown.csv")
    exio = read_csv(exio_path)
    exio[!, :database] .= "EXIOBASE v3.9.6"
    rename!(exio, :SIC_1_desc => :sic_division)
    exio = exio[:, [:database, :sic_division, :n_sectors, :share_S1, :share_S2, :share_S3]]

    gloria = read_csv(GLORIA_SIC1_PATH)
    gloria[!, :database] .= "GLORIA v060"
    rename!(gloria, :sic1 => :sic_division, :n_sectors => :n_sectors)
    gloria = gloria[:, [:database, :sic_division, :n_sectors, :share_S1, :share_S2, :share_S3]]

    out = vcat(emrio, exio, gloria; cols=:union)
    return write_checkpoint("08_open_mrio_sic_comparison.csv", out; output_dir=output_dir)
end

function checkpoint_uncertainty(; output_dir::AbstractString=CHECKPOINT_DIR)
    totals_path = joinpath(UNCERTAINTY_DIR, "uncertainty_totals_2015_20260518.csv")
    df = read_csv(totals_path)
    out = df[:, [:level, :year, :metric, :point_estimate_original, :ui95_low, :ui95_mid, :ui95_high, :ui90_low, :ui90_high, :relative_width_95, :n_iter, :interval_type, :uncertainty_source]]
    return write_checkpoint("09_uncertainty_summary.csv", out; output_dir=output_dir)
end

function checkpoint_representativeness(; output_dir::AbstractString=CHECKPOINT_DIR)
    q = read_csv(joinpath(OUTPUT_DIR, "2015", "q_est_20240406.csv"))
    c = read_csv(joinpath(FIGURE_DIR, "df_c_20240406.csv"))
    fig = read_csv(joinpath(FIGURE_DIR, "df_fig1_20240406.csv"))
    total_scope123 = finite_sum(q.g_S1) + finite_sum(q.g_S23_EMRIO)
    matched_scope123 = finite_sum(c.S123)
    reported_scope3_benchmark = finite_sum(fig.g_S3_est)
    total_scope3 = finite_sum(q.g_S3_T)
    out = DataFrame(
        sample = ["matched_company_rows_available", "reported_denominator_comparison"],
        n_rows = [nrow(c), nrow(fig)],
        numerator_metric = ["scope1_plus_scope2plus3", "scope3_benchmark"],
        numerator_value = [matched_scope123, reported_scope3_benchmark],
        denominator_metric = ["full_emrio_scope1_plus_scope2plus3", "full_emrio_scope3"],
        denominator_value = [total_scope123, total_scope3],
        coverage_share = [safe_div(matched_scope123, total_scope123), safe_div(reported_scope3_benchmark, total_scope3)],
        note = [
            "Computed from public checkpoint generation inputs; row count reflects available df_c output, not a released firm table.",
            "Computed from reported-denominator comparison benchmark total relative to full EMRIO Scope 3 total.",
        ],
    )
    return write_checkpoint("10_representativeness_summary.csv", out; output_dir=output_dir)
end

function generate_public_checkpoints(; output_dir::AbstractString=CHECKPOINT_DIR, small_cell_threshold::Int=3)
    ensure_dir(output_dir)
    checkpoint_sector_emissions(; output_dir=output_dir, threshold=small_cell_threshold)
    checkpoint_scope1_allocation(; output_dir=output_dir, threshold=small_cell_threshold)
    checkpoint_emrio_diagnostics(; output_dir=output_dir)
    checkpoint_scope23(; output_dir=output_dir, threshold=small_cell_threshold)
    checkpoint_reported_benchmark_country(; output_dir=output_dir, threshold=small_cell_threshold)
    checkpoint_reported_benchmark_sic(; output_dir=output_dir, threshold=small_cell_threshold)
    checkpoint_estimator_defs(; output_dir=output_dir)
    checkpoint_open_mrio(; output_dir=output_dir)
    checkpoint_uncertainty(; output_dir=output_dir)
    checkpoint_representativeness(; output_dir=output_dir)
    println("All public checkpoint CSVs generated in ", output_dir)
end

if abspath(PROGRAM_FILE) == @__FILE__
    generate_public_checkpoints()
end
