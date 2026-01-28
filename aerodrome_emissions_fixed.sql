-- Dune Analytics Query: Aerodrome AERO Emissions Calculator (CORRECTED)
-- Fixed: Votes persist across epochs - we need ALL active votes, not just epoch votes

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

-- Get ALL votes (not filtered by epoch) - votes persist until changed
all_user_votes AS (
  SELECT
    voter AS user_address,
    pool AS pool_address,
    weight / 1e18 AS vote_weight,
    evt_block_time,
    evt_tx_hash,
    ROW_NUMBER() OVER (
      PARTITION BY voter, pool
      ORDER BY evt_block_time DESC, evt_tx_hash DESC
    ) AS rn
  FROM aerodrome_base.voter_evt_voted
  WHERE contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
    AND weight > 0  -- Exclude zero-weight votes (vote removals)
),

-- Keep only the most recent vote per user per pool
latest_active_votes AS (
  SELECT
    user_address,
    pool_address,
    vote_weight
  FROM all_user_votes
  WHERE rn = 1
),

-- Aggregate votes per pool
pool_vote_totals AS (
  SELECT
    pool_address,
    SUM(vote_weight) AS total_pool_votes,
    COUNT(DISTINCT user_address) AS unique_voters
  FROM latest_active_votes
  GROUP BY pool_address
),

-- Calculate total votes and percentages
pool_vote_summary AS (
  SELECT
    pool_address,
    total_pool_votes,
    unique_voters,
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
