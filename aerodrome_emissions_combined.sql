-- Dune Analytics Query: Aerodrome AERO Emissions with Investment Calculator
-- Combines emissions calculation with TVL, APR, and reward projections
-- Fixed voting logic: properly aggregates votes from ALL users per pool

-- ============================================================================
-- VOTING EXPLANATION:
-- Each user can vote for multiple pools with different weights
-- Each pool receives votes from multiple users
-- To calculate pool's share:
--   1. Sum all users' votes for Pool A = Pool A Total Votes
--   2. Sum all pool votes across all pools = Total Votes
--   3. Pool A Vote % = (Pool A Total Votes / Total Votes) * 100
--   4. Pool A Emissions = Pool A Vote % * Total Weekly Emissions
-- ============================================================================

WITH params AS (
  -- PARAMETER: Set your investment budget here (or use Dune parameter)
  SELECT {{Budget Investment}} AS investment_usd
),

-- Get latest epoch start time from most recent mint event
latest_mint AS (
  SELECT
    evt_block_time AS mint_time,
    _weekly / 1e18 AS total_weekly_emissions
  FROM aerodrome_base.minter_evt_mint
  ORDER BY evt_block_time DESC
  LIMIT 1
),

-- Calculate current epoch window (Thursday 00:00 UTC to next Thursday 00:00 UTC)
current_epoch AS (
  SELECT
    -- Align to Thursday by subtracting 3 days, truncating to week, then adding 3 days back
    DATE_TRUNC('week', mint_time - INTERVAL '3' day) + INTERVAL '3' day AS epoch_start,
    DATE_TRUNC('week', mint_time - INTERVAL '3' day) + INTERVAL '10' day AS epoch_end,
    total_weekly_emissions
  FROM latest_mint
),

-- Get all votes from the Voter contract within current epoch
votes_in_epoch AS (
  SELECT
    voter AS user_address,
    pool,
    weight / 1e18 AS vote_weight,  -- Convert from wei
    evt_block_time,
    evt_tx_hash
  FROM aerodrome_base.voter_evt_voted
  CROSS JOIN current_epoch
  WHERE evt_block_time >= current_epoch.epoch_start
    AND evt_block_time < current_epoch.epoch_end
),

-- For each USER + POOL combination, keep only their MOST RECENT vote
-- This handles re-votes (later vote overrides earlier vote)
latest_user_votes AS (
  SELECT
    user_address,
    pool,
    vote_weight,
    evt_block_time,
    ROW_NUMBER() OVER (
      PARTITION BY user_address, pool
      ORDER BY evt_block_time DESC, evt_tx_hash DESC
    ) AS rn
  FROM votes_in_epoch
),

-- Sum votes per pool across ALL users (this is the key aggregation)
-- This gives each pool's total voting weight
pool_vote_totals AS (
  SELECT
    pool,
    SUM(vote_weight) AS pool_total_votes,
    COUNT(DISTINCT user_address) AS unique_voters
  FROM latest_user_votes
  WHERE rn = 1  -- Only most recent vote per user per pool
  GROUP BY pool
),

-- Calculate total votes across ALL pools for percentage calculation
all_pools_vote_sum AS (
  SELECT
    pool,
    pool_total_votes,
    unique_voters,
    SUM(pool_total_votes) OVER () AS total_votes_all_pools
  FROM pool_vote_totals
),

-- Get latest TVL data for each pool
latest_pools_tvl AS (
  SELECT
    id AS pool_address,
    token0_symbol || '/' || token1_symbol AS pool_name,
    token0_balance_usd + token1_balance_usd AS pool_tvl_usd,
    block_date,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY block_date DESC) AS rn
  FROM aerodrome.tvl_daily
  WHERE blockchain = 'base'
    AND block_date >= CURRENT_DATE - INTERVAL '7' DAY
    AND (token0_balance_usd + token1_balance_usd) > 10000  -- Filter small pools
),

pools_with_tvl AS (
  SELECT
    pool_address,
    pool_name,
    pool_tvl_usd
  FROM latest_pools_tvl
  WHERE rn = 1
),

-- Get latest AERO price
aero_price_latest AS (
  SELECT COALESCE(price, 0.5) AS aero_price_usd
  FROM prices.usd
  WHERE blockchain = 'base'
    AND contract_address = 0x940181a94a35a4569e4529a3cdfb74e38fd98631
    AND minute >= NOW() - INTERVAL '24' HOUR
  ORDER BY minute DESC
  LIMIT 1
),

-- Combine all data and calculate metrics
pool_metrics AS (
  SELECT
    -- Pool identifiers
    t.pool_address,
    t.pool_name,

    -- TVL metrics
    t.pool_tvl_usd,

    -- Voting metrics
    COALESCE(v.pool_total_votes, 0) AS pool_votes,
    COALESCE(v.unique_voters, 0) AS unique_voters,
    COALESCE(v.total_votes_all_pools, 1) AS total_votes_epoch,  -- Fallback to 1 to avoid division by zero

    -- Vote percentage (THIS IS THE KEY CALCULATION)
    COALESCE((v.pool_total_votes / NULLIF(v.total_votes_all_pools, 0)) * 100, 0) AS vote_percentage,

    -- Emissions metrics
    e.total_weekly_emissions,
    COALESCE((v.pool_total_votes / NULLIF(v.total_votes_all_pools, 0)), 0) * e.total_weekly_emissions AS pool_weekly_emissions_aero,

    -- AERO price
    a.aero_price_usd,

    -- Investment parameters
    p.investment_usd,

    -- LP share of pool (what % of the pool would your investment represent)
    (p.investment_usd / NULLIF(t.pool_tvl_usd, 0)) * 100 AS lp_share_percentage,

    -- Your estimated weekly rewards
    (p.investment_usd / NULLIF(t.pool_tvl_usd, 0)) *
      COALESCE((v.pool_total_votes / NULLIF(v.total_votes_all_pools, 0)), 0) *
      e.total_weekly_emissions AS weekly_aero_reward,

    (p.investment_usd / NULLIF(t.pool_tvl_usd, 0)) *
      COALESCE((v.pool_total_votes / NULLIF(v.total_votes_all_pools, 0)), 0) *
      e.total_weekly_emissions * a.aero_price_usd AS weekly_reward_usd,

    -- Epoch info
    e.epoch_start,
    e.epoch_end
  FROM pools_with_tvl t
  LEFT JOIN all_pools_vote_sum v ON t.pool_address = v.pool
  CROSS JOIN current_epoch e
  CROSS JOIN aero_price_latest a
  CROSS JOIN params p
)

-- Final output with all metrics
SELECT
  pool_address AS "Pool Address",
  pool_name AS "Pool Name",
  pool_tvl_usd AS "TVL (USD)",

  -- Voting details
  pool_votes AS "Pool Total Votes",
  unique_voters AS "Unique Voters",
  total_votes_epoch AS "Total Votes (All Pools)",
  ROUND(vote_percentage, 4) AS "Vote Share (%)",

  -- Emissions
  ROUND(pool_weekly_emissions_aero, 2) AS "Pool Emissions/Week (AERO)",

  -- Investment analysis
  investment_usd AS "Your Investment (USD)",
  ROUND(lp_share_percentage, 4) AS "Your LP Share (%)",
  ROUND(weekly_aero_reward, 4) AS "Your Weekly Rewards (AERO)",
  ROUND(weekly_reward_usd, 2) AS "Your Weekly Rewards (USD)",

  -- APR calculation (annualized)
  ROUND((weekly_reward_usd * 52 / NULLIF(investment_usd, 0)) * 100, 2) AS "Emissions APR (%)",

  -- Reference data
  ROUND(aero_price_usd, 4) AS "AERO Price (USD)",
  ROUND(total_weekly_emissions, 2) AS "Total Epoch Emissions (AERO)",

  -- Epoch window
  DATE_FORMAT(epoch_start, '%Y-%m-%d %H:%i UTC') AS "Epoch Start",
  DATE_FORMAT(epoch_end, '%Y-%m-%d %H:%i UTC') AS "Epoch End"

FROM pool_metrics
WHERE vote_percentage > 0  -- Only show pools with active votes
ORDER BY vote_percentage DESC
LIMIT 100;
