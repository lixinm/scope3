# Does company size confound the reporter-vs-non-reporter intensity gap?

**Date:** 2026-04-19
**Data:** `replication/output/figures/df_c_20240406.csv` (2015, N = 2,012 companies)2
**Reference list:** `replication/output/figures/g_CDP_2015.csv`
**Intensity metric:** `ratio = S123 / SALES / 100` (ton CO₂e per 10k USD, EMRIO-based Scope 1–3)

---

## 1. Motivation

The original boxplot (`fig_boxplot.pdf`) compares EMRIO-based Scope 1–3 emission
intensities across three groups of companies:

1. **Reporters** — firms with a reported Scope 3 value in CDP (`g_S3_CDP_c` non-null)
2. **In CDP, no S3** — firms present in the CDP database but without a Scope 3 submission
3. **Not in CDP** — firms absent from CDP entirely

Reviewer concern: the observed intensity gap between these groups might be
**driven by company size (SALES) rather than reporting status itself**. Larger
firms could both (a) be more likely to report and (b) have lower intensity,
producing a spurious association. This report tests that hypothesis.

---

## 2. Group sizes are indeed very different

Before stratifying, a simple diagnostic confirms the groups differ substantially
in size:

| Group          | n   | Median SALES | Mean SALES | IQR (p25–p75)     |
|----------------|-----|-------------:|-----------:|------------------:|
| Reporters      | 893 |   **3,518**  |   10,248   |   1,350 – 10,173  |
| In CDP, no S3  | 171 |     1,633    |    3,541   |     619 –  4,183  |
| Not in CDP     | 948 |     **368**  |    1,424   |     173 –    998  |

Reporters are roughly **10× larger** (by median SALES) than Not-in-CDP firms.
This is exactly the confounding pattern the reviewer was worried about, so the
concern is well-founded *a priori* and deserves a stratified test.

Diagnostic figures:
- `fig_boxplot_sales.pdf` — SALES boxplot by group (log-scaled y axis)
- `fig_boxplot_scatter.pdf` — log10(SALES) vs intensity, colored by group

---

## 3. Stratified comparison: split the sample into SALES quartiles

To control for size, companies were split into **four SALES quartiles on the
full sample**, and the three reporting groups were compared *within* each
bucket. Quartile edges (SALES units as stored in `df_c`):

```
Q1 (smallest) : [0.1,      316.6]
Q2            : (316.6,  1,198.2]
Q3            : (1,198.2, 4,136.6]
Q4 (largest)  : (4,136.6, 270,756.2]
```

### 3.1 Median intensity within each size quartile

| Size bucket   | Reporters | In CDP, no S3 | Not in CDP | Reporters vs Not-in-CDP |
|---------------|----------:|--------------:|-----------:|------------------------:|
| Q1 (smallest) |  **2.79** |          3.87 |   **6.52** | ≈ 2.3× lower            |
| Q2            |  **3.27** |          5.48 |   **5.85** | ≈ 1.8× lower            |
| Q3            |  **3.29** |          3.97 |   **5.32** | ≈ 1.6× lower            |
| Q4 (largest)  |  **3.39** |          3.48 |   **6.39** | ≈ 1.9× lower            |
| **All**       |      3.31 |          4.04 |       5.99 | ≈ 1.8×                  |

**The gap between Reporters and Not-in-CDP persists inside every single size
quartile**, and its magnitude is similar to the unstratified gap. There is no
quartile in which the difference disappears or reverses.

(The "In CDP, no S3" group sits between the other two in most buckets; sample
sizes inside Q1 and Q4 are small — 23 and 44 — so it should be interpreted with
caution.)

Figure: `fig_boxplot_size_stratified.pdf` (4 facets, one per SALES quartile).

### 3.2 Regression check

Two OLS models on `log(ratio)`, with **Not in CDP as the baseline group**:

| Model                                    | Reporters coef. | In-CDP-no-S3 coef. |
|------------------------------------------|----------------:|-------------------:|
| (1) `log_ratio ~ Group`                  |    **−0.648**   |        −0.445      |
| (2) `log_ratio ~ Group + log(SALES)`     |    **−0.601**   |        −0.416      |

Interpretation:

- **Model 1** says Reporters have on average ~48% lower intensity than
  Not-in-CDP firms (`exp(−0.648) ≈ 0.52`), without any size control.
- **Model 2** adds `log(SALES)` as a control. The Reporters coefficient moves
  only from −0.648 to −0.601 — i.e. the reporter-status effect shrinks by
  roughly **7%** when size is controlled for.

Full regression tables: `regression_size_group.txt`.

---

## 4. Conclusion

**Company size does not explain away the intensity gap between reporters and
non-reporters.** Although the three groups differ substantially in SALES
(reporters are about 10× larger by median), the intensity gap survives size
stratification almost intact:

- Within every SALES quartile, reporters still have ≈1.6–2.3× lower median
  intensity than firms absent from CDP.
- A log-linear regression controlling for `log(SALES)` shrinks the reporter-vs-
  non-reporter coefficient by only ~7% (from −0.648 to −0.601).

The reviewer's confounding concern was well-posed — the groups *are* very
differently sized — but the data show the confounding effect is small. The
original finding is **robust to size control**: reporting status, not company
size, is the dominant driver of the intensity gap visible in `fig_boxplot.pdf`.

### Caveats
- Sample sizes for "In CDP, no S3" are small inside Q1 (n=23) and Q4 (n=44);
  statements about that middle group in those buckets are noisy.
- Size was controlled with SALES only. Industry mix (SIC) is a plausible
  additional confounder and has not been tested here; if the reviewer remains
  skeptical, the natural next step is a regression adding industry fixed
  effects (e.g. `+ C(SIC_2digit)`) or within-industry stratification.
- All numbers refer to 2015 (the `g_CDP_2015` snapshot). The stability of the
  finding across years has not been checked.

---

## 5. Files produced

All in `replication/output/figures/experiment/`:

| File                                   | Contents                                          |
|----------------------------------------|---------------------------------------------------|
| `fig_boxplot_sales.pdf`                | SALES boxplot by group (diagnostic)               |
| `fig_boxplot_scatter.pdf`              | log10(SALES) vs intensity scatter by group        |
| `fig_boxplot_size_stratified.pdf`      | 4-facet stratified boxplot (main result)          |
| `table_size_stratified.csv`            | n / median / mean per (quartile × group)          |
| `regression_size_group.txt`            | Full OLS output for both models                   |

Scripts (no existing code or outputs were modified):

- `replication/plots/fig_boxplot_size_check.py`
- `replication/plots/fig_boxplot_size_stratified.py`
