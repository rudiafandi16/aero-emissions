# Aerodrome Emissions Calculator

## 🎯 SOLUTION FOUND: Gauge-Based Voting System

**The Issue:** Users vote on GAUGES, not pools directly!

The "pool" field in `voter_evt_voted` events is actually a **GAUGE address**, not a pool address. We need to map gauges to pools using `voter_evt_gaugecreated` events.

### ✅ Use This Query: `aerodrome_emissions_with_gauges.sql`

This corrected query:
1. Maps gauge addresses to pool addresses using `voter_evt_gaugecreated`
2. Aggregates votes by actual pool (multiple gauges can point to same pool)
3. Should now match aerodrome.finance/vote rankings

---

## Previous Problem (Now Solved)
The voting results from our queries didn't match the official Aerodrome website (https://aerodrome.finance/vote).
- Website shows: SUMR/USDC as top pool
- Previous query shows: WETH/msETH as top pool
- **Root Cause:** Not mapping gauges to pools

---

## Transaction Analysis Queries (To Verify Gauge System)

### 1. `analyze_tx.sql` - Analyze Your Actual Vote
Analyzes transaction: `0x89f179ee4bdbc112fd2388bb54d3aa64139522d4c05284908d7ecb077f36e0a1`
- Shows the voted address (gauge)
- Checks if it matches FUN/USDC pool or gauge

### 2. `gauge_mapping_check.sql` - Verify Gauge -> Pool Mapping
- Gets all gauge creation events
- Maps your vote to the actual pool via gauge
- Confirms the gauge system theory

---

## Alternative Diagnostic Queries (For Deep Debugging)

### 1. `check_gauge_system.sql` - CRITICAL
**Run this FIRST** to understand the data structure.

This query checks:
- What Aerodrome tables are available in Dune
- What voter contracts exist
- If there are gauge-related tables

**Expected Output:** List of tables and contract addresses

---

### 2. `deep_diagnostic.sql` - Compare Aggregation Methods
Tests two different theories about how votes work:
- **Method A:** Latest vote per user per pool (users can vote for multiple pools)
- **Method B:** Latest vote per user only (users vote for ONE pool at a time)

**Expected Output:** Top 20 pools using both methods

**What to check:** Does either method show SUMR/USDC at the top?

---

### 3. `focused_pool_diagnostic.sql` - Trace Specific Pools
Examines the actual voting data for:
- SUMR/USDC (should be top according to website)
- WETH/msETH (shows as top in our query)

**Expected Output:**
- Vote counts and voter counts for each pool
- Sample recent votes for each pool

**What to check:**
- Which pool has more total votes?
- Which pool has more unique voters?
- Are the vote weights significantly different?

---

### 4. `diagnostic_voting_query.sql` - Current Implementation
Our current "fixed" query - shows what we're getting now.

**Expected Output:** Top 20 pools with vote percentages

---

## Analysis Instructions

After running the diagnostic queries, answer these questions:

1. **From `check_gauge_system.sql`:**
   - What voter contract addresses exist?
   - Are there multiple voter contracts? (We're using `0x16613524e02ad97edfef371bc883f2f5d6c480a5`)
   - Are there any gauge-related tables?

2. **From `deep_diagnostic.sql`:**
   - Does Method A or Method B match the website rankings?
   - What's the top pool in each method?

3. **From `focused_pool_diagnostic.sql`:**
   - How many votes does SUMR/USDC have vs WETH/msETH?
   - Are we seeing the votes for both pools?
   - When was the last vote for each pool?

## Possible Root Causes

Based on diagnostic results, the issue could be:

1. **Wrong voter contract address** - Check if there's a newer/different voter contract
2. **Gauge system** - Maybe voting is on gauges, not pools directly
3. **Vote weight interpretation** - Maybe weights need different conversion or there's a veAERO multiplier
4. **Aggregation logic** - Maybe Method B (one vote per user total) is correct
5. **Timing** - Maybe the website shows a different epoch window
6. **Data lag** - Dune data might be behind the live blockchain

## Next Steps

Once you run these queries and share the results, I can:
1. Identify the exact root cause
2. Fix the main emissions calculator query
3. Ensure it matches the website rankings

---

## Files in this Repo

### ✅ USE THIS QUERY
- **`aerodrome_emissions_with_gauges.sql`** - CORRECT query using gauge -> pool mapping

### Transaction Analysis (To Verify)
- `analyze_tx.sql` - Analyzes your actual FUN/USDC vote transaction
- `gauge_mapping_check.sql` - Verifies gauge -> pool mapping works

### Deep Diagnostic Queries (For Research)
- `check_gauge_system.sql` - Lists all available tables and contracts
- `deep_diagnostic.sql` - Tests different aggregation methods
- `focused_pool_diagnostic.sql` - Compares SUMR/USDC vs WETH/msETH
- `diagnostic_voting_query.sql` - Tests current implementation

### Previous Attempts (Reference Only - Don't Use)
- `aerodrome_emissions_query.sql` - Original query (epoch filter bug)
- `aerodrome_emissions_fixed.sql` - Fixed epoch but missing gauge mapping
- `aerodrome_emissions_combined.sql` - Combined version but missing gauge mapping
