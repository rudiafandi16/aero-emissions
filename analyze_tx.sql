-- ANALYZE ACTUAL VOTE TRANSACTION
-- TX: 0x89f179ee4bdbc112fd2388bb54d3aa64139522d4c05284908d7ecb077f36e0a1
-- User voted for FUN/USDC pool

-- Step 1: Get the Voted event from this transaction
SELECT
  'Voted Event' AS event_type,
  voter,
  pool,
  weight,
  weight / 1e18 AS weight_decimal,
  evt_block_time,
  evt_block_number,
  contract_address AS voter_contract,
  evt_tx_hash
FROM aerodrome_base.voter_evt_voted
WHERE evt_tx_hash = 0x89f179ee4bdbc112fd2388bb54d3aa64139522d4c05284908d7ecb077f36e0a1;

-- Step 2: Check if there are other voting-related events in this tx
-- Try to find GaugeVoted or other gauge events
SELECT
  'Transaction Details' AS info,
  block_time,
  block_number,
  "from" AS tx_from,
  "to" AS tx_to,
  success,
  gas_used
FROM base.transactions
WHERE hash = 0x89f179ee4bdbc112fd2388bb54d3aa64139522d4c05284908d7ecb077f36e0a1;

-- Step 3: Get ALL events from this transaction to understand full flow
SELECT
  'All Events in TX' AS info,
  contract_address,
  topic0,  -- Event signature
  topic1,
  topic2,
  topic3,
  data,
  block_time
FROM base.logs
WHERE tx_hash = 0x89f179ee4bdbc112fd2388bb54d3aa64139522d4c05284908d7ecb077f36e0a1
ORDER BY log_index;

-- Step 4: Find the FUN/USDC pool address
SELECT
  'FUN/USDC Pool' AS info,
  id AS pool_address,
  token0_symbol || '/' || token1_symbol AS pool_name,
  block_date
FROM aerodrome.tvl_daily
WHERE blockchain = 'base'
  AND (
    (token0_symbol = 'FUN' AND token1_symbol = 'USDC') OR
    (token0_symbol = 'USDC' AND token1_symbol = 'FUN')
  )
GROUP BY id, token0_symbol, token1_symbol, block_date
ORDER BY block_date DESC
LIMIT 5;

-- Step 5: Check if the pool address from Voted event matches FUN/USDC
WITH tx_vote AS (
  SELECT
    pool AS voted_pool_address,
    voter,
    weight / 1e18 AS vote_weight
  FROM aerodrome_base.voter_evt_voted
  WHERE evt_tx_hash = 0x89f179ee4bdbc112fd2388bb54d3aa64139522d4c05284908d7ecb077f36e0a1
),
fun_pool AS (
  SELECT
    id AS pool_address,
    token0_symbol || '/' || token1_symbol AS pool_name
  FROM aerodrome.tvl_daily
  WHERE blockchain = 'base'
    AND (
      (token0_symbol = 'FUN' AND token1_symbol = 'USDC') OR
      (token0_symbol = 'USDC' AND token1_symbol = 'FUN')
    )
  GROUP BY id, token0_symbol, token1_symbol
)
SELECT
  'Vote Analysis' AS info,
  tx.voter,
  tx.voted_pool_address,
  fp.pool_name,
  tx.vote_weight,
  CASE
    WHEN tx.voted_pool_address = fp.pool_address THEN 'MATCH - Voted directly on pool'
    ELSE 'NO MATCH - Might be voting on gauge'
  END AS address_check
FROM tx_vote tx
CROSS JOIN fun_pool fp;
