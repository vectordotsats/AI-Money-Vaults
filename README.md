# AI Money Vaults

A DeFi protocol where AI agents manage deposited funds to earn yield for their owners. Built from scratch on Sepolia testnet.

**Live demo:** [ai-money-vault.netlify.app](https://ai-money-vault.netlify.app)

---

## What is this?

Users deposit USDC into an ERC-4626 vault and receive `aiVLT` shares in return. Instead of funds sitting idle, the protocol actively deploys capital to generate yield through two paths:

1. **Lending yield** — Idle USDC gets supplied to Aave V3 (and later Morpho), earning borrow rates from borrowers on those platforms.
2. **Flash loan fees** — AI agents take flash loans from the vault to execute arbitrage trades. The fees they pay come back to the vault as additional yield for depositors.

Agents can also deposit their own profits into the vault to earn yield from path 1 — creating a flywheel.

---

## How it works

The architecture is hybrid — smart contracts on-chain, AI agents off-chain.

Solidity can't process market data or make intelligent decisions. And giving a bot direct access to user funds is a security risk. So the split is simple: contracts hold the money and enforce the rules, agents read the market and decide when to act. Every action goes through the contract's guardrails first.

```
Depositors (USDC in, aiVLT out)
        │
   AI Vault (ERC-4626)
        │
  AaveV3Strategy ──────── Flash Loan Module
   │         │                    │
Aave V3   Morpho              DEXs (arb)
                                  │
              ─── on-chain ───────┼──────────
                                  │
              Keeper Bot (TypeScript)
                reads market data
                triggers rebalancing
```

---

## What's been built

### Contracts (Solidity / Foundry)

- **AI Vault** — ERC-4626 vault. Deposit USDC, receive aiVLT shares, withdraw anytime.
- **AaveV3Strategy** — Supplies idle USDC to Aave V3 on Sepolia to earn lending yield. Dual access control (`onlyKeeper` for deploying capital, `onlyVault` for pulling it back). 90% max deployment guardrail so there's always idle USDC for withdrawals.

### Frontend (Next.js / TypeScript)

- Wallet connection via RainbowKit
- Deposit and withdraw with two-step approval flow
- Live vault stats (TVL, your shares)
- Transaction feedback with toast notifications

### Security decisions

These aren't theoretical — each one was caught and addressed during the build:

- **No `balanceOf()` for accounting** — Uses tracked state variables (`totalDepositedInContract`, `totalDeployed`) to prevent donation-based manipulation attacks.
- **CEI pattern everywhere** — State updates happen after external calls succeed, never before.
- **Emergency withdraw goes to vault, not owner** — Owner can't intercept funds. No rug path.
- **Withdrawals can never be paused** — Users always have an exit, even during emergencies.
- **Scoped access control** — Keeper can only deploy capital within guardrails. Vault can only pull funds back. Owner handles admin. No single role can do everything.

---

## What's next

- [ ] Vault V2 — Strategy routing (connect vault ↔ strategy)
- [ ] Keeper bot — TypeScript service that monitors Aave rates and triggers rebalancing
- [ ] Flash loan module — Let AI agents take flash loans for arb execution
- [ ] Morpho integration — Second lending yield source
- [ ] Frontend V2 — Display strategy stats (allocation %, accrued yield)

---

## Tech stack

| Layer | Stack |
|-------|-------|
| Contracts | Solidity, Foundry, OpenZeppelin |
| Frontend | Next.js, TypeScript, wagmi, viem, RainbowKit, Tailwind |
| Keeper (planned) | TypeScript, viem |
| Network | Ethereum Sepolia testnet |

---

## Contract addresses (Sepolia)

| Contract | Address |
|----------|---------|
| AI Vault | `0x2a3584548D96E6807Ca4884Cb8CA98f69d0Ca7ca` |
| Mock USDC | `0x94E60fBd4a1a40402F70B67d79c89c3E3BdE8620` |
| Aave V3 Pool | `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951` |
| Aave USDC | `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8` |
| aUSDC | `0x16dA4541aD1807f4443d92D26044C1147406EB80` |

---

## Run locally

**Frontend:**

```bash
cd ai-vault-app
npm install
npm run dev
```

**Contracts:**

```bash
cd foundry
forge install
forge build
forge test
```

---

## Author

Built by [@0xvector_](https://x.com/0xvector_)

Building in public — follow along for updates on the keeper bot, flash loan module, and Morpho integration.
