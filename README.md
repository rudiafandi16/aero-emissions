# Aerodrome Emissions Diagnostic Queries

## Problem
The voting results from our queries don't match the official Aerodrome website (https://aerodrome.finance/vote).
- Website shows: SUMR/USDC as top pool
- Our query shows: WETH/msETH as top pool

## Diagnostic Queries to Run (In Order)

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

### Main Queries (Use After Fix)
- `aerodrome_emissions_fixed.sql` - Full emissions calculator with investment analysis
- `aerodrome_emissions_combined.sql` - Alternative version with different structure

### Diagnostic Queries (For Debugging)
- `check_gauge_system.sql` - Check data structure
- `deep_diagnostic.sql` - Test aggregation methods
- `focused_pool_diagnostic.sql` - Trace specific pools
- `diagnostic_voting_query.sql` - Current implementation test

### Original Queries (Reference)
- `aerodrome_emissions_query.sql` - Original query (has epoch filter bug)
