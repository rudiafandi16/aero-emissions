-- DIAGNOSTIC QUERY: Debug Aerodrome Voting Data
-- Compare against website: https://aerodrome.finance/vote?sort=votes%3Adesc

-- Step 1: Check raw voting events from the last 30 days
WITH recent_votes AS (
  SELECT
    voter AS user_address,
    pool AS pool_address,
    weight / 1e18 AS vote_weight,
    evt_block_time,
    evt_tx_hash,
    evt_block_number
  FROM aerodrome_base.voter_evt_voted
  WHERE contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
    AND evt_block_time >= NOW() - INTERVAL '30' DAY
  ORDER BY evt_block_time DESC
  LIMIT 1000
),

-- Step 2: Get each user's LATEST vote for each pool (across all time, not just epoch)
-- THEORY: Maybe votes persist across epochs until user changes them
latest_user_pool_votes AS (
  SELECT
    voter AS user_address,
    pool AS pool_address,
    weight / 1e18 AS vote_weight,
    evt_block_time,
    ROW_NUMBER() OVER (
      PARTITION BY voter, pool
      ORDER BY evt_block_time DESC, evt_tx_hash DESC
    ) AS rn
  FROM aerodrome_base.voter_evt_voted
  WHERE contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
    AND weight > 0  -- Only active votes, ignore zero-weight (vote removal)
),

-- Step 3: Aggregate total votes per pool (from ALL active votes, not just current epoch)
pool_totals AS (
  SELECT
    pool_address,
    SUM(vote_weight) AS total_pool_votes,
    COUNT(DISTINCT user_address) AS voter_count
  FROM latest_user_pool_votes
  WHERE rn = 1  -- Most recent vote per user per pool
  GROUP BY pool_address
),

-- Step 4: Get total votes across all pools
vote_summary AS (
  SELECT
    pool_address,
    total_pool_votes,
    voter_count,
    SUM(total_pool_votes) OVER () AS total_votes_all_pools
  FROM pool_totals
),

-- Step 5: Get pool names from TVL table
pool_names AS (
  SELECT
    id AS pool_address,
    token0_symbol || '/' || token1_symbol AS pool_name,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY block_date DESC) AS rn
  FROM aerodrome.tvl_daily
  WHERE blockchain = 'base'
),

-- Step 6: Combine with pool names
pools_with_names AS (
  SELECT
    v.pool_address,
    COALESCE(p.pool_name, CAST(v.pool_address AS VARCHAR)) AS pool_name,
    v.total_pool_votes,
    v.voter_count,
    v.total_votes_all_pools,
    (v.total_pool_votes / v.total_votes_all_pools * 100) AS vote_percentage
  FROM vote_summary v
  LEFT JOIN pool_names p ON v.pool_address = p.pool_address AND p.rn = 1
)

-- Output top 20 pools to compare with website
SELECT
  pool_address AS "Pool Address",
  pool_name AS "Pool Name",
  ROUND(total_pool_votes, 2) AS "Total Votes",
  voter_count AS "# Voters",
  ROUND(vote_percentage, 4) AS "Vote %",
  ROUND(total_votes_all_pools, 2) AS "Total Votes (All Pools)"
FROM pools_with_names
ORDER BY total_pool_votes DESC
LIMIT 20;

-- ============================================================================
-- THEORY TO TEST:
-- Aerodrome voting might work like this:
-- 1. Users vote for pools and those votes PERSIST until changed
-- 2. Votes don't expire at epoch end - they stay active
-- 3. The epoch window only matters for EMISSIONS calculation, not vote counting
-- 4. So we should count ALL active votes (latest per user per pool), not just
--    votes cast within the current epoch window
-- ============================================================================
