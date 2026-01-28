# Aerodrome Emissions Calculator

Repository for developing Dune Analytics queries to calculate AERO token emissions for Aerodrome pools on Base.

## Status

All previous queries have been removed due to incorrect logic.

## Requirements

Calculate estimated AERO token reward emissions for each Aerodrome pool based on:
- Voter contract: `0x16613524e02ad97edfef371bc883f2f5d6c480a5` on Base
- Latest epoch voting data (Thursday 00:00 UTC to next Thursday 00:00 UTC)
- Total weekly emissions from `aerodrome_base.minter_evt_mint`
- Pool emissions = (pool_votes / total_votes) × total_weekly_emissions

## Output Required

Top 100 pools with:
- Pool address
- Pool name
- Total votes
- Vote percentage
- Emissions allocation (AERO)
- TVL
- APR calculations based on investment amount
