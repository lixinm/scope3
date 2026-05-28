# DATA_ROOT Dependencies Report for replication/

**Generated: 2026-04-16**

This document lists all files under `<DATA_ROOT>` that are required
by the replication pipeline under `replication/`.

Since `<DATA_ROOT>` is not included in the handover package, these
files must be provided separately for the replication scripts to run.

---

## 1. Summary of Scan

**Scanned directory**: `replication//`

**Files scanned**:
- 21 Julia source files (.jl): config.jl, run_all.jl, 13 lib/*.jl, 8 pipeline/*.jl
- 6 Python source files (.py): plots/*.py
- 1 Markdown file: README.md
- 3 Python bytecode files (.pyc): plots/__pycache__/*.pyc (skipped)
- 149+ CSV output files, 5 PDF figures, 1 JLD2 output (skipped — data, not code)

**Search methods used**:
1. Textual grep for `<DATA_ROOT>` paths
2. Julia dynamic path inspection: `joinpath`, `@__DIR__`, `dirname(@__FILE__)`, `abspath`, `normpath`
3. Python dynamic path inspection: `os.path`, `pathlib.Path`, `dirname`
4. Manual reading and tracing of all 27 source files
5. Verification of referenced paths against actual filesystem

---

## 2. Global Deduplicated List of Required DATA_ROOT Files

### 2.1 EMRIO Database (1 file)

```
<DATA_ROOT>/IO/EIO/EMRIO/2015/20240228.jld2
```

Selected at runtime by `get_file_with_highest_number()` (highest numeric filename).

### 2.2 DEIO Country IO Data (71 files)

Each file is at:
```
<DATA_ROOT>/IO/EIO/DEIO/{COUNTRY}/2015/data_20240224.jld2
```

Selected at runtime by `find_file_with_max_digits()` (matches `data_(\d+).jld2`).

Countries (71):
ALB, ARM, AUS, AUT, AZE, BEL, BEN, BGR, BLR, BOL, BRA, CAN, CHE, CHL, CIV,
CMR, COL, CRI, CYP, CZE, DEU, DNK, DOM, ECU, ESP, EST, FIN, FRA, GBR, GEO,
GHA, GRC, HKG, HND, HRV, HUN, IND, IRL, ISR, ITA, JPN, KAZ, KOR, KWT, LBN,
LKA, LTU, LUX, LVA, MAR, MDG, MEX, MKD, MLT, NER, NLD, NOR, NZL, POL, PRT,
ROU, RUS, SEN, SGP, SVK, SVN, SWE, TUR, TWN, USA, ZAF

### 2.3 FactSet Entity Concordance (3 files)

```
<DATA_ROOT>/FactSet/Financial/ff_sec_entity.txt
<DATA_ROOT>/FactSet/Shipping/sc_ship_sec_entity.txt
<DATA_ROOT>/FactSet/Supplychain/ent_scr_sec_entity.txt
```

### 2.4 Arranged Base Segment Data (1 file)

```
<DATA_ROOT>/tmp/nt_arranged_base_segment_20231210.jld2
```

Selected at runtime by `find_tmp_p()` (matches `nt_arranged_base_segment_(\d+).jld2`).

### Total: 76 files required from `<DATA_ROOT>`

---

## 3. Per-File Dependency Map

### 3.1 Files WITH DATA_ROOT dependencies

#### config.jl
**Role**: Defines `<DATA_ROOT>` and `EMRIO_PATH` constants used by all pipeline steps.
**Requires**: All 76 DATA_ROOT files (defines the root path for all external data access).

#### run_all.jl
**Role**: Master script that includes Steps 1-4.
**Requires**: All 76 DATA_ROOT files (via included pipeline steps).

#### lib/load_emissions_data.jl
**Role**: Defines `load_sec_entity()` and `load_segment_base()`.
**Requires**:
- `<DATA_ROOT>/FactSet/Financial/ff_sec_entity.txt`
- `<DATA_ROOT>/FactSet/Shipping/sc_ship_sec_entity.txt`
- `<DATA_ROOT>/FactSet/Supplychain/ent_scr_sec_entity.txt`
- `<DATA_ROOT>/tmp/nt_arranged_base_segment_20231210.jld2`

#### lib/load_emrio.jl
**Role**: Defines `load_emrio()` — loads the EMRIO database + calls `load_segment_base()`.
**Requires**:
- `<DATA_ROOT>/IO/EIO/EMRIO/2015/20240228.jld2`
- All 4 files listed under load_emissions_data.jl (via `load_segment_base()`)

#### lib/load_country_io.jl
**Role**: Defines `load_country_io()` — loads per-country IO data.
**Requires**:
- `<DATA_ROOT>/IO/EIO/DEIO/{COUNTRY}/2015/data_20240224.jld2` (71 countries)

#### lib/utils.jl
**Role**: Contains path construction helpers (`path_c_y`, `find_tmp_p`, `get_file_with_highest_number`).
**Requires**: No files directly, but constructs paths to:
- `.../IO/EIO/DEIO/{COUNTRY}/{YEAR}/`
- `.../tmp/`
- `.../IO/EIO/EMRIO/{YEAR}/`

#### lib/scope23_leontief.jl
**Role**: Defines `identify_energy_sectors()` and `compute_scope23()`.
**Requires**: All 71 DEIO country files (via `load_country_io()` called for each country).

#### pipeline/01_sector_emissions.jl
**Requires**: All 76 DATA_ROOT files (calls `load_emrio()` + `load_country_io()` for each country).

#### pipeline/02_scope1_subsegments.jl
**Requires**: All 76 DATA_ROOT files (calls `load_emrio()` + `load_country_io()` for each country).

#### pipeline/03_emrio_aggregate.jl
**Requires**: EMRIO + FactSet + tmp files (5 files; does NOT call `load_country_io()`).

#### pipeline/04_scope23.jl
**Requires**: All 76 DATA_ROOT files (calls `compute_scope23()` → `identify_energy_sectors()` → `load_country_io()` for each country; also may recompute Step 3 if intermediate file missing).

#### pipeline/05_figure_data.jl
**Requires**: EMRIO + FactSet + tmp files (5 files; calls `load_emrio()` but does NOT call `load_country_io()`).
**Note**: `import_path` is passed to `generate_triangle_data()` and `generate_country_data()` as a parameter, but it is not actually used within those functions (dead parameter).

#### pipeline/verify_step1.jl
**Requires**: All 76 DATA_ROOT files (calls `load_emrio()` + `load_country_io()` for each country).

#### pipeline/verify_step2.jl
**Requires**: All 76 DATA_ROOT files (calls `load_emrio()` + `load_country_io()` for each country).

### 3.2 Files WITHOUT DATA_ROOT dependencies

| File | Reason |
|------|--------|
| lib/arrange_sector.jl | Operates on in-memory data passed as arguments |
| lib/scope1_cdp.jl | Operates on in-memory data passed as arguments |
| lib/scope1_epa.jl | Uses `base_path` (supplychain/), not `import_path` |
| lib/scope1_generate.jl | Uses `base_path` and `output_path`, not `import_path` |
| lib/rest_of_world.jl | Operates on in-memory IEA data passed as arguments |
| lib/nos_aggregate.jl | Operates on in-memory EMRIO data passed as arguments |
| lib/figure_data.jl | Accepts `import_path` parameter but never uses it (dead parameter) |
| pipeline/verify_step4.jl | Only compares CSV files from `OUTPUT_PATH` and `ORIG_OUTPUT_PATH` |
| plots/fig_boxplot.py | Reads only from local output/figures/ CSV files |
| plots/fig_country.py | Reads only from local output/figures/ CSV files |
| plots/fig_country_ratio.py | Reads only from local output/figures/ CSV files |
| plots/fig_country_ratio_appendix.py | Reads only from local output/figures/ CSV files |
| plots/fig_triangle.py | Reads only from local output/figures/ CSV files |
| plots/table_country_ratio.py | Reads only from local output/figures/ CSV files |
| README.md | Documentation only |

---

## 4. Files Modified with NOTICE Tags

The following 14 files had NOTICE comments added near the top:

1. `config.jl` — after existing header comment block
2. `run_all.jl` — after existing header comment block
3. `lib/load_emissions_data.jl` — after existing header comment block
4. `lib/load_emrio.jl` — after existing header comment block
5. `lib/load_country_io.jl` — after existing header comment block
6. `lib/utils.jl` — after existing header comment block
7. `lib/scope23_leontief.jl` — after existing header comment block
8. `pipeline/01_sector_emissions.jl` — after existing header comment block
9. `pipeline/02_scope1_subsegments.jl` — after existing header comment block
10. `pipeline/03_emrio_aggregate.jl` — before first executable statement
11. `pipeline/04_scope23.jl` — before first executable statement
12. `pipeline/05_figure_data.jl` — before first executable statement
13. `pipeline/verify_step1.jl` — after existing header comment block
14. `pipeline/verify_step2.jl` — after existing header comment block

---

## 5. Files NOT Modified and Why

| File | Reason |
|------|--------|
| lib/arrange_sector.jl | No DATA_ROOT dependency |
| lib/scope1_cdp.jl | No DATA_ROOT dependency |
| lib/scope1_epa.jl | No DATA_ROOT dependency |
| lib/scope1_generate.jl | No DATA_ROOT dependency |
| lib/rest_of_world.jl | No DATA_ROOT dependency |
| lib/nos_aggregate.jl | No DATA_ROOT dependency |
| lib/figure_data.jl | `import_path` parameter exists but is dead (never used) |
| pipeline/verify_step4.jl | No DATA_ROOT dependency (only uses OUTPUT/ORIG_OUTPUT paths) |
| plots/*.py (6 files) | No DATA_ROOT dependency (read local CSV output only) |
| README.md | Documentation only |
| plots/__pycache__/*.pyc | Compiled bytecode, not source |
| output/**/*.csv, *.jld2, *.pdf | Data/output files, not source code |

---

## 6. Uncertain or Ambiguous Dependencies

### 6.1 Dynamic file selection

Three DATA_ROOT paths use runtime file discovery instead of hardcoded filenames:

- **EMRIO**: `get_file_with_highest_number()` selects the JLD2 file with the
  highest numeric name in `.../EMRIO/2015/`. Currently there is only one file
  (`20240228.jld2`), so the dependency is unambiguous. If additional files are
  added to that directory, the highest-numbered one will be selected.

- **DEIO**: `find_file_with_max_digits()` selects the JLD2 file matching
  `data_(\d+).jld2` with the highest number. Currently each country directory
  contains exactly one such file (`data_20240224.jld2`). The bare `20240224.jld2`
  files in the same directories are NOT loaded by the replication code.

- **tmp**: `find_tmp_p()` selects the JLD2 file matching
  `nt_arranged_base_segment_(\d+).jld2` with the highest number. Currently there
  is only one file (`nt_arranged_base_segment_20231210.jld2`).

### 6.2 Country list determination

The exact set of countries processed is determined at runtime by
`emrio.country_list`, which comes from `unique(nt_EMRIO.att_r.ISO_COUNTRY_r)`
inside the EMRIO JLD2 file. Without loading the EMRIO database, the exact country
list cannot be confirmed. However, the 71 DEIO country directories that have
`2015/` subdirectories represent the maximum possible set. The replication code
will fail for any country not in the DEIO directory.

### 6.3 Dead parameter in figure_data.jl

`lib/figure_data.jl` functions (`generate_triangle_data`, `generate_country_data`,
`generate_country_data_appendix`) accept an `import_path` parameter that is passed
through to `_prepare_q_est_with_cdp()`, but `_prepare_q_est_with_cdp()` never
uses this parameter. This is a dead parameter — no actual DATA_ROOT dependency exists.
No NOTICE was added to this file.

---

## 7. Verification Checklist

- [x] Searched for all textual references to `<DATA_ROOT>` paths
- [x] Inspected Python dynamic path construction (os.path, pathlib.Path, dirname) — no legacy import path references found
- [x] Inspected Julia dynamic path construction (joinpath, @__DIR__, dirname, abspath, normpath, relpath, pwd)
- [x] Checked all 21 Julia files and 6 Python files
- [x] Checked for shell scripts, notebooks, Makefiles, TOML, YAML, config files — none found
- [x] Verified all referenced paths exist under `<DATA_ROOT>`
- [x] Did not modify JSON or formats without comment support (none present)
- [x] Did not modify Manifest.toml (none present)
- [x] Did not change any script logic
- [x] Created this dependency report
