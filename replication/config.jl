# ============================================================================
# config.jl — Central configuration for the replication package.
#
# This is the ONLY file a reviewer needs to edit to adapt paths to their
# own data installation.  All pipeline steps read from these constants.
# ============================================================================
#
# NOTICE: This file defines IMPORT_PATH which points to external data under
# import. All pipeline steps depend on this path.
# Required import dependencies (accessed via IMPORT_PATH):
#   - <DATA_ROOT>/IO/EIO/EMRIO/2015/20240228.jld2
#   - <DATA_ROOT>/IO/EIO/DEIO/{COUNTRY}/2015/data_20240224.jld2
#     (71 countries: ALB, ARM, AUS, AUT, AZE, BEL, BEN, BGR, BLR, BOL, BRA,
#      CAN, CHE, CHL, CIV, CMR, COL, CRI, CYP, CZE, DEU, DNK, DOM, ECU, ESP,
#      EST, FIN, FRA, GBR, GEO, GHA, GRC, HKG, HND, HRV, HUN, IND, IRL, ISR,
#      ITA, JPN, KAZ, KOR, KWT, LBN, LKA, LTU, LUX, LVA, MAR, MDG, MEX, MKD,
#      MLT, NER, NLD, NOR, NZL, POL, PRT, ROU, RUS, SEN, SGP, SVK, SVN, SWE,
#      TUR, TWN, USA, ZAF)
#   - <DATA_ROOT>/FactSet/Financial/ff_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Shipping/sc_ship_sec_entity.txt
#   - <DATA_ROOT>/FactSet/Supplychain/ent_scr_sec_entity.txt
#   - <DATA_ROOT>/tmp/nt_arranged_base_segment_20231210.jld2
# Please ensure these files are available before running the replication pipeline.

# ---- Paths ----
# Base path to the supplychain project directory.
# Set via env var SCOPE3_BASE_PATH, e.g.:
#   export SCOPE3_BASE_PATH=/path/to/supplychain
const BASE_PATH = get(ENV, "SCOPE3_BASE_PATH", "./")

# Path to external data (EMRIO matrices, FactSet data, etc.).
# Set via env var SCOPE3_DATA_ROOT, e.g.:
#   export SCOPE3_DATA_ROOT=/path/to/data
const IMPORT_PATH = get(ENV, "SCOPE3_DATA_ROOT", "./data/")

# ---- Parameters ----
const YEAR = 2015
const GHG_TYPE = "GHG6"

# Fixed output file tag.  This is appended to output filenames so that
# results are reproducible and comparable across runs.  Do NOT use
# Dates.now() — a fixed tag ensures file names are deterministic.
const OUTPUT_TAG = "20240406"

# EMRIO version selection.
#   "auto" = automatically pick the JLD2 file with the highest version number
#   or specify a fixed version string, e.g. "7"
const EMRIO_VERSION = "auto"

# ---- Countries ----
# Set to `nothing` to use the full country list from the EMRIO database.
# Or provide a vector of ISO country codes to process only a subset,
# e.g. ["USA", "JPN", "GBR"] for faster testing.
const COUNTRY_LIST_OVERRIDE = nothing

# ---- Output control ----
# Whether to write intermediate JLD2 files (Step 3 aggregation results).
# Set to `false` to save disk space if you only need final outputs.
const WRITE_INTERMEDIATE = true

# ---- Derived paths (do not edit) ----
const DATA_PATH = joinpath(BASE_PATH, "data")
const REPLICATION_DIR = @__DIR__                          # this file's directory
const OUTPUT_PATH = joinpath(REPLICATION_DIR, "output")   # replication/output/
const ORIG_OUTPUT_PATH = joinpath(BASE_PATH, "output")    # original output (read-only, for verification)
const EMRIO_PATH = joinpath(IMPORT_PATH, "IO/EIO/EMRIO", string(YEAR))
