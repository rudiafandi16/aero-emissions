-- CORRECTED QUERY: Aerodrome Emissions with Gauge -> Pool Mapping
-- THEORY: Users vote on GAUGES, not pools directly
-- We need to map gauge addresses to pool addresses

WITH params AS (
  SELECT {{Budget Investment}} AS investment_usd
),

-- Get latest weekly emissions
latest_emissions AS (
  SELECT
    _weekly / 1e18 AS total_weekly_emissions,
    evt_block_time
  FROM aerodrome_base.minter_evt_mint
  ORDER BY evt_block_time DESC
  LIMIT 1
),

-- Get gauge -> pool mapping from GaugeCreated events
gauge_to_pool_map AS (
  SELECT
    gauge AS gauge_address,
    pool AS pool_address
  FROM aerodrome_base.voter_evt_gaugecreated
  WHERE contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
),

-- Get ALL votes (the "pool" field in Voted event is actually the gauge address)
all_user_votes_on_gauges AS (
  SELECT
    voter AS user_address,
    pool AS gauge_address,  -- This is actually a GAUGE address, not pool!
    weight / 1e18 AS vote_weight,
    evt_block_time,
    evt_tx_hash,
    ROW_NUMBER() OVER (
      PARTITION BY voter, pool
      ORDER BY evt_block_time DESC, evt_tx_hash DESC
    ) AS rn
  FROM aerodrome_base.voter_evt_voted
  WHERE contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
    AND weight > 0
),

-- Keep only latest vote per user per gauge
latest_votes_per_user_gauge AS (
  SELECT
    user_address,
    gauge_address,
    vote_weight
  FROM all_user_votes_on_gauges
  WHERE rn = 1
),

-- Map gauge votes to actual pools
votes_mapped_to_pools AS (
  SELECT
    v.user_address,
    v.gauge_address,
    g.pool_address,
    v.vote_weight
  FROM latest_votes_per_user_gauge v
  INNER JOIN gauge_to_pool_map g ON v.gauge_address = g.gauge_address
),

-- Aggregate votes by POOL (not gauge)
pool_vote_totals AS (
  SELECT
    pool_address,
    SUM(vote_weight) AS total_pool_votes,
    COUNT(DISTINCT user_address) AS unique_voters,
    COUNT(DISTINCT gauge_address) AS gauge_count
  FROM votes_mapped_to_pools
  GROUP BY pool_address
),

-- Calculate vote percentages
pool_vote_summary AS (
  SELECT
    pool_address,
    total_pool_votes,
    unique_voters,
    gauge_count,
    SUM(total_pool_votes) OVER () AS total_votes_all_pools,
    (total_pool_votes / SUM(total_pool_votes) OVER ()) * 100 AS vote_percentage
  FROM pool_vote_totals
),

-- Get latest TVL per pool
latest_tvl AS (
  SELECT
    id AS pool_address,
    token0_symbol || '/' || token1_symbol AS pool_name,
    token0_balance_usd + token1_balance_usd AS pool_tvl_usd,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY block_date DESC) AS rn
  FROM aerodrome.tvl_daily
  WHERE blockchain = 'base'
    AND block_date >= CURRENT_DATE - INTERVAL '7' DAY
    AND (token0_balance_usd + token1_balance_usd) > 10000
),

pools_with_tvl AS (
  SELECT
    pool_address,
    pool_name,
    pool_tvl_usd
  FROM latest_tvl
  WHERE rn = 1
),

-- Get AERO price
aero_price_current AS (
  SELECT COALESCE(price, 0.5) AS aero_price_usd
  FROM prices.usd
  WHERE blockchain = 'base'
    AND contract_address = 0x940181a94a35a4569e4529a3cdfb74e38fd98631
    AND minute >= NOW() - INTERVAL '24' HOUR
  ORDER BY minute DESC
  LIMIT 1
),

-- Calculate all metrics
final_metrics AS (
  SELECT
    -- Pool info
    t.pool_address,
    t.pool_name,
    t.pool_tvl_usd,

    -- Voting metrics
    COALESCE(v.total_pool_votes, 0) AS pool_votes,
    COALESCE(v.unique_voters, 0) AS unique_voters,
    COALESCE(v.gauge_count, 0) AS num_gauges,
    COALESCE(v.total_votes_all_pools, 0) AS total_votes,
    COALESCE(v.vote_percentage, 0) AS vote_percentage,

    -- Emissions
    e.total_weekly_emissions,
    (COALESCE(v.vote_percentage, 0) / 100) * e.total_weekly_emissions AS pool_weekly_emissions,

    -- Price
    a.aero_price_usd,

    -- Investment calculations
    p.investment_usd,
    (p.investment_usd / NULLIF(t.pool_tvl_usd, 0)) * 100 AS lp_share_pct,

    -- Your rewards
    (p.investment_usd / NULLIF(t.pool_tvl_usd, 0)) *
      (COALESCE(v.vote_percentage, 0) / 100) *
      e.total_weekly_emissions AS weekly_aero_reward,

    (p.investment_usd / NULLIF(t.pool_tvl_usd, 0)) *
      (COALESCE(v.vote_percentage, 0) / 100) *
      e.total_weekly_emissions * a.aero_price_usd AS weekly_usd_reward

  FROM pools_with_tvl t
  LEFT JOIN pool_vote_summary v ON t.pool_address = v.pool_address
  CROSS JOIN latest_emissions e
  CROSS JOIN aero_price_current a
  CROSS JOIN params p
)

-- Final output
SELECT
  pool_address AS "Pool Address",
  pool_name AS "Pool Name",
  pool_tvl_usd AS "TVL (USD)",

  -- Voting details
  pool_votes AS "Pool Votes",
  unique_voters AS "# Voters",
  num_gauges AS "# Gauges",
  total_votes AS "Total Votes",
  ROUND(vote_percentage, 4) AS "Vote Share (%)",

  -- Emissions
  ROUND(pool_weekly_emissions, 2) AS "Pool Emissions/Week (AERO)",

  -- Investment analysis
  investment_usd AS "Investment (USD)",
  ROUND(lp_share_pct, 4) AS "LP Share (%)",
  ROUND(weekly_aero_reward, 4) AS "Weekly Rewards (AERO)",
  ROUND(weekly_usd_reward, 2) AS "Weekly Rewards (USD)",
  ROUND((weekly_usd_reward * 52 / NULLIF(investment_usd, 0)) * 100, 2) AS "Emissions APR (%)",

  -- Reference
  ROUND(aero_price_usd, 4) AS "AERO Price (USD)",
  ROUND(total_weekly_emissions, 2) AS "Total Emissions (AERO)"

FROM final_metrics
WHERE vote_percentage > 0
ORDER BY vote_percentage DESC
LIMIT 100;
