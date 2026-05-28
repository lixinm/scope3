# Mapping EXIOBASE 2015 (pxp) Sectors to SIC 1-digit Categories

**Purpose.** Our firm-level EMRIO dataset is classified by **SIC 1-digit**
categories, while the public MRIO database **EXIOBASE v3.9.6 pxp (2015)** uses
its own product list of 200 items keyed loosely to **NACE Rev.1.1 / ISIC
Rev.3.1**. To overlay EXIOBASE benchmark points onto the ternary figure of
firm-level Scope 1/2/3 shares (`fig_triangle.pdf`), we need a many-to-one
mapping from the 200 EXIOBASE products to the 10 SIC 1-digit categories used
in the ternary plot.

This document explains how that mapping was constructed, documents every
judgment call, and points to the machine-readable table.

---

## 1. Source classifications

- **SIC 1-digit** (10 categories, fixed by `fig_triangle.py`):
  1. Agriculture, Forestry and Fishing
  2. Mining
  3. Construction
  4. Manufacturing
  5. Transportation, Communications, Electric, Gas and Sanitary service
  6. Wholesale Trade
  7. Retail Trade
  8. Finance, Insurance and Real Estate
  9. Services
  10. Public Administration

- **EXIOBASE pxp (2015)**: 200 product-by-product rows repeated across 49
  regions (total 9,800 region-product cells). Each product's full label
  often contains a numeric code in parentheses — e.g.
  `"Wholesale trade and commission trade services … (51)"` — which is the
  **NACE Rev.1.1 division** the product corresponds to.

---

## 2. Mapping logic

The mapping is deterministic and rule-based, not a classifier. Every EXIOBASE
product was assigned to exactly one SIC 1-digit category using (in order):

### Rule A — NACE code in the EXIOBASE label

When an EXIOBASE product name ends with a code like `(51)` we use the
**NACE Rev.1.1 ↔ SIC 1-digit** correspondence:

| NACE Rev.1.1 divisions | SIC 1-digit category                      |
|------------------------|-------------------------------------------|
| 01–05                  | Agriculture, Forestry and Fishing         |
| 10–14                  | Mining                                    |
| 15–37                  | Manufacturing                             |
| 40–41                  | Transportation / Utilities / Sanitary     |
| 45                     | Construction                              |
| 50 (motor-vehicle trade) | Retail Trade (treated as auto retail)   |
| 51                     | Wholesale Trade                           |
| 52, 55                 | Retail Trade (incl. hotels & restaurants) |
| 60–64                  | Transportation, Communications            |
| 65–67                  | Finance, Insurance                        |
| 70                     | Finance, Insurance and Real Estate        |
| 71–74, 80, 85, 91–95   | Services                                  |
| 75                     | Public Administration                     |

### Rule B — Semantic classification when no NACE code is present

Many EXIOBASE products are raw commodities or intermediate outputs with no
bracketed code. These are classified by meaning:

| Heuristic                                   | Assigned category                  |
|---------------------------------------------|------------------------------------|
| Crop / livestock / fishing / forestry output | Agriculture, Forestry and Fishing |
| Ores, coal types, crude petroleum, natural gas, stone, sand | Mining |
| Refinery outputs (gasoline, kerosene, diesel, LPG, …) and fuel gases (coke oven gas, blast furnace gas, …) | Manufacturing (NACE 23) |
| All "Electricity by X" + electricity T&D + steam/hot water + gas distribution through mains | Transportation / Utilities / Sanitary |
| All "… waste for treatment: …" lines         | Transportation / Utilities / Sanitary |
| All "Secondary X for treatment, Re-processing into new X" lines | Manufacturing (recycling, NACE 37) |
| Primary metals, chemicals, plastics, cement, glass, ceramics | Manufacturing |

### Rule C — Named judgment calls

A handful of products could defensibly go in more than one category. The
choices made here (and the alternatives you could consider) are:

| EXIOBASE product                                         | Assigned        | Alternative               |
|----------------------------------------------------------|-----------------|---------------------------|
| Manure (biogas treatment) / Manure (conventional)        | Agriculture    | Utilities / Sanitary      |
| Ash for treatment → clinker                              | Utilities / Sanitary | Manufacturing (recycling) |
| Secondary raw materials                                  | Utilities / Sanitary | Manufacturing |
| "Secondary X → new X" re-processing (aluminium, steel, paper, plastic, glass, copper, lead, other non-ferrous, precious metals, wood, construction material) | Manufacturing | Utilities / Sanitary |
| Hotel and restaurant services (55)                       | Retail Trade   | Services                 |
| Sale / maintenance / repair of motor vehicles (50)       | Retail Trade   | Wholesale / Services     |
| Retail trade services of motor fuel                      | Retail Trade   | Wholesale                |
| Extra-territorial organizations and bodies               | Services       | Public Administration    |
| Private households with employed persons (95)            | Services       | —                        |

Each of these can be flipped by editing the `SIC_MAP` dictionary in
`replication/plots/fig_triangle_exiobase.py` and re-running the script
(~1–2 minutes).

---

## 3. Scope-2-relevant sub-list (separate flag)

For computing the EXIOBASE **Scope 2** share in the ternary figure, we also
need to know which EXIOBASE products represent **purchased energy carriers**
whose upstream emissions should be attributed to the buyer's Scope 2 rather
than Scope 3. We use the GHG Protocol convention (electricity + heat + steam).

The following 15 products are flagged `counted_in_Scope2_upstream = yes`
in the CSV (all fall under "Transportation / Utilities / Sanitary" in the
SIC mapping):

- Electricity by coal, gas, nuclear, hydro, wind, solar photovoltaic,
  solar thermal, petroleum, biomass and waste, tide/wave/ocean, Geothermal
- Electricity nec
- Transmission services of electricity
- Distribution and trade services of electricity
- Steam and hot water supply services

Gas distribution through mains is **not** included, because natural gas is
treated as Scope 1 (combusted on-site) in corporate accounting.

---

## 4. Known limitations

1. **pxp, not ixi.** EXIOBASE offers both product-by-product and
   industry-by-industry system tables. We used pxp because that was the
   archive available locally. For these SIC categories the differences are
   typically within a few percent, but strictly speaking the benchmark
   represents *product* technology, not *industry* accounting.
2. **NACE Rev.1.1 ≠ SIC 1987.** EXIOBASE follows the European NACE
   classification; the firm-level data uses US SIC. Their 1-digit / top-level
   structures align well but not perfectly (e.g. NACE keeps motor-vehicle
   retail and wholesale split across divisions that SIC collapses
   differently). The mapping in this document reflects the most common
   correspondence in published concordance tables.
3. **Heterogeneous aggregates.** "Chemicals nec" (one EXIOBASE product)
   collapses specialty chemicals, soaps, pharmaceuticals, cosmetics, paints
   and pesticides into a single product. When that single product is mapped
   into SIC Manufacturing, the resulting benchmark represents the
   weighted-average of this heterogeneous mix and **cannot be disaggregated
   into SIC 4-digit sub-industries from EXIOBASE alone**.
4. **Several border-line products**, documented in §2-C above, were placed by
   judgment. These choices are transparent in `SIC_MAP` and can be revised.

---

## 5. Reproducibility

- **Mapping definition (source of truth):**
  `replication/plots/fig_triangle_exiobase.py`, dictionary `SIC_MAP` and set
  `ELECTRICITY_LIKE`.
- **Machine-readable table:**
  `replication/output/figures/experiment/sic1_to_exiobase_mapping.csv`
  — one row per (SIC 1-digit × EXIOBASE product), 200 rows total, columns:
  - `SIC_1_digit_category`
  - `EXIOBASE_pxp_sector`
  - `NACE_code_in_name` (parsed from label when present)
  - `counted_in_Scope2_upstream` (`yes` / `no`)
- **Coverage check.** The script enforces that every one of the 200 EXIOBASE
  products appears in exactly one SIC category. At the time of writing, all
  200 are covered; if EXIOBASE's product list changes in a future release,
  re-running the script will print a warning naming any unmapped products.

---

## 6. Output of the mapping (counts per SIC 1-digit)

| SIC 1-digit category                                             | # EXIOBASE products |
|------------------------------------------------------------------|--------------------:|
| Agriculture, Forestry and Fishing                                | 19                  |
| Mining                                                           | 19                  |
| Construction                                                     | 1                   |
| Manufacturing                                                    | 94                  |
| Transportation, Communications, Electric, Gas and Sanitary service | 46                |
| Wholesale Trade                                                  | 1                   |
| Retail Trade                                                     | 4                   |
| Finance, Insurance and Real Estate                               | 4                   |
| Services                                                         | 11                  |
| Public Administration                                            | 1                   |
| **Total**                                                        | **200**             |

(Some single-row NACE divisions like Construction (NACE 45) or Public
Administration (NACE 75) legitimately map to just one EXIOBASE product
because EXIOBASE itself does not disaggregate them.)

---

## 7. Files

| File | Description |
|------|-------------|
| `replication/plots/fig_triangle_exiobase.py`                    | Script defining the mapping and producing the ternary figure |
| `replication/output/figures/experiment/sic1_to_exiobase_mapping.csv` | Flat 200-row mapping table |
| `replication/output/figures/experiment/sic1_to_exiobase_mapping.md`  | This document |
| `replication/output/figures/experiment/exiobase2015_sic1_s1s2s3_breakdown.csv` | Aggregated global S1/S2/S3 shares per SIC 1-digit category |
| `replication/output/figures/experiment/fig_triangle_exiobase.pdf`    | Ternary figure overlaying firm-level scatter with EXIOBASE benchmarks |
