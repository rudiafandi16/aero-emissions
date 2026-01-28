-- CHECK FOR GAUGE SYSTEM
-- Theory: Voting might be on gauges, not pools directly

-- List all available Aerodrome tables
SELECT
  'Available Aerodrome Base Tables' AS info,
  table_schema,
  table_name
FROM information_schema.tables
WHERE table_schema LIKE '%aerodrome%'
ORDER BY table_schema, table_name;

-- Check if there are gauge-related events
-- Try to find gauge creation or gauge voting events
SELECT
  'Voter Events Available' AS info,
  table_name
FROM information_schema.tables
WHERE table_schema = 'aerodrome_base'
  AND table_name LIKE '%voter%'
ORDER BY table_name;

-- Alternative: Maybe votes are in a different contract?
-- Check all contracts in voter_evt_voted
SELECT
  'All Voter Contract Addresses' AS info,
  contract_address,
  COUNT(*) AS event_count,
  MIN(evt_block_time) AS first_seen,
  MAX(evt_block_time) AS last_seen,
  COUNT(DISTINCT voter) AS unique_voters,
  COUNT(DISTINCT pool) AS unique_pools
FROM aerodrome_base.voter_evt_voted
GROUP BY contract_address
ORDER BY last_seen DESC;
