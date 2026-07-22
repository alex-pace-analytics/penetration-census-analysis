-- Penetration analysis by census demographics: household subscription drivers
-- Co-authored with CoCo

--------------------------------------------------------------------------------
-- PENETRATION × CENSUS DEMOGRAPHICS ANALYSIS
--
-- A workbench of queries that slice customer penetration rate by demographic
-- dimensions from census-enriched household data. Used for correlation analysis
-- and identifying which household characteristics predict subscription.
--
-- Source table: A daily household-level fact table enriched with census block
-- group demographics (housing, family composition, labor, transportation, etc.)
--
-- CONFIGURATION:
--   Replace <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY with your table.
--   Replace <SNAPSHOT_DATE_CURRENT> and <SNAPSHOT_DATE_PRIOR> with your dates.
--   See the "Placeholders" section at the bottom of this file.
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- 1. CENSUS BLOCK GROUP SUMMARY
--------------------------------------------------------------------------------

WITH census_block_summary AS (
    SELECT
        DAILY_TIME_KEY,
        CENSUS_BLOCK_GROUP,
        PERC_HH_W_CHILDREN,
        HOME_VALUE_0K_50K,
        HOME_VALUE_50K_100K,
        HOME_VALUE_100K_250K,
        HOME_VALUE_250K_500K,
        HOME_VALUE_500K_1M,
        HOME_VALUE_GREATER_1M,
        1 - PERC_HH_W_CHILDREN AS perc_hh_wo_children,
        COUNT(CASE WHEN DWELLING_SEGMENT = 'APARTMENT' THEN 1 END) AS apartment_count,
        COUNT(CASE WHEN DWELLING_SEGMENT = 'HOUSE' THEN 1 END) AS house_count,
        COUNT(1) AS hhs,
        SUM(CASE WHEN CUSTOMER_KEY > 0 THEN 1 ELSE 0 END) AS num_customers,
        SUM(CASE WHEN BULK_FLG = 1 THEN 1 ELSE 0 END) AS bulk_hhs
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
)
SELECT
    DAILY_TIME_KEY,
    CENSUS_BLOCK_GROUP,
    hhs,
    num_customers,
    PERC_HH_W_CHILDREN,
    perc_hh_wo_children,
    bulk_hhs,
    num_customers / NULLIF(hhs, 0) AS penetration,
    bulk_hhs / NULLIF(hhs, 0) AS bulk_pct,
    apartment_count,
    house_count,
    HOME_VALUE_0K_50K,
    HOME_VALUE_50K_100K,
    HOME_VALUE_100K_250K,
    HOME_VALUE_250K_500K,
    HOME_VALUE_500K_1M,
    HOME_VALUE_GREATER_1M
FROM census_block_summary
ORDER BY CENSUS_BLOCK_GROUP, DAILY_TIME_KEY;


--------------------------------------------------------------------------------
-- 2. SINGLE-DIMENSION PENETRATION CUTS
--------------------------------------------------------------------------------

-- 2a. Dwelling Segment (Apartment vs House)
SELECT
    DWELLING_SEGMENT,
    DAILY_TIME_KEY,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(*) AS total_households,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
  AND DWELLING_SEGMENT IS NOT NULL
GROUP BY DWELLING_SEGMENT, DAILY_TIME_KEY;


-- 2b. Bulk vs Non-Bulk (MDU/bulk arrangements)
SELECT
    DAILY_TIME_KEY,
    BULK_FLG,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(*) AS total_households,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
GROUP BY BULK_FLG, DAILY_TIME_KEY;


-- 2c. Bulk presence at census block level
WITH block_bulk_status AS (
    SELECT
        CENSUS_BLOCK_GROUP,
        MAX(BULK_FLG) AS has_bulk_flag
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    GROUP BY CENSUS_BLOCK_GROUP
),
households_with_bulk_flag_status AS (
    SELECT
        t.*,
        CASE WHEN b.has_bulk_flag = 1 THEN 'has_bulk' ELSE 'no_bulk' END AS block_bulk_status
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY t
    JOIN block_bulk_status b ON t.CENSUS_BLOCK_GROUP = b.CENSUS_BLOCK_GROUP
)
SELECT
    block_bulk_status,
    DAILY_TIME_KEY,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(*) AS total_households,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM households_with_bulk_flag_status
WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
GROUP BY block_bulk_status, DAILY_TIME_KEY;


-- 2d. Children per household (bucketed)
SELECT
    DAILY_TIME_KEY,
    CASE
        WHEN CHILDREN_PER_HH < 1 THEN 'no_kids'
        WHEN CHILDREN_PER_HH < 2 THEN 'low_kids'
        WHEN CHILDREN_PER_HH < 3 THEN 'med_kids'
        ELSE 'high_kids'
    END AS kids_bucket,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(*) AS total_households,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
  AND CHILDREN_PER_HH IS NOT NULL
GROUP BY DAILY_TIME_KEY, kids_bucket
ORDER BY DAILY_TIME_KEY, kids_bucket;


-- 2e. Family-dominant vs Non-family-dominant households
WITH household_mix_labeled AS (
    SELECT
        *,
        CASE
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS >= 0.6 THEN 'family_dominant'
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS <= 0.4 THEN 'non_family_dominant'
            ELSE 'even_split'
        END AS household_mix
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
)
SELECT
    household_mix,
    DAILY_TIME_KEY,
    COUNT(*) AS total_households,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customers,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM household_mix_labeled
GROUP BY household_mix, DAILY_TIME_KEY
ORDER BY household_mix, DAILY_TIME_KEY;


-- 2f. Ownership level (bucketed by % owner-occupied)
SELECT
    DAILY_TIME_KEY,
    CASE
        WHEN PERC_OWNER_OCCUPIED < 0.25 THEN 'low_ownership'
        WHEN PERC_OWNER_OCCUPIED < 0.5  THEN 'mid_low_ownership'
        WHEN PERC_OWNER_OCCUPIED < 0.75 THEN 'mid_high_ownership'
        ELSE 'high_ownership'
    END AS ownership_bucket,
    COUNT(*) AS total_hhs,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
  AND PERC_OWNER_OCCUPIED IS NOT NULL
GROUP BY DAILY_TIME_KEY, ownership_bucket
ORDER BY DAILY_TIME_KEY, ownership_bucket;


-- 2g. Kids vs Non-Kids (block-level family majority)
WITH kids_v_non_kids AS (
    SELECT
        *,
        CASE
            WHEN TOTAL_FAMILIES_WO_CHILDREN > TOTAL_FAMILIES_W_CHILDREN THEN 'Less Kids'
            WHEN TOTAL_FAMILIES_WO_CHILDREN <= TOTAL_FAMILIES_W_CHILDREN THEN 'More Kids'
            ELSE 'Equal'
        END AS kids_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TOTAL_FAMILIES_WO_CHILDREN IS NOT NULL
      AND TOTAL_FAMILIES_W_CHILDREN IS NOT NULL
)
SELECT
    kids_group,
    DAILY_TIME_KEY,
    COUNT(*) AS total_households,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customers,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM kids_v_non_kids
GROUP BY kids_group, DAILY_TIME_KEY
ORDER BY kids_group, DAILY_TIME_KEY;


-- 2h. Labor Force participation
WITH labor_force AS (
    SELECT
        *,
        CASE
            WHEN TOTAL_IN_LABOR_FORCE > TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Majority'
            WHEN TOTAL_IN_LABOR_FORCE < TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Minority'
            ELSE 'Equal'
        END AS labor_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TOTAL_IN_LABOR_FORCE IS NOT NULL
      AND TOTAL_NOT_IN_LABOR_FORCE IS NOT NULL
)
SELECT
    labor_group,
    DAILY_TIME_KEY,
    COUNT(*) AS total_households,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customers,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM labor_force
GROUP BY labor_group, DAILY_TIME_KEY
ORDER BY labor_group, DAILY_TIME_KEY;


-- 2i. Transportation mode (dominant in block)
WITH base AS (
    SELECT
        *,
        CASE
            WHEN TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_CARPOOL
             AND TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_WORK_FROM_HOME THEN 'Drive Alone Majority'
            WHEN TRANSPORTATION_CARPOOL > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_CARPOOL > TRANSPORTATION_WORK_FROM_HOME THEN 'Carpool Majority'
            WHEN TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_CARPOOL THEN 'WFH Majority'
            ELSE 'Other'
        END AS transport_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TRANSPORTATION_DRIVE_ALONE IS NOT NULL
      AND TRANSPORTATION_CARPOOL IS NOT NULL
      AND TRANSPORTATION_WORK_FROM_HOME IS NOT NULL
)
SELECT
    transport_group,
    DAILY_TIME_KEY,
    COUNT(*) AS total_households,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customers,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY transport_group, DAILY_TIME_KEY
ORDER BY transport_group, DAILY_TIME_KEY;


--------------------------------------------------------------------------------
-- 3. TWO-WAY CROSS-TABULATIONS
--
-- Each query crosses two demographic dimensions to find interaction effects
-- on penetration rate. The pattern is consistent:
--   GROUP BY dimension_a, dimension_b, DAILY_TIME_KEY
--   Output: household_count, customer_count, penetration_rate
--
-- Combinations covered:
--   Dwelling × {Kids, Ownership, Family}
--   Kids     × {Ownership, Family}
--   Ownership × Family
--   Kids Group × {Dwelling, Ownership}
--   Labor    × {Dwelling, Kids, Ownership, Family, Kids Group}
--   Transport × {Dwelling, Kids, Ownership, Family, Kids Group}
--------------------------------------------------------------------------------

-- 3a. Dwelling Segment × Children
SELECT
    DAILY_TIME_KEY,
    DWELLING_SEGMENT,
    CASE
        WHEN CHILDREN_PER_HH < 1 THEN 'no_kids'
        WHEN CHILDREN_PER_HH < 2 THEN 'low_kids'
        WHEN CHILDREN_PER_HH < 3 THEN 'med_kids'
        ELSE 'high_kids'
    END AS kids_bucket,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(*) AS total_households,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
  AND CHILDREN_PER_HH IS NOT NULL
GROUP BY DAILY_TIME_KEY, DWELLING_SEGMENT, kids_bucket
ORDER BY DAILY_TIME_KEY, DWELLING_SEGMENT, kids_bucket;


-- 3b. Dwelling Segment × Ownership
WITH base AS (
    SELECT
        DWELLING_SEGMENT,
        DAILY_TIME_KEY,
        CUSTOMER_FLAG,
        CASE
            WHEN PERC_OWNER_OCCUPIED < 0.25 THEN 'low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.5  THEN 'mid_low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.75 THEN 'mid_high_ownership'
            ELSE 'high_ownership'
        END AS ownership_bucket
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND DWELLING_SEGMENT IS NOT NULL
      AND PERC_OWNER_OCCUPIED IS NOT NULL
)
SELECT
    DWELLING_SEGMENT,
    ownership_bucket,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY DWELLING_SEGMENT, ownership_bucket, DAILY_TIME_KEY
ORDER BY DWELLING_SEGMENT, ownership_bucket, DAILY_TIME_KEY;


-- 3c. Dwelling Segment × Family Mix
WITH household_mix_labeled AS (
    SELECT
        DWELLING_SEGMENT,
        DAILY_TIME_KEY,
        CUSTOMER_FLAG,
        CASE
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS >= 0.6 THEN 'family_dominant'
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS <= 0.4 THEN 'non_family_dominant'
            ELSE 'even_split'
        END AS household_mix
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND DWELLING_SEGMENT IS NOT NULL
      AND TOTAL_FAMILIES IS NOT NULL
      AND TOTAL_HOUSEHOLDS != 0
)
SELECT
    DWELLING_SEGMENT,
    household_mix,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM household_mix_labeled
GROUP BY DWELLING_SEGMENT, household_mix, DAILY_TIME_KEY
ORDER BY DWELLING_SEGMENT, household_mix, DAILY_TIME_KEY;


-- 3d. Children × Ownership
WITH base AS (
    SELECT
        DAILY_TIME_KEY,
        CUSTOMER_FLAG,
        CASE
            WHEN CHILDREN_PER_HH < 1 THEN 'no_kids'
            WHEN CHILDREN_PER_HH < 2 THEN 'low_kids'
            WHEN CHILDREN_PER_HH < 3 THEN 'med_kids'
            ELSE 'high_kids'
        END AS kids_bucket,
        CASE
            WHEN PERC_OWNER_OCCUPIED < 0.25 THEN 'low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.5  THEN 'mid_low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.75 THEN 'mid_high_ownership'
            ELSE 'high_ownership'
        END AS ownership_bucket
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND CHILDREN_PER_HH IS NOT NULL
      AND PERC_OWNER_OCCUPIED IS NOT NULL
)
SELECT
    kids_bucket,
    ownership_bucket,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY kids_bucket, ownership_bucket, DAILY_TIME_KEY
ORDER BY kids_bucket, ownership_bucket, DAILY_TIME_KEY;


-- 3e. Children × Family Mix
WITH base AS (
    SELECT
        DAILY_TIME_KEY,
        CUSTOMER_FLAG,
        CASE
            WHEN CHILDREN_PER_HH < 1 THEN 'no_kids'
            WHEN CHILDREN_PER_HH < 2 THEN 'low_kids'
            WHEN CHILDREN_PER_HH < 3 THEN 'med_kids'
            ELSE 'high_kids'
        END AS kids_bucket,
        CASE
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS >= 0.6 THEN 'family_dominant'
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS <= 0.4 THEN 'non_family_dominant'
            ELSE 'even_split'
        END AS household_mix
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND CHILDREN_PER_HH IS NOT NULL
      AND TOTAL_FAMILIES IS NOT NULL
      AND TOTAL_HOUSEHOLDS != 0
)
SELECT
    kids_bucket,
    household_mix,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY kids_bucket, household_mix, DAILY_TIME_KEY
ORDER BY kids_bucket, household_mix, DAILY_TIME_KEY;


-- 3f. Ownership × Family Mix
WITH base AS (
    SELECT
        *,
        CASE
            WHEN PERC_OWNER_OCCUPIED < 0.25 THEN 'low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.5  THEN 'mid_low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.75 THEN 'mid_high_ownership'
            ELSE 'high_ownership'
        END AS ownership_bucket,
        CASE
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS >= 0.6 THEN 'family_dominant'
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS <= 0.4 THEN 'non_family_dominant'
            ELSE 'even_split'
        END AS household_mix
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND PERC_OWNER_OCCUPIED IS NOT NULL
      AND TOTAL_FAMILIES IS NOT NULL
)
SELECT
    ownership_bucket,
    household_mix,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY ownership_bucket, household_mix, DAILY_TIME_KEY
ORDER BY ownership_bucket, household_mix, DAILY_TIME_KEY;


-- 3g. Kids Group × Dwelling Segment
WITH kids_v_non_kids AS (
    SELECT
        *,
        CASE
            WHEN TOTAL_FAMILIES_WO_CHILDREN > TOTAL_FAMILIES_W_CHILDREN THEN 'Less Kids'
            WHEN TOTAL_FAMILIES_WO_CHILDREN <= TOTAL_FAMILIES_W_CHILDREN THEN 'More Kids'
            ELSE 'Equal'
        END AS kids_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TOTAL_FAMILIES_WO_CHILDREN IS NOT NULL
      AND TOTAL_FAMILIES_W_CHILDREN IS NOT NULL
)
SELECT
    DWELLING_SEGMENT,
    kids_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM kids_v_non_kids
WHERE DWELLING_SEGMENT IS NOT NULL
GROUP BY DWELLING_SEGMENT, kids_group, DAILY_TIME_KEY
ORDER BY DWELLING_SEGMENT, kids_group, DAILY_TIME_KEY;


-- 3h. Kids Group × Ownership
WITH base AS (
    SELECT
        *,
        CASE
            WHEN PERC_OWNER_OCCUPIED < 0.25 THEN 'low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.5  THEN 'mid_low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.75 THEN 'mid_high_ownership'
            ELSE 'high_ownership'
        END AS ownership_bucket,
        CASE
            WHEN TOTAL_FAMILIES_WO_CHILDREN > TOTAL_FAMILIES_W_CHILDREN THEN 'Less Kids'
            WHEN TOTAL_FAMILIES_WO_CHILDREN <= TOTAL_FAMILIES_W_CHILDREN THEN 'More Kids'
            ELSE 'Equal'
        END AS kids_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND PERC_OWNER_OCCUPIED IS NOT NULL
      AND TOTAL_FAMILIES_WO_CHILDREN IS NOT NULL
      AND TOTAL_FAMILIES_W_CHILDREN IS NOT NULL
)
SELECT
    ownership_bucket,
    kids_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY ownership_bucket, kids_group, DAILY_TIME_KEY
ORDER BY ownership_bucket, kids_group, DAILY_TIME_KEY;


-- 3i. Labor Force × Dwelling Segment
WITH labor_force AS (
    SELECT
        *,
        CASE
            WHEN TOTAL_IN_LABOR_FORCE > TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Majority'
            WHEN TOTAL_IN_LABOR_FORCE < TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Minority'
            ELSE 'Equal'
        END AS labor_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TOTAL_IN_LABOR_FORCE IS NOT NULL
      AND TOTAL_NOT_IN_LABOR_FORCE IS NOT NULL
)
SELECT
    DWELLING_SEGMENT,
    labor_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM labor_force
WHERE DWELLING_SEGMENT IS NOT NULL
GROUP BY DWELLING_SEGMENT, labor_group, DAILY_TIME_KEY
ORDER BY DWELLING_SEGMENT, labor_group, DAILY_TIME_KEY;


-- 3j. Labor Force × Children (bucketed)
WITH base AS (
    SELECT
        DAILY_TIME_KEY,
        CUSTOMER_FLAG,
        CASE
            WHEN CHILDREN_PER_HH < 1 THEN 'no_kids'
            WHEN CHILDREN_PER_HH < 2 THEN 'low_kids'
            WHEN CHILDREN_PER_HH < 3 THEN 'med_kids'
            ELSE 'high_kids'
        END AS kids_bucket,
        CASE
            WHEN TOTAL_IN_LABOR_FORCE > TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Majority'
            WHEN TOTAL_IN_LABOR_FORCE < TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Minority'
            ELSE 'Equal'
        END AS labor_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND CHILDREN_PER_HH IS NOT NULL
      AND TOTAL_IN_LABOR_FORCE IS NOT NULL
      AND TOTAL_NOT_IN_LABOR_FORCE IS NOT NULL
      AND TOTAL_HOUSEHOLDS != 0
)
SELECT
    kids_bucket,
    labor_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY kids_bucket, labor_group, DAILY_TIME_KEY
ORDER BY kids_bucket, labor_group, DAILY_TIME_KEY;


-- 3k. Labor Force × Ownership
WITH base AS (
    SELECT
        *,
        CASE
            WHEN PERC_OWNER_OCCUPIED < 0.25 THEN 'low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.5  THEN 'mid_low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.75 THEN 'mid_high_ownership'
            ELSE 'high_ownership'
        END AS ownership_bucket,
        CASE
            WHEN TOTAL_IN_LABOR_FORCE > TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Majority'
            WHEN TOTAL_IN_LABOR_FORCE < TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Minority'
            ELSE 'Equal'
        END AS labor_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND PERC_OWNER_OCCUPIED IS NOT NULL
      AND TOTAL_IN_LABOR_FORCE IS NOT NULL
      AND TOTAL_NOT_IN_LABOR_FORCE IS NOT NULL
)
SELECT
    ownership_bucket,
    labor_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY ownership_bucket, labor_group, DAILY_TIME_KEY
ORDER BY ownership_bucket, labor_group, DAILY_TIME_KEY;


-- 3l. Labor Force × Family Mix
WITH base AS (
    SELECT
        *,
        CASE
            WHEN TOTAL_IN_LABOR_FORCE > TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Majority'
            WHEN TOTAL_IN_LABOR_FORCE < TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Minority'
            ELSE 'Equal'
        END AS labor_group,
        CASE
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS >= 0.6 THEN 'family_dominant'
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS <= 0.4 THEN 'non_family_dominant'
            ELSE 'even_split'
        END AS household_mix
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TOTAL_IN_LABOR_FORCE IS NOT NULL
      AND TOTAL_NOT_IN_LABOR_FORCE IS NOT NULL
      AND TOTAL_FAMILIES IS NOT NULL
)
SELECT
    labor_group,
    household_mix,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY labor_group, household_mix, DAILY_TIME_KEY
ORDER BY labor_group, household_mix, DAILY_TIME_KEY;


-- 3m. Labor Force × Kids Group
WITH base AS (
    SELECT
        *,
        CASE
            WHEN TOTAL_IN_LABOR_FORCE > TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Majority'
            WHEN TOTAL_IN_LABOR_FORCE < TOTAL_NOT_IN_LABOR_FORCE THEN 'Labor Minority'
            ELSE 'Equal'
        END AS labor_group,
        CASE
            WHEN TOTAL_FAMILIES_WO_CHILDREN > TOTAL_FAMILIES_W_CHILDREN THEN 'Less Kids'
            WHEN TOTAL_FAMILIES_WO_CHILDREN <= TOTAL_FAMILIES_W_CHILDREN THEN 'More Kids'
            ELSE 'Equal'
        END AS kids_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TOTAL_IN_LABOR_FORCE IS NOT NULL
      AND TOTAL_NOT_IN_LABOR_FORCE IS NOT NULL
      AND TOTAL_FAMILIES_WO_CHILDREN IS NOT NULL
      AND TOTAL_FAMILIES_W_CHILDREN IS NOT NULL
)
SELECT
    labor_group,
    kids_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) AS customer_count,
    COUNT(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY labor_group, kids_group, DAILY_TIME_KEY
ORDER BY labor_group, kids_group, DAILY_TIME_KEY;


-- 3n. Transportation × Dwelling Segment
WITH base AS (
    SELECT
        *,
        CASE
            WHEN TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_CARPOOL
             AND TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_WORK_FROM_HOME THEN 'Drive Alone Majority'
            WHEN TRANSPORTATION_CARPOOL > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_CARPOOL > TRANSPORTATION_WORK_FROM_HOME THEN 'Carpool Majority'
            WHEN TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_CARPOOL THEN 'WFH Majority'
            ELSE 'Other'
        END AS transport_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TRANSPORTATION_DRIVE_ALONE IS NOT NULL
      AND TRANSPORTATION_CARPOOL IS NOT NULL
      AND TRANSPORTATION_WORK_FROM_HOME IS NOT NULL
)
SELECT
    DWELLING_SEGMENT,
    transport_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
WHERE DWELLING_SEGMENT IS NOT NULL
GROUP BY DWELLING_SEGMENT, transport_group, DAILY_TIME_KEY
ORDER BY DWELLING_SEGMENT, transport_group, DAILY_TIME_KEY;


-- 3o. Transportation × Children (bucketed)
WITH base AS (
    SELECT
        *,
        CASE
            WHEN CHILDREN_PER_HH < 1 THEN 'no_kids'
            WHEN CHILDREN_PER_HH < 2 THEN 'low_kids'
            WHEN CHILDREN_PER_HH < 3 THEN 'med_kids'
            ELSE 'high_kids'
        END AS kids_bucket,
        CASE
            WHEN TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_CARPOOL
             AND TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_WORK_FROM_HOME THEN 'Drive Alone Majority'
            WHEN TRANSPORTATION_CARPOOL > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_CARPOOL > TRANSPORTATION_WORK_FROM_HOME THEN 'Carpool Majority'
            WHEN TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_CARPOOL THEN 'WFH Majority'
            ELSE 'Other'
        END AS transport_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TRANSPORTATION_DRIVE_ALONE IS NOT NULL
      AND TRANSPORTATION_CARPOOL IS NOT NULL
      AND TRANSPORTATION_WORK_FROM_HOME IS NOT NULL
      AND CHILDREN_PER_HH IS NOT NULL
)
SELECT
    kids_bucket,
    transport_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY kids_bucket, transport_group, DAILY_TIME_KEY
ORDER BY kids_bucket, transport_group, DAILY_TIME_KEY;


-- 3p. Transportation × Ownership
WITH base AS (
    SELECT
        *,
        CASE
            WHEN PERC_OWNER_OCCUPIED < 0.25 THEN 'low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.5  THEN 'mid_low_ownership'
            WHEN PERC_OWNER_OCCUPIED < 0.75 THEN 'mid_high_ownership'
            ELSE 'high_ownership'
        END AS ownership_bucket,
        CASE
            WHEN TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_CARPOOL
             AND TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_WORK_FROM_HOME THEN 'Drive Alone Majority'
            WHEN TRANSPORTATION_CARPOOL > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_CARPOOL > TRANSPORTATION_WORK_FROM_HOME THEN 'Carpool Majority'
            WHEN TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_CARPOOL THEN 'WFH Majority'
            ELSE 'Other'
        END AS transport_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TRANSPORTATION_DRIVE_ALONE IS NOT NULL
      AND TRANSPORTATION_CARPOOL IS NOT NULL
      AND TRANSPORTATION_WORK_FROM_HOME IS NOT NULL
      AND PERC_OWNER_OCCUPIED IS NOT NULL
)
SELECT
    ownership_bucket,
    transport_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY ownership_bucket, transport_group, DAILY_TIME_KEY
ORDER BY ownership_bucket, transport_group, DAILY_TIME_KEY;


-- 3q. Transportation × Family Mix
WITH base AS (
    SELECT
        *,
        CASE
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS >= 0.6 THEN 'family_dominant'
            WHEN TOTAL_FAMILIES / TOTAL_HOUSEHOLDS <= 0.4 THEN 'non_family_dominant'
            ELSE 'even_split'
        END AS household_mix,
        CASE
            WHEN TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_CARPOOL
             AND TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_WORK_FROM_HOME THEN 'Drive Alone Majority'
            WHEN TRANSPORTATION_CARPOOL > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_CARPOOL > TRANSPORTATION_WORK_FROM_HOME THEN 'Carpool Majority'
            WHEN TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_CARPOOL THEN 'WFH Majority'
            ELSE 'Other'
        END AS transport_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TRANSPORTATION_DRIVE_ALONE IS NOT NULL
      AND TRANSPORTATION_CARPOOL IS NOT NULL
      AND TRANSPORTATION_WORK_FROM_HOME IS NOT NULL
      AND TOTAL_FAMILIES IS NOT NULL
)
SELECT
    household_mix,
    transport_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY household_mix, transport_group, DAILY_TIME_KEY
ORDER BY household_mix, transport_group, DAILY_TIME_KEY;


-- 3r. Transportation × Kids Group
WITH base AS (
    SELECT
        *,
        CASE
            WHEN TOTAL_FAMILIES_WO_CHILDREN > TOTAL_FAMILIES_W_CHILDREN THEN 'Less Kids'
            WHEN TOTAL_FAMILIES_WO_CHILDREN <= TOTAL_FAMILIES_W_CHILDREN THEN 'More Kids'
            ELSE 'Equal'
        END AS kids_group,
        CASE
            WHEN TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_CARPOOL
             AND TRANSPORTATION_DRIVE_ALONE > TRANSPORTATION_WORK_FROM_HOME THEN 'Drive Alone Majority'
            WHEN TRANSPORTATION_CARPOOL > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_CARPOOL > TRANSPORTATION_WORK_FROM_HOME THEN 'Carpool Majority'
            WHEN TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_DRIVE_ALONE
             AND TRANSPORTATION_WORK_FROM_HOME > TRANSPORTATION_CARPOOL THEN 'WFH Majority'
            ELSE 'Other'
        END AS transport_group
    FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
    WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
      AND TOTAL_HOUSEHOLDS != 0
      AND TRANSPORTATION_DRIVE_ALONE IS NOT NULL
      AND TRANSPORTATION_CARPOOL IS NOT NULL
      AND TRANSPORTATION_WORK_FROM_HOME IS NOT NULL
      AND TOTAL_FAMILIES_WO_CHILDREN IS NOT NULL
      AND TOTAL_FAMILIES_W_CHILDREN IS NOT NULL
)
SELECT
    kids_group,
    transport_group,
    DAILY_TIME_KEY,
    COUNT(*) AS household_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) AS customer_count,
    SUM(CASE WHEN CUSTOMER_FLAG = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS penetration_rate
FROM base
GROUP BY kids_group, transport_group, DAILY_TIME_KEY
ORDER BY kids_group, transport_group, DAILY_TIME_KEY;


--------------------------------------------------------------------------------
-- 4. FULL DEMOGRAPHIC CORRELATION PULL (for offline modeling)
--
-- Outputs one row per census block group with all demographic fields plus
-- penetration rate, suitable for correlation matrices or feature importance.
--------------------------------------------------------------------------------

SELECT
    CENSUS_BLOCK_GROUP,
    TOTAL_HOUSEHOLDS,
    TOTAL_POPULATION,
    TOTAL_FAMILIES,
    TOTAL_LABOR_FORCE,
    TOTAL_IN_LABOR_FORCE,
    PERC_IN_LABOR_FORCE,
    TOTAL_NOT_IN_LABOR_FORCE,
    PERC_NOT_IN_LABOR_FORCE,
    TRANSPORTATION_TOTAL,
    TRANSPORTATION_DRIVE_ALONE,
    TRANSPORTATION_CARPOOL,
    TRANSPORTATION_WORK_FROM_HOME,
    PERC_WORK_FROM_HOME,
    TOTAL_HOUSEHOLD_STATUS,
    TOTAL_OCCUPIED_STATUS,
    PERC_HH_OCCUPIED,
    TOTAL_VACANT_STATUS,
    PERC_HH_VACANT,
    TOTAL_OWNER_OCCUPIED,
    PERC_OWNER_OCCUPIED,
    TOTAL_RENTER_OCCUPIED,
    PERC_RENTER_OCCUPIED,
    TOTAL_MOBILE_HOME,
    PERC_HH_MOBILE_HOME,
    TOTAL_HOME_VALUE,
    HOME_VALUE_0K_50K,
    PERC_HOME_VALUE_0K_50K,
    HOME_VALUE_50K_100K,
    PERC_HOME_VALUE_50K_100K,
    HOME_VALUE_100K_250K,
    PERC_HOME_VALUE_100K_250K,
    HOME_VALUE_250K_500K,
    PERC_HOME_VALUE_250K_500K,
    HOME_VALUE_500K_1M,
    PERC_HOME_VALUE_500K_1M,
    HOME_VALUE_GREATER_1M,
    PERC_HOME_VALUE_GREATER_1M,
    TOTAL_INTERNET_HOUSEHOLD,
    TOTAL_INTERNET_SUBSCRIPTION,
    PERC_HH_INTERNET_SUBSCRIPTION,
    TOTAL_INTERNET_NO_SUBSCRIPTION,
    PERC_HH_NO_INTERNET_SUBSCRIPTION,
    TOTAL_INTERNET_NO_ACCESS,
    PERC_HH_NO_INTERNET_ACCESS,
    POP_PER_HH,
    ADULTS_PER_HH,
    CHILDREN_PER_HH,
    TOTAL_FAMILIES_W_CHILDREN,
    TOTAL_FAMILIES_WO_CHILDREN,
    PERC_HH_W_CHILDREN,
    MEDIAN_HH_AGE,
    TOTAL_EDUCATION,
    TOTAL_DEGREE_BACHELORS_ABOVE,
    PERC_DEGREE_BACHELORS_ABOVE,
    COUNT(1) AS hhs,
    SUM(CASE WHEN CUSTOMER_KEY > 0 THEN 1 ELSE 0 END) AS num_customers,
    SUM(CASE WHEN CUSTOMER_KEY > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(1) AS penetration
FROM <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY
WHERE DAILY_TIME_KEY IN ('<SNAPSHOT_DATE_CURRENT>', '<SNAPSHOT_DATE_PRIOR>')
GROUP BY ALL;


--------------------------------------------------------------------------------
-- PLACEHOLDERS REFERENCE
--
-- <DB>.<SCHEMA>.HOUSEHOLD_DAILY_HISTORY  Your census-enriched household table
-- <SNAPSHOT_DATE_CURRENT>                e.g. '2025-03-31'
-- <SNAPSHOT_DATE_PRIOR>                  e.g. '2024-03-31'
--------------------------------------------------------------------------------
