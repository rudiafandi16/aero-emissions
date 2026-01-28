-- DEEP DIAGNOSTIC: Find why votes don't match Aerodrome website
-- Testing multiple theories about voting data structure

-- ============================================================================
-- PART 1: Check what Voter contract addresses exist
-- ============================================================================
SELECT
  'Voter Contracts' AS check_type,
  contract_address,
  COUNT(*) AS event_count,
  MIN(evt_block_time) AS first_event,
  MAX(evt_block_time) AS latest_event
FROM aerodrome_base.voter_evt_voted
GROUP BY contract_address
ORDER BY latest_event DESC;

-- ============================================================================
-- PART 2: Sample recent raw voting events
-- ============================================================================
SELECT
  'Recent Raw Votes' AS check_type,
  voter,
  pool,
  weight,
  weight / 1e18 AS weight_decimal,
  evt_block_time,
  evt_tx_hash
FROM aerodrome_base.voter_evt_voted
WHERE contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
ORDER BY evt_block_time DESC
LIMIT 20;

-- ============================================================================
-- PART 3: Check if there's a GaugeVoted event or similar
-- ============================================================================
-- Note: This might fail if table doesn't exist
-- SELECT 'Gauge Votes' AS check_type, *
-- FROM aerodrome_base.voter_evt_gaugevoted
-- LIMIT 10;

-- ============================================================================
-- PART 4: Try different aggregation methods
-- ============================================================================

-- Method A: Latest vote per user per pool (our current approach)
WITH method_a AS (
  SELECT
    voter,
    pool,
    weight / 1e18 AS vote_weight,
    evt_block_time,
    ROW_NUMBER() OVER (PARTITION BY voter, pool ORDER BY evt_block_time DESC) AS rn
  FROM aerodrome_base.voter_evt_voted
  WHERE contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
),
method_a_agg AS (
  SELECT
    pool,
    SUM(vote_weight) AS total_votes,
    COUNT(DISTINCT voter) AS voter_count
  FROM method_a
  WHERE rn = 1 AND vote_weight > 0
  GROUP BY pool
),

-- Method B: Latest vote per user OVERALL (maybe users vote for ONE pool at a time?)
method_b AS (
  SELECT
    voter,
    pool,
    weight / 1e18 AS vote_weight,
    evt_block_time,
    ROW_NUMBER() OVER (PARTITION BY voter ORDER BY evt_block_time DESC) AS rn
  FROM aerodrome_base.voter_evt_voted
  WHERE contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
    AND weight > 0
),
method_b_agg AS (
  SELECT
    pool,
    SUM(vote_weight) AS total_votes,
    COUNT(DISTINCT voter) AS voter_count
  FROM method_b
  WHERE rn = 1
  GROUP BY pool
),

-- Get pool names
pool_names AS (
  SELECT
    id AS pool_address,
    token0_symbol || '/' || token1_symbol AS pool_name,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY block_date DESC) AS rn
  FROM aerodrome.tvl_daily
  WHERE blockchain = 'base'
)

-- Compare both methods
SELECT
  'Method A: Latest per user+pool' AS method,
  COALESCE(p.pool_name, CAST(a.pool AS VARCHAR)) AS pool_name,
  a.pool,
  a.total_votes,
  a.voter_count
FROM method_a_agg a
LEFT JOIN pool_names p ON a.pool = p.pool_address AND p.rn = 1
ORDER BY a.total_votes DESC
LIMIT 20

UNION ALL

SELECT
  'Method B: Latest per user only' AS method,
  COALESCE(p.pool_name, CAST(b.pool AS VARCHAR)) AS pool_name,
  b.pool,
  b.total_votes,
  b.voter_count
FROM method_b_agg b
LEFT JOIN pool_names p ON b.pool = p.pool_address AND p.rn = 1
ORDER BY b.total_votes DESC
LIMIT 20;
