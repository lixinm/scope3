# Public EMRIO Checkpoint Notebooks

This directory contains reviewer-facing notebooks that read only audited
aggregate checkpoint tables from:

```text
replication/public_data/checkpoints/
```

The notebooks verify selected intermediate checkpoints from the actual EMRIO
calculation pipeline. They do not read licensed raw inputs, firm-level outputs,
`<DATA_ROOT>`, or reversible JLD2 intermediate files. The notebooks can be
run from a public checkout using only the files committed under
`public_data/checkpoints/`.

## Notebooks

- `verify_actual_emrio_checkpoints.ipynb`: broad aggregate checkpoint
  verification for sector emissions, Scope 1 allocation, Scope 2/3 summaries,
  reported--benchmark comparisons, uncertainty, and representativeness outputs.
- `trace_step4_leontief_scope23.ipynb`: computation trace for the actual Step 4
  Leontief inverse and Scope 2/3 decomposition. It shows the sequence from
  loading the Step 3 aggregate object through `I - A`, inverse residual checks,
  multiplier diagnostics, and the final Scope 2/3 equation checks.

## Run

From `replication/`:

```bash
python -m pip install -r requirements.txt
jupyter notebook notebooks/verify_actual_emrio_checkpoints.ipynb
jupyter notebook notebooks/trace_step4_leontief_scope23.ipynb
```

The notebooks are committed with outputs preserved so reviewers can inspect the
checkpoint tables even without rerunning them locally.

## Public-Release Self-Check

The final audit cells check that loaded checkpoint tables do not expose
restricted identifier columns, private/local paths, invalid required numeric
values, or accidentally published dense-matrix/vector columns. Passing these
cells does not replace the upstream disclosure audit, but it guards against
accidental leakage through the public notebook inputs.

## Maintenance Rules

Before committing notebook changes:

1. Clear stale outputs and metadata.
2. Rerun from a clean checkout using only `public_data/checkpoints/`.
3. Commit the rerun notebooks with outputs preserved.
4. Inspect notebook JSON for local paths, private paths, entity IDs, company
   names, ISINs, or other restricted identifiers.
