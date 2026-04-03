- Here's your remaining build checklist:
  Contracts (Solidity)

* Vault V2 upgrade — add strategy routing so the vault can send idle USDC to the strategy and pull it back for withdrawals. Also need to switch from 18-decimal MockUSDC to Aave's 6-decimal Sepolia USDC
* Flash loan module — the contract that lets AI agents take flash loans from the vault and return principal + fee
* Morpho integration — second lending strategy (after Aave is fully working)

* Keeper Bot (TypeScript)
* Market monitor — reads Aave supply rates, detects when to rebalance
* Execution layer — calls supplyToAave() and rebalance() on the strategy contract via viem
* Decision logic — when to supply more, when to pull back, threshold triggers
  Frontend
* Remove "Time in Vault" stat from UI
* Add strategy stats — show how much is deployed to Aave, accrued yield, current allocation %
* Display the two yield sources (lending yield + flash loan fees)
  Testing
* Foundry tests for AaveV3Strategy — test access control, guardrails, emergency flow
* Integration tests — vault ↔ strategy interaction on Sepolia fork

Next step is the Vault V2 upgrade — that's the bridge between what you've already deployed and the strategy contract we just wrote. Without it, the two contracts can't talk to each other.
