// On-chain ABIs the keeper needs. Kept minimal: only the functions/errors
// the bot, wiring script, and e2e test actually call. `as const` lets viem
// infer argument and return types at compile time.

export const VAULT_ABI = [
  // ── reads ──
  { inputs: [], name: "asset", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "totalAssets", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "totalIdleDeposits", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "allTimeDeposits", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "idleBalance", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "strategy", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "keeper", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "owner", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "totalSupply", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "decimals", outputs: [{ type: "uint8" }], stateMutability: "view", type: "function" },
  { inputs: [{ type: "address" }], name: "balanceOf", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [{ type: "uint256" }], name: "convertToAssets", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [{ type: "address" }], name: "maxWithdraw", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  // ── writes ──
  {
    inputs: [
      { name: "amount", type: "uint256" },
      { name: "receiver", type: "address" },
    ],
    name: "deposit",
    outputs: [{ name: "shares", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "assets", type: "uint256" },
      { name: "receiver", type: "address" },
      { name: "owner", type: "address" },
    ],
    name: "withdraw",
    outputs: [{ name: "shares", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  { inputs: [{ name: "amount", type: "uint256" }], name: "depositToStrategy", outputs: [], stateMutability: "nonpayable", type: "function" },
  { inputs: [{ name: "_strategy", type: "address" }], name: "setStrategy", outputs: [], stateMutability: "nonpayable", type: "function" },
  { inputs: [{ name: "_keeper", type: "address" }], name: "setKeeper", outputs: [], stateMutability: "nonpayable", type: "function" },
  // ── custom errors (so viem can decode revert reasons) ──
  { inputs: [], name: "ZeroAddress", type: "error" },
  { inputs: [], name: "ZeroAmount", type: "error" },
  { inputs: [], name: "NotKeeper", type: "error" },
  { inputs: [], name: "NoStrategySet", type: "error" },
  { inputs: [], name: "InsufficientIdleBalance", type: "error" },
  { inputs: [{ name: "account", type: "address" }], name: "OwnableUnauthorizedAccount", type: "error" },
] as const;

export const STRATEGY_ABI = [
  // ── reads ──
  { inputs: [], name: "totalStrategyAssets", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "totalDeployed", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "totalDepositedInContract", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "accruedYield", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "idleBalanceInVault", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "maxSupplyPercentage", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "paused", outputs: [{ type: "bool" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "vault", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "keeper", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "owner", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  // ── writes ──
  { inputs: [{ name: "amount", type: "uint256" }], name: "supplyToAave", outputs: [], stateMutability: "nonpayable", type: "function" },
  { inputs: [{ name: "_newVault", type: "address" }], name: "updateVault", outputs: [], stateMutability: "nonpayable", type: "function" },
  { inputs: [{ name: "_newKeeper", type: "address" }], name: "updateKeeper", outputs: [], stateMutability: "nonpayable", type: "function" },
  // ── custom errors ──
  { inputs: [], name: "NotKeeper", type: "error" },
  { inputs: [], name: "NotVault", type: "error" },
  { inputs: [], name: "IsPaused", type: "error" },
  { inputs: [], name: "ZeroAmount", type: "error" },
  { inputs: [], name: "ZeroAddress", type: "error" },
  { inputs: [], name: "ExceedsMaxSupply", type: "error" },
  { inputs: [], name: "InsufficientBalance", type: "error" },
  { inputs: [{ name: "account", type: "address" }], name: "OwnableUnauthorizedAccount", type: "error" },
] as const;

export const ERC20_ABI = [
  { inputs: [{ type: "address" }], name: "balanceOf", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "decimals", outputs: [{ type: "uint8" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "symbol", outputs: [{ type: "string" }], stateMutability: "view", type: "function" },
  {
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    name: "allowance",
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;
