# penetration-census-analysis

Systematic exploration of which household and census-block demographics correlate with subscriber penetration, using Snowflake SQL.

## Overview

This is an **analytical workbench** — a collection of ~30 SQL queries that slice customer penetration rate across demographic dimensions individually and in pairwise combinations. The goal is to identify which household characteristics are the strongest predictors of subscription, informing targeting strategy, market planning, and predictive modeling.

All queries run against a single census-enriched household-level fact table, comparing two year-over-year daily snapshots.

## Analysis Structure

### Section 1: Census Block Group Summary

Aggregates households by census block group with home value distribution, dwelling mix, customer counts, and bulk status. Produces a dataset suitable for direct correlation analysis or geographic visualization.

### Section 2: Single-Dimension Penetration Cuts (9 queries)

Each query isolates one demographic variable and computes penetration rate by bucket:

| Query | Dimension | Buckets |
|-------|-----------|---------|
| 2a | Dwelling Segment | Apartment, House |
| 2b | Bulk Status | Bulk flag on household |
| 2c | Block-Level Bulk Presence | Any bulk in census block vs none |
| 2d | Children per Household | no_kids, low, med, high |
| 2e | Family Composition | family_dominant, non_family, even_split |
| 2f | Ownership Level | low → high (quartiles of % owner-occupied) |
| 2g | Kids Group (block-level) | More Kids vs Less Kids majority |
| 2h | Labor Force | Labor Majority vs Minority |
| 2i | Transportation Mode | Drive Alone, Carpool, WFH majority |

### Section 3: Two-Way Cross-Tabulations (18 queries)

Crosses meaningful pairs of dimensions to surface **interaction effects** — cases where the combination of two factors matters more than either alone:

```
Dwelling    × {Kids, Ownership, Family}
Kids        × {Ownership, Family}
Ownership   × Family
Kids Group  × {Dwelling, Ownership}
Labor       × {Dwelling, Kids, Ownership, Family, Kids Group}
Transport   × {Dwelling, Kids, Ownership, Family, Kids Group}
```

### Section 4: Full Demographic Correlation Pull

One wide query outputting all ~55 census demographic columns plus penetration at the census-block-group level. Designed for export to Python/R for:
- Correlation matrices
- Feature importance ranking
- Regression or tree-based modeling

## Data Requirements

Your source table needs these column families (names are generic — map to your schema):

```
HOUSEHOLD_DAILY_HISTORY
├── DAILY_TIME_KEY              ← date of snapshot
├── CUSTOMER_KEY / CUSTOMER_FLAG ← subscriber indicator
├── CENSUS_BLOCK_GROUP          ← geographic grouping (US Census)
├── DWELLING_SEGMENT            ← housing type (apartment/house)
├── BULK_FLG                    ← 1 if bulk/MDU arrangement
├── CHILDREN_PER_HH             ← avg children per household in block
├── TOTAL_FAMILIES_W/WO_CHILDREN ← family counts with/without children
├── PERC_OWNER_OCCUPIED         ← 0-1 proportion of owner-occupied housing
├── TOTAL_IN/NOT_IN_LABOR_FORCE ← labor participation counts
├── TRANSPORTATION_*            ← commute mode counts (drive, carpool, WFH)
├── HOME_VALUE_*                ← home value distribution buckets
├── TOTAL_FAMILIES / TOTAL_HOUSEHOLDS ← for family ratio calculation
└── PERC_HH_W_CHILDREN, MEDIAN_HH_AGE, PERC_DEGREE_BACHELORS_ABOVE, etc.
```

These fields are available from the US Census Bureau's American Community Survey (ACS) at the block group level, joined to your household/serviceable-address table.

## Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `<DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY` | Your enriched household fact table | `DW.CENSUS.HH_DAILY` |
| `<SNAPSHOT_DATE_CURRENT>` | Current year snapshot | `'2025-03-31'` |
| `<SNAPSHOT_DATE_PRIOR>` | Prior year snapshot | `'2024-03-31'` |

## Usage

These are **not** meant to be run as a single script. Pick individual queries based on your analysis needs:

```sql
-- Run just the dwelling segment cut (query 2a)
-- Export the full correlation pull (Section 4) to CSV for pandas analysis
```

### Suggested Workflow

1. Run the single-dimension cuts (Section 2) to identify which factors have the largest penetration spread
2. For top factors, run relevant two-way cross-tabs (Section 3) to check for interaction effects
3. Export Section 4 for statistical modeling (logistic regression, random forest feature importance, etc.)

## Output Format

Every query returns a consistent structure:

| Column | Description |
|--------|-------------|
| *dimension_columns* | The demographic buckets being analyzed |
| `DAILY_TIME_KEY` | Snapshot date (for YoY comparison) |
| `customer_count` | Number of subscribers in segment |
| `total_households` | Total households in segment |
| `penetration_rate` | customer_count / total_households (0.0–1.0) |

## Interpreting Results

- **Penetration rate** is a decimal (0.0–1.0). Multiply by 100 for percentage.
- **YoY comparison** — look for segments where penetration changed significantly. This may indicate emerging opportunities or competitive pressure.
- **Cross-tab interactions** — a segment might show average penetration alone but very high/low penetration when combined with another factor (e.g., apartments in high-kid areas).
- **Statistical significance** — for segments with small `total_households`, penetration differences may not be meaningful. Consider minimum sample sizes when drawing conclusions.

## Adapting This Analysis

This pattern works for any subscription business with geographic/demographic enrichment:

1. **Telecom** (broadband, cable, fiber) — the original use case
2. **Utilities** — adoption of optional services (solar, EV charging, smart home)
3. **Insurance** — penetration by neighborhood demographics
4. **Retail banking** — product adoption by census tract

To adapt: replace the customer flag logic and add/remove demographic dimensions relevant to your market.

## Design Decisions

- **`* 1.0` in divisions** — ensures float division rather than integer truncation.
- **NULL filters** — each query explicitly filters out NULL values, preventing misleading bucket counts.
- **`TOTAL_HOUSEHOLDS != 0`** — guards against division-by-zero in ratio calculations.
- **`SELECT *` in CTEs** — used for readability in exploratory context. For production, replace with explicit column lists.
- **No competitor dimension** — deliberately excluded from this public version. In practice, you'd add a `PRIMARY_COMPETITOR` field for competitive analysis.

## Requirements

- **Snowflake** (standard SQL dialect, uses `GROUP BY ALL`)
- Read access to the household daily history table
- A warehouse sized for full scans of household-level data (can be large — one row per household per day)
- For Section 4: a downstream tool (Python, R, Excel) for statistical analysis

## License

MIT
