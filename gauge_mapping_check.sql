-- THEORY: Voting is on GAUGES, not POOLS directly
-- Need to map Gauge -> Pool to get correct results

-- Step 1: Check if there are Gauge creation/deployment events
-- This would tell us the gauge -> pool mapping

-- Try to find gauge factory or gauge creation events
WITH gauge_created AS (
  SELECT
    pool,
    gauge,
    evt_block_time,
    contract_address
  FROM aerodrome_base.voter_evt_gaugecreated
  ORDER BY evt_block_time DESC
  LIMIT 100
),

-- Step 2: From your vote transaction, get the "pool" address (might be gauge)
your_vote AS (
  SELECT
    pool AS voted_address,  -- This might actually be a gauge address
    voter,
    weight / 1e18 AS vote_weight,
    evt_block_time
  FROM aerodrome_base.voter_evt_voted
  WHERE evt_tx_hash = 0x89f179ee4bdbc112fd2388bb54d3aa64139522d4c05284908d7ecb077f36e0a1
),

-- Step 3: Try to map gauge to pool
gauge_to_pool AS (
  SELECT
    gc.gauge,
    gc.pool,
    yv.voter,
    yv.vote_weight,
    yv.evt_block_time AS vote_time,
    gc.evt_block_time AS gauge_created_time
  FROM gauge_created gc
  INNER JOIN your_vote yv ON gc.gauge = yv.voted_address
)

-- Output results
SELECT
  'Your Vote Mapped' AS info,
  voter,
  gauge AS gauge_address,
  pool AS actual_pool_address,
  vote_weight,
  vote_time
FROM gauge_to_pool

UNION ALL

SELECT
  'All Recent Gauges' AS info,
  NULL AS voter,
  gauge,
  pool,
  NULL AS vote_weight,
  evt_block_time
FROM gauge_created
ORDER BY info, evt_block_time DESC
LIMIT 50;
