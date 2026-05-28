# ============================================================================
# experiment_emrio_reduce.jl — Reduce EMRIO rows/columns for robustness testing.
#
# INTERNAL EXPERIMENT ONLY. Does NOT modify any on-disk data or original logic.
# Creates an in-memory deep copy of nt_EMRIO with a subset of rows/columns
# removed, then rebuilds all linked runtime metadata consistently.
#
# Usage:
#   result = reduce_emrio(nt_EMRIO;
#       enabled   = true,
#       drop_idx  = 100:119,
#       dry_run   = false,
#   )
#   # result.nt_EMRIO_reduced is the modified object (or original if disabled)
#   # result.report contains a human-readable summary
# ============================================================================

using SparseArrays

"""
    reduce_emrio(nt_EMRIO; enabled=false, drop_idx=100:119, dry_run=false)

Create a structurally reduced in-memory copy of `nt_EMRIO` for robustness testing.

Drops the same indices from both row and column dimensions so the core EMRIO_T
matrix remains square. Rebuilds all linked runtime objects (att_q, att_qd,
EMRIO_xq, EMRIO_xqd, T_RoW_qd, T_q_RoWd) and reindexes ROW_NUM / COL_NUM.

Objects that have no dimension dependency on the dropped indices are left unchanged:
  T_RoW_RoWd, xRoW, xRoWd, att_r, att_rs, att_s

# Arguments
- `nt_EMRIO`  : Original EMRIO NamedTuple (NOT mutated)
- `enabled`   : If `false`, returns the original object unchanged (default: false)
- `drop_idx`  : Indices to drop (e.g. `100:119` or `[5, 10, 200]`)
- `dry_run`   : If `true`, compute and report dimensions but skip the actual reduction

# Returns a NamedTuple:
- `nt_EMRIO_reduced` : The reduced (or original) NamedTuple
- `report`           : Dict with before/after dimensions and rebuild status
"""
function reduce_emrio(nt_EMRIO;
                      enabled::Bool = false,
                      drop_idx = 100:119,
                      dry_run::Bool = false)

    drop_idx = collect(drop_idx)
    n_orig = size(nt_EMRIO.EMRIO_T, 1)

    report = Dict{String,Any}(
        "enabled"    => enabled,
        "dry_run"    => dry_run,
        "drop_idx"   => drop_idx,
        "n_dropped"  => length(drop_idx),
        "n_orig"     => n_orig,
    )

    if !enabled
        report["status"] = "SKIPPED (enabled=false)"
        println("[experiment_emrio_reduce] Experiment disabled — returning original nt_EMRIO.")
        return (nt_EMRIO_reduced = nt_EMRIO, report = report)
    end

    # Validate indices
    bad = [i for i in drop_idx if i < 1 || i > n_orig]
    if !isempty(bad)
        error("[experiment_emrio_reduce] drop_idx contains out-of-range indices: $bad (valid: 1:$n_orig)")
    end

    keep_idx = setdiff(1:n_orig, drop_idx)
    n_new = length(keep_idx)

    report["n_new"]     = n_new
    report["keep_size"] = n_new

    println("[experiment_emrio_reduce] Original EMRIO_T: $(n_orig) x $(n_orig)")
    println("[experiment_emrio_reduce] Dropping $(length(drop_idx)) indices: $(first(drop_idx)):$(last(sort(drop_idx)))")
    println("[experiment_emrio_reduce] New EMRIO_T will be: $(n_new) x $(n_new)")

    if dry_run
        report["status"] = "DRY_RUN (no reduction applied)"
        println("[experiment_emrio_reduce] Dry run — no changes applied.")
        return (nt_EMRIO_reduced = nt_EMRIO, report = report)
    end

    # ------------------------------------------------------------------
    # Apply structural reduction — subset directly, no deepcopy needed.
    # Indexing into arrays/DataFrames already creates new objects.
    # This avoids doubling peak memory usage.
    # ------------------------------------------------------------------
    n_orig_att_q  = nrow(nt_EMRIO.att_q)
    n_orig_att_qd = nrow(nt_EMRIO.att_qd)

    EMRIO_T_new   = nt_EMRIO.EMRIO_T[keep_idx, keep_idx]
    att_q_new     = nt_EMRIO.att_q[keep_idx, :]
    att_qd_new    = nt_EMRIO.att_qd[keep_idx, :]
    # EMRIO_xq is a column vector (n,) or (n×1); EMRIO_xqd is a row vector (1×n)
    # Handle both shapes correctly
    if ndims(nt_EMRIO.EMRIO_xq) == 1
        EMRIO_xq_new = nt_EMRIO.EMRIO_xq[keep_idx]
    else
        EMRIO_xq_new = nt_EMRIO.EMRIO_xq[keep_idx, :]
    end
    if ndims(nt_EMRIO.EMRIO_xqd) == 1
        EMRIO_xqd_new = nt_EMRIO.EMRIO_xqd[keep_idx]
    else
        EMRIO_xqd_new = nt_EMRIO.EMRIO_xqd[:, keep_idx]
    end
    T_RoW_qd_new  = nt_EMRIO.T_RoW_qd[:, keep_idx]
    T_q_RoWd_new  = nt_EMRIO.T_q_RoWd[keep_idx, :]

    # ------------------------------------------------------------------
    # Rebuild runtime index metadata
    # ------------------------------------------------------------------
    att_q_new[!, :ROW_NUM]  = 1:nrow(att_q_new)
    att_qd_new[!, :COL_NUM] = 1:nrow(att_qd_new)

    report["ROW_NUM_rebuilt"] = true
    report["COL_NUM_rebuilt"] = true
    report["att_q_rows_before"]  = n_orig_att_q
    report["att_q_rows_after"]   = nrow(att_q_new)
    report["att_qd_rows_before"] = n_orig_att_qd
    report["att_qd_rows_after"]  = nrow(att_qd_new)
    report["EMRIO_T_size_before"] = (n_orig, n_orig)
    report["EMRIO_T_size_after"]  = size(EMRIO_T_new)

    # ------------------------------------------------------------------
    # Reassemble NamedTuple with unchanged fields carried over
    # ------------------------------------------------------------------
    nt_reduced = (
        EMRIO_T     = EMRIO_T_new,
        att_q       = att_q_new,
        att_qd      = att_qd_new,
        EMRIO_xq    = EMRIO_xq_new,
        EMRIO_xqd   = EMRIO_xqd_new,
        T_RoW_qd    = T_RoW_qd_new,
        T_q_RoWd    = T_q_RoWd_new,
        T_RoW_RoWd  = nt_EMRIO.T_RoW_RoWd,
        xRoW        = nt_EMRIO.xRoW,
        xRoWd       = nt_EMRIO.xRoWd,
        att_r        = nt_EMRIO.att_r,
        att_rs       = :att_rs in keys(nt_EMRIO) ? nt_EMRIO.att_rs : missing,
        att_s        = :att_s  in keys(nt_EMRIO) ? nt_EMRIO.att_s  : missing,
    )

    report["status"] = "REDUCED"

    # ------------------------------------------------------------------
    # Print summary
    # ------------------------------------------------------------------
    println("[experiment_emrio_reduce] Reduction applied successfully.")
    println("  EMRIO_T:    ($(n_orig), $(n_orig)) → $(size(EMRIO_T_new))")
    println("  att_q:      $(n_orig_att_q) rows → $(nrow(att_q_new)) rows")
    println("  att_qd:     $(n_orig_att_qd) rows → $(nrow(att_qd_new)) rows")
    println("  EMRIO_xq:   $(n_orig) → $(length(EMRIO_xq_new))")
    println("  EMRIO_xqd:  $(n_orig) → $(length(EMRIO_xqd_new))")
    println("  T_RoW_qd:   cols $(n_orig) → $(size(T_RoW_qd_new, 2))")
    println("  T_q_RoWd:   rows $(n_orig) → $(size(T_q_RoWd_new, 1))")
    println("  ROW_NUM rebuilt: 1:$(nrow(att_q_new))")
    println("  COL_NUM rebuilt: 1:$(nrow(att_qd_new))")
    println("  Unchanged: T_RoW_RoWd, xRoW, xRoWd, att_r, att_rs, att_s")

    return (nt_EMRIO_reduced = nt_reduced, report = report)
end
