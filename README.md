# penetration-census-analysis

Systematic exploration of which household and census-block demographics correlate with subscriber penetration, using Snowflake SQL.

## Overview

This is an **analytical workbench** — a collection of ~35 SQL queries that slice customer penetration rate across demographic dimensions individually and in pairwise combinations. The goal is to identify which household characteristics are the strongest predictors of subscription, informing targeting strategy, market planning, and predictive modeling.

All queries run against a single census-enriched household-level fact table, comparing two year-over-year daily snapshots.

## Analysis Structure

### Section 1: Census Block Group Summary

Aggregates households by census block group with home value distribution, dwelling mix, customer counts, and bulk status. Produces a dataset suitable for direct correlation analysis or geographic visualization.

### Section 2: Single-Dimension Penetration Cuts (11 queries)

Each query isolates one demographic variable and computes penetration rate by bucket:

| Query | Dimension | Buckets |
|-------|-----------|---------|
| 2a | Dwelling Segment | Apartment, House |
| 2b | Bulk Status | Bulk flag on household |
| 2c | Block-Level Bulk Presence | Any bulk in census block vs none |
| 2d | Children per Household | no_kids, low, med, high |
| 2e | Primary Competitor | Named competitors in area |
| 2f | Family Composition | family_dominant, non_family, even_split |
| 2g | Ownership Level | low → high (quartiles of % owner-occupied) |
| 2h | Internet Tier Available | Digital Equity → Extra (speed-based grouping) |
| 2i | Kids Group (block-level) | More Kids vs Less Kids majority |
| 2j | Labor Force | Labor Majority vs Minority |
| 2k | Transportation Mode | Drive Alone, Carpool, WFH majority |

### Section 3: Two-Way Cross-Tabulations (25 queries)

Crosses every meaningful pair of dimensions to surface **interaction effects** — cases where the combination of two factors matters more than either alone:

```
Dwelling × {Kids, Competitor, Ownership, Family}
Kids     × {Competitor, Ownership, Family}
Competitor × {Ownership, Family}
Ownership × Family
Kids Group × {Dwelling, Competitor, Ownership}
Labor    × {Dwelling, Kids, Competitor, Ownership, Family, Kids Group}
Transport × {Dwelling, Kids, Competitor, Ownership, Family, Kids Group}
```

### Section 4: Full Demographic Correlation Pull

One wide query outputting all ~55 census demographic columns plus penetration at the census-block-group level. Designed for export to Python/R for:
- Correlation matrices
- Feature importance ranking
- Regression or tree-based modeling

## Data Model

```
HOUSEHOLD_DAILY_HISTORY
├── DAILY_TIME_KEY          ← date of snapshot
├── CUSTOMER_KEY            ← >0 indicates active subscriber
├── CUSTOMER_FLAG           ← 1/0 subscriber indicator
├── CENSUS_BLOCK_GROUP      ← geographic grouping
├── DWELLING_SEGMENT        ← APARTMENT / HOUSE
├── PRIMARY_COMPETITOR      ← dominant competitor in area
├── BULK_FLG                ← 1 if bulk/MDU arrangement
├── CHILDREN_PER_HH         ← avg children per household in block
├── TOTAL_FAMILIES_W/WO_CHILDREN
├── PERC_OWNER_OCCUPIED     ← 0-1 proportion
├── TOTAL_IN/NOT_IN_LABOR_FORCE
├── TRANSPORTATION_*        ← drive alone, carpool, WFH counts
├── HOME_VALUE_*            ← distribution buckets
├── CHSI_HIGHEST_TIER_BEFORE_NM  ← best available internet tier
└── ... (55+ demographic columns from census enrichment)
```

## Configuration

Replace this single placeholder throughout the file:

| Placeholder | Description |
|-------------|-------------|
| `<DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY` | Your census-enriched daily household fact table |

### Date Pairs

Most queries compare `2024-03-31` vs `2025-03-31`. Update the `DAILY_TIME_KEY IN (...)` filters to use your preferred comparison dates. The dates should be valid daily snapshots in your table.

## Usage

These are **not** meant to be run as a single script. Pick individual queries based on your analysis needs:

```sql
-- Example: Run just the dwelling segment cut
-- Copy query 2a and execute in your SQL client

-- Example: Export the full correlation pull (Section 4) for Python analysis
-- Run query 4, export to CSV, load into pandas for correlation matrix
```

### Suggested workflow

1. Run the single-dimension cuts (Section 2) to identify which factors have the largest penetration spread
2. For the top factors, run the relevant two-way cross-tabs (Section 3) to check for interaction effects
3. Export Section 4 for statistical modeling

## Output Format

Every query returns a consistent structure:

| Column | Description |
|--------|-------------|
| *dimension_columns* | The demographic buckets being analyzed |
| `DAILY_TIME_KEY` | Snapshot date (for YoY comparison) |
| `customer_count` | Number of subscribers in segment |
| `total_households` | Total households in segment |
| `penetration_rate` | customer_count / total_households |

## Interpreting Results

- **Penetration rate** is expressed as a decimal (0.0–1.0) in most queries. Multiply by 100 for percentage.
- **YoY comparison** — look for segments where penetration changed significantly between the two dates. This may indicate emerging opportunities or competitive pressure.
- **Cross-tab interactions** — a segment might show average penetration alone but very high/low penetration when combined with another factor (e.g., apartments + high-kid areas).

## Requirements

- **Snowflake** (standard SQL dialect)
- Read access to the household daily history table
- A warehouse sized for full scans of the household table (can be large — one row per household per day)
- For Section 4 export: a downstream tool (Python, R, Excel) for correlation analysis

## Design Decisions

- **`* 1.0` in divisions** ensures float output rather than integer division truncation.
- **NULL filters** — each query explicitly filters out NULL values for the dimensions being analyzed, preventing misleading bucket counts.
- **`TOTAL_HOUSEHOLDS != 0`** guards against division-by-zero in family/labor ratio calculations.
- **No NULLIF in penetration** — since we filter NULLs and zeros in the WHERE clause, the denominator (`COUNT(*)`) is always > 0.
- **`SELECT *` in CTEs** — used intentionally for readability in an exploratory context. For production deployment, replace with explicit column lists.

## License

MIT
