-- Dune Analytics Query: Aerodrome AERO Token Emissions by Pool (Latest Epoch)
-- Calculates estimated AERO rewards for each pool based on voting weight
-- Epoch: Thursday 00:00 UTC to next Thursday 00:00 UTC

WITH current_epoch AS (
    -- Calculate the latest epoch window (Thursday to Thursday UTC)
    -- Subtract 3 days to align week start to Thursday, then add back
    SELECT
        DATE_TRUNC('week', CURRENT_TIMESTAMP AT TIME ZONE 'UTC' - INTERVAL '3' day) + INTERVAL '3' day AS epoch_start,
        DATE_TRUNC('week', CURRENT_TIMESTAMP AT TIME ZONE 'UTC' - INTERVAL '3' day) + INTERVAL '10' day AS epoch_end
),

votes_in_epoch AS (
    -- Get all votes from the Aerodrome Voter contract during the current epoch
    SELECT
        voter AS user_address,
        pool,
        weight,
        evt_block_time,
        evt_tx_hash
    FROM aerodrome_base.Voter_evt_Voted
    CROSS JOIN current_epoch
    WHERE contract_address = 0x16613524e02ad97edfef371bc883f2f5d6c480a5
        AND evt_block_time >= current_epoch.epoch_start
        AND evt_block_time < current_epoch.epoch_end
),

latest_votes_per_user_pool AS (
    -- For each user and pool combination, keep only their most recent vote
    -- Uses ROW_NUMBER to rank votes by timestamp descending
    SELECT
        user_address,
        pool,
        weight,
        evt_block_time,
        ROW_NUMBER() OVER (
            PARTITION BY user_address, pool
            ORDER BY evt_block_time DESC, evt_tx_hash DESC
        ) AS rn
    FROM votes_in_epoch
),

pool_vote_totals AS (
    -- Sum all users' latest votes per pool to get total votes
    SELECT
        pool,
        SUM(weight) AS total_votes,
        COUNT(DISTINCT user_address) AS unique_voters
    FROM latest_votes_per_user_pool
    WHERE rn = 1  -- Only the most recent vote per user per pool
    GROUP BY pool
),

all_votes_sum AS (
    -- Calculate the sum of votes across all pools
    SELECT SUM(total_votes) AS sum_all_pool_votes
    FROM pool_vote_totals
),

weekly_emissions AS (
    -- Get the latest weekly emissions from the Minter contract
    -- Divide by 1e18 to convert from wei to AERO tokens
    SELECT
        CAST(_weekly AS DOUBLE) / 1e18 AS total_weekly_emissions,
        evt_block_time
    FROM aerodrome_base.minter_evt_mint
    ORDER BY evt_block_time DESC
    LIMIT 1
)

-- Final output: Calculate each pool's share of emissions
SELECT
    pt.pool AS pool_address,
    pt.total_votes AS votes,
    pt.unique_voters,
    ROUND(100.0 * pt.total_votes / av.sum_all_pool_votes, 4) AS vote_percentage,
    ROUND(
        (CAST(pt.total_votes AS DOUBLE) / CAST(av.sum_all_pool_votes AS DOUBLE)) * we.total_weekly_emissions,
        2
    ) AS emissions_allocation
FROM pool_vote_totals pt
CROSS JOIN all_votes_sum av
CROSS JOIN weekly_emissions we
WHERE av.sum_all_pool_votes > 0  -- Avoid division by zero
ORDER BY pt.total_votes DESC
LIMIT 100;
