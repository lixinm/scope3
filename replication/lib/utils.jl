# ============================================================================
# utils.jl — General-purpose utility functions for the replication pipeline.
#
# Consolidated from:
#   module/functions/find_newest_file.jl   (file discovery)
#   module/functions/load_SIC_country.jl   (SIC concordance)
#   module/functions/functions_GHG.jl      (DataFrame helpers)
#   module/functions/rename_func.jl        (company name normalization)
#   module/functions/add_short_name.jl     (short name generation)
#
# All functions are self-contained: they accept explicit arguments and
# return values.  No function modifies global state.
# ============================================================================
#
# NOTICE: This file contains path construction helpers for import.
# Required import dependencies (accessed indirectly via callers):
#   path_c_y(import_path, country, yr) constructs paths to:
#   - <DATA_ROOT>/IO/EIO/DEIO/{COUNTRY}/{YEAR}/
#   find_tmp_p(folder_path) searches for files in:
#   - <DATA_ROOT>/tmp/
#   get_file_with_highest_number(path) searches for files in:
#   - <DATA_ROOT>/IO/EIO/EMRIO/{YEAR}/
# Please ensure these directories exist when running this replication script.

# ============================================================================
# Section 1: File Discovery
# ============================================================================

"""
    list_years(path)

List all subdirectories of `path` (typically year directories like "2015").
"""
function list_years(path::String)
    all_items = readdir(path)
    return filter(item -> isdir(joinpath(path, item)), all_items)
end

"""
    extract_number(filename)

Extract the integer from a JLD2 filename like "7.jld2" → 7.
Returns `nothing` if the filename is not purely numeric before ".jld2".
"""
function extract_number(filename::String)
    return tryparse(Int, replace(filename, ".jld2" => ""))
end

"""
    get_file_with_highest_number(path)

Find the JLD2 file with the highest numeric name in `path`.
E.g., if the directory contains "5.jld2", "7.jld2", "3.jld2", returns "7.jld2".
Used to find the latest version of the EMRIO database.
"""
function get_file_with_highest_number(path::String)
    all_files = readdir(path)
    valid_files = filter(f -> endswith(f, ".jld2"), all_files)
    numbered_files = filter(f -> !isnothing(extract_number(f)), valid_files)
    if isempty(numbered_files)
        return nothing
    end
    # Fixed: sort by parsed number, not string (original code had a latent
    # bug where "9.jld2" would sort above "10.jld2" in string order).
    sorted_files = sort(numbered_files, by=extract_number, rev=true)
    return sorted_files[1]
end

"""
    find_file_with_max_digits(folder_path)

Find the JLD2 file matching `data_N.jld2` with the highest N.
Used to find the latest version of country-level IO data.
"""
function find_file_with_max_digits(folder_path::String)
    files = readdir(folder_path)
    max_value = 0
    max_filename = ""
    for file in files
        match_result = match(r"data_(\d+)\.jld2", file)
        if match_result !== nothing
            digits = parse(Int, match_result.captures[1])
            if digits > max_value
                max_value = digits
                max_filename = file
            end
        end
    end
    return max_filename
end

"""
    find_tmp_p(folder_path)

Find the `nt_arranged_base_segment_N.jld2` file with the highest N.
Used to find the latest version of the arranged segment data.
"""
function find_tmp_p(folder_path::String)
    files = readdir(folder_path)
    max_value = 0
    max_filename = ""
    for file in files
        match_result = match(r"nt_arranged_base_segment_(\d+)\.jld2", file)
        if match_result !== nothing
            digits = parse(Int, match_result.captures[1])
            if digits > max_value
                max_value = digits
                max_filename = file
            end
        end
    end
    return max_filename
end

"""
    path_c_y(import_path, country, yr)

Construct the path to a country's domestic EIO data directory.
Returns: `{import_path}/IO/EIO/DEIO/{country}/{yr}`
"""
function path_c_y(import_path::String, country, yr)
    return joinpath(import_path, "IO/EIO/DEIO", string(country), string(yr))
end

# ============================================================================
# Section 2: SIC Concordance
# ============================================================================

"""
    j_SIC(matrix, row_labels, column_labels)

Convert a binary concordance matrix into a DataFrame of (SECTOR_CODE, SIC_CODE) pairs.
For each 1 in `matrix[i,j]`, creates a row with `(row_labels[i], column_labels[j])`.
"""
function j_SIC(matrix, row_labels, column_labels)
    result_df = DataFrame(SECTOR_CODE = String[], SIC_CODE = String[])
    for i in 1:size(matrix, 1)
        for j in 1:size(matrix, 2)
            if matrix[i, j] == 1
                push!(result_df, (row_labels[i], column_labels[j]))
            end
        end
    end
    return result_df
end

# ============================================================================
# Section 3: DataFrame Helpers
# ============================================================================

"""
    df_filter(df, col, value)

Filter rows of `df` where column `col` exactly equals `value` (using `===`).
"""
function df_filter(df, col, value)
    return df[df[!, col] .=== value, :]
end

"""
    find_not_repeated(df, c)

Return rows from `df` where the value in column `c` appears exactly once.
"""
function find_not_repeated(df::DataFrame, c)
    output = DataFrame()
    push!(output, first(df))
    delete!(output, 1)
    list_no_repeated = Dict()
    list_repeated = Dict()
    for row in eachrow(df)
        if row[c] in keys(list_repeated)
            continue
        elseif row[c] in keys(list_no_repeated)
            delete!(list_no_repeated, row[c])
            list_repeated[row[c]] = 1
            output = output[output[!, Symbol(c)] .!= row[c], :]
        else
            push!(output, row)
            list_no_repeated[row[c]] = 1
        end
    end
    return output
end

"""
    find_repeated(df, c)

Return rows from `df` where the value in column `c` appears more than once.
"""
function find_repeated(df::DataFrame, c)
    df_no_repeated = find_not_repeated(df, c)
    output = DataFrame()
    push!(output, first(df))
    delete!(output, 1)
    for row in eachrow(df)
        if row[c] in df_no_repeated[!, Symbol(c)]
            continue
        else
            push!(output, row)
        end
    end
    return output
end

# String-typed column versions (dispatch)
find_not_repeated(df::DataFrame, c::String) = find_not_repeated(df, Symbol(c))
find_repeated(df::DataFrame, c::String) = find_repeated(df, Symbol(c))

"""
    drop_row_in_list(df, lst, c)

Remove rows from `df` where column `c` value is in `lst`.
"""
function drop_row_in_list(df::DataFrame, lst, c)
    df_copy = deepcopy(df)
    for row in eachrow(df_copy)
        if row[c] in lst
            df_copy = df_copy[df_copy[!, Symbol(c)] .!= row[c], :]
        end
    end
    return sort!(df_copy, Symbol(c))
end

"""
    change_date_to_FISCAL_YEAR(df)

Add a `FISCAL_YEAR` column based on the `DATE` column.
Fiscal year = calendar year if date is Dec 31, otherwise year - 1.
"""
function change_date_to_FISCAL_YEAR(df)
    FISCAL_YEAR = Vector{Int}()
    for row in eachrow(df)
        t = row[:DATE]
        if Dates.month(t) * 100 + Dates.day(t) < 1231
            push!(FISCAL_YEAR, Dates.year(t) - 1)
        else
            push!(FISCAL_YEAR, Dates.year(t))
        end
    end
    df[!, :FISCAL_YEAR] = FISCAL_YEAR
    return df
end

# ============================================================================
# Section 4: Company Name Processing
# ============================================================================

"""
    replace_name_eu(df, column)

Clean EU company names: remove common suffixes (LP, COKG, GMBH, etc.)
and normalize spelling variants.
"""
function replace_name_eu(df, column)
    df_copy = deepcopy(df)
    replacelist = [
        r"LP$", r"COKG$", r"CO$", r"SPA$", r"GMBH$", r"CORP$",
        r"ASUKBRANCH$", "CRAIGAVON", r"GMBHANDCOKG$", r"ESTATESDEPARTMENT"
    ]
    for row in eachrow(df_copy)
        for i in replacelist
            row[Symbol(column)] = replace(row[Symbol(column)], i => "")
        end
        row[Symbol(column)] = replace(row[Symbol(column)], "SERVICES" => "SERVICE")
        row[Symbol(column)] = replace(row[Symbol(column)], "CENTRE" => "CENTER")
        row[Symbol(column)] = replace(row[Symbol(column)], "ENTERPISES" => "ENTERPRISES")
        row[Symbol(column)] = replace(row[Symbol(column)], "FOUNDATIONTRUST" => "TRUST")
        row[Symbol(column)] = replace(row[Symbol(column)], "WARME" => "WAERME")
    end
    return df_copy
end

"""
    replace_name_dc(df, column)

Clean French company names: remove SNC, ASSOCIES suffixes.
"""
function replace_name_dc(df, column)
    df_copy = deepcopy(df)
    list_fr = [r"ASSOCIES$", r"ANDASSOCIES$", r"SNC$"]
    for row in eachrow(df_copy)
        if row[Symbol(column)] !== missing
            for i in list_fr
                row[Symbol(column)] = replace(row[Symbol(column)], i => "")
            end
            row[Symbol(column)] = replace(row[Symbol(column)], "SERVICES" => "SERVICE")
            row[Symbol(column)] = replace(row[Symbol(column)], "FOUNDATIONTRUST" => "TRUST")
        end
    end
    return df_copy
end

"""
    rename_de(df, column)

Handle German umlauts (ä→äe, ü→üe, ö→öe, Ö→Öe) for matching.
Only suitable for companies in DEU and AUT.
"""
function rename_de(df, column)
    df_copy = deepcopy(df)
    replacelist = ["ä", "ü", "ö", "ü", "Ö"]
    for row in eachrow(df_copy)
        for i in replacelist
            row[Symbol(column)] = replace(row[Symbol(column)], i => string(i, "e"))
        end
    end
    return df_copy
end

# ============================================================================
# Section 5: Short Name Generation (used in Step 5-6 for output)
# ============================================================================

"""
    contains_all_letters(a, b)

Check if string `a` contains all characters from string `b`.
"""
function contains_all_letters(a::AbstractString, b::AbstractString)::Bool
    for char in b
        if !(char in a)
            return false
        end
    end
    return true
end

"""
    min_ordered_substring_ignore_case(a, b)

Find the shortest substring of `a` that contains all characters of `b`
in order (case-insensitive).  Returns `a` if either string contains
non-ASCII characters.
"""
function min_ordered_substring_ignore_case(a::AbstractString, b::AbstractString)
    if !all(isascii, a) || !all(isascii, b)
        return a
    end
    a_lower = lowercase(a)
    b_lower = lowercase(b)
    best_substring = ""
    for i in 1:length(a)
        j = 1
        k = i
        start_idx = i
        while k <= length(a) && j <= length(b)
            if a_lower[k] == b_lower[j]
                j += 1
            end
            k = nextind(a_lower, k)
        end
        if j > length(b)
            end_idx = prevind(a_lower, k)
            current_substring = a[start_idx:end_idx]
            if isempty(best_substring) || length(current_substring) < length(best_substring)
                best_substring = current_substring
            end
        end
    end
    return best_substring
end

# ============================================================================
# Section 6: Company Name Normalization (from rename_func.jl)
#
# Note: The original rename_func.jl (module/functions/rename_func.jl) defined
# replace_company_name(), a large regex-based normalizer for legal entity
# formats (LLC, Ltd, GmbH, KK, SA, etc.).  It was included here but never
# called by any pipeline step (1-5).  The include has been removed to
# eliminate the last code-level dependency on module/.
#
# If future steps require company-name normalization, copy the function
# body into this file rather than re-adding the cross-directory include.
# ============================================================================
