-- FOCUSED DIAGNOSTIC: Find SUMR/USDC pool and trace its votes
-- According to aerodrome.finance/vote, SUMR/USDC should be top pool

-- Step 1: Find SUMR/USDC pool address
WITH sumr_pool AS (
  SELECT
    id AS pool_address,
    token0_symbol,
    token1_symbol,
    token0_symbol || '/' || token1_symbol AS pool_name
  FROM aerodrome.tvl_daily
  WHERE blockchain = 'base'
    AND (
      (token0_symbol = 'SUMR' AND token1_symbol = 'USDC') OR
      (token0_symbol = 'USDC' AND token1_symbol = 'SUMR')
    )
  GROUP BY id, token0_symbol, token1_symbol
),

-- Step 2: Get all votes for SUMR/USDC pool
sumr_votes AS (
  SELECT
    v.voter,
    v.pool,
    v.weight / 1e18 AS vote_weight,
    v.evt_block_time,
    v.contract_address,
    s.pool_name
  FROM aerodrome_base.voter_evt_voted v
  INNER JOIN sumr_pool s ON v.pool = s.pool_address
  WHERE v.contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
  ORDER BY v.evt_block_time DESC
),

-- Step 3: Also check WETH/msETH (which shows as top in our query)
weth_pool AS (
  SELECT
    id AS pool_address,
    token0_symbol,
    token1_symbol,
    token0_symbol || '/' || token1_symbol AS pool_name
  FROM aerodrome.tvl_daily
  WHERE blockchain = 'base'
    AND (
      (token0_symbol LIKE '%ETH%' AND token1_symbol LIKE '%ETH%') OR
      (token0_symbol = 'WETH' AND token1_symbol = 'msETH') OR
      (token0_symbol = 'msETH' AND token1_symbol = 'WETH')
    )
  GROUP BY id, token0_symbol, token1_symbol
),

weth_votes AS (
  SELECT
    v.voter,
    v.pool,
    v.weight / 1e18 AS vote_weight,
    v.evt_block_time,
    v.contract_address,
    w.pool_name
  FROM aerodrome_base.voter_evt_voted v
  INNER JOIN weth_pool w ON v.pool = w.pool_address
  WHERE v.contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
  ORDER BY v.evt_block_time DESC
)

-- Output comparison
SELECT
  'SUMR/USDC Votes' AS pool_type,
  pool_name,
  pool AS pool_address,
  COUNT(*) AS total_vote_events,
  COUNT(DISTINCT voter) AS unique_voters,
  SUM(vote_weight) AS sum_all_weights,
  MAX(evt_block_time) AS latest_vote_time
FROM sumr_votes
GROUP BY pool_name, pool

UNION ALL

SELECT
  'WETH/msETH Votes' AS pool_type,
  pool_name,
  pool AS pool_address,
  COUNT(*) AS total_vote_events,
  COUNT(DISTINCT voter) AS unique_voters,
  SUM(vote_weight) AS sum_all_weights,
  MAX(evt_block_time) AS latest_vote_time
FROM weth_votes
GROUP BY pool_name, pool;

-- Also show sample recent votes for each
SELECT 'SUMR/USDC Recent Votes' AS info, * FROM sumr_votes LIMIT 10
UNION ALL
SELECT 'WETH/msETH Recent Votes' AS info, * FROM weth_votes LIMIT 10;
