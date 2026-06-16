# Axis Keeper Bot

The autonomous brain of the Axis protocol. Without it, deposited USDC sits idle in
the vault earning nothing. With it, Axis becomes self-managing: the bot watches the
vault, pushes idle capital into the AaveV3 strategy, and supplies it to Aave so it
earns yield — 24/7, on a schedule, with guardrails.

```
USDC in vault ──depositToStrategy()──▶ strategy ──supplyToAave()──▶ Aave (earning)
        ▲                                                                  │
        └──────────────── withdraw() auto-pulls back ─────────────────────┘
```

## What each cycle does (default: every 5 minutes)

1. Reads the on-chain snapshot: vault idle USDC, total assets, strategy deployed /
   idle, accrued yield, allocation %, pause state.
2. If vault idle ≥ `IDLE_THRESHOLD_USDC`, calls `depositToStrategy()` to move idle
   USDC into the strategy (keeping `IDLE_RESERVE_USDC` back as a buffer).
3. Calls `supplyToAave()` for as much as the strategy's `maxSupplyPercentage`
   guardrail allows, so the capital actually earns. (The bot computes the supply
   amount to never trip `ExceedsMaxSupply`.)
4. Logs everything to the console and appends a record to `data/history.json`.

Every transaction is `simulate`d first, so reverts (with decoded custom errors like
`NotKeeper` / `ExceedsMaxSupply`) surface before any gas is spent. A failed cycle is
caught and logged — it never kills the scheduler.

## Stack

TypeScript · [viem](https://viem.sh) · [node-cron](https://github.com/node-cron/node-cron) · Node 20+

## Quick start

```bash
cd keeper-bot
npm install
cp .env.example .env        # fill in RPC_URL and PRIVATE_KEY

npm run typecheck           # compile-check, no chain calls
npm run dry-run             # one read-only cycle: logs decisions, sends nothing
npm run once                # one real cycle (needs a funded keeper)
npm run start               # scheduled loop (this is what runs in production)
```

### Defaults

Contract addresses default to the live Sepolia deployment (see
`../ai-vault-app/app/constants/addresses.tsx`), so you only strictly need `RPC_URL`
(and `PRIVATE_KEY` for writes). Override any of them in `.env`.

## Before the bot can act: wiring + authorization

The keeper signer must be authorized on-chain, and the vault/strategy must point at
each other. Check it:

```bash
npm run wiring        # read-only report: PASS/FAIL for each link
npm run wiring:fix    # fixes mismatches (signer must be the contract OWNER)
```

`wiring:fix` will, as needed:

- `vault.setStrategy(STRATEGY_ADDRESS)`
- `strategy.updateVault(VAULT_ADDRESS)`  ← **fixes the known mismatch** (the strategy
  was deployed pointing at the old V2 vault `0x2a35…a7ca` instead of the live
  `0x88fb…030c`)
- `vault.setKeeper(signer)` and `strategy.updateKeeper(signer)`

> The bot's startup preflight also warns loudly if the signer can't push or supply,
> so you'll know immediately if wiring is off.

## End-to-end test (run this before trusting the loop)

Proves the whole loop on-chain: deposit → depositToStrategy → supplyToAave →
(optional wait) → withdraw, asserting balances/shares/yield at each step.

```bash
# small amount, no wait
RPC_URL=... PRIVATE_KEY=... npm run e2e

# measure ~1 hour of real yield
E2E_AMOUNT_USDC=25 E2E_WAIT_SECONDS=3600 npm run e2e
```

It refuses to send value if preconditions (USDC balance, authorization, wiring)
aren't met. **Sends real transactions and spends gas — testnet only.**

## Configuration

| Env var | Default | Meaning |
|---|---|---|
| `RPC_URL` | — (required) | JSON-RPC endpoint |
| `PRIVATE_KEY` | — | Keeper signer; omit for read-only / `DRY_RUN` |
| `CHAIN_ID` | `11155111` | Network (Sepolia) |
| `VAULT_ADDRESS` / `STRATEGY_ADDRESS` / `USDC_ADDRESS` | live Sepolia | Contracts |
| `CRON_SCHEDULE` | `*/5 * * * *` | Loop cadence |
| `IDLE_THRESHOLD_USDC` | `100` | Min vault idle before pushing to strategy |
| `IDLE_RESERVE_USDC` | `0` | Idle USDC kept in vault as buffer |
| `MIN_SUPPLY_USDC` | `1` | Don't supply to Aave below this |
| `DRY_RUN` | `false` | Simulate only, send no txns |
| `HISTORY_FILE` | `data/history.json` | Where cycle history is written |
| `HISTORY_MAX_RECORDS` | `5000` | Trim history to this many records |

## Deploy (runs 24/7)

Both targets are pre-configured. Set `RPC_URL` and `PRIVATE_KEY` as **secrets** in the
platform dashboard — never commit them.

**Railway** — `railway.json` builds from the `Dockerfile` and restarts on failure.
Point a new Railway service at this repo (root `keeper-bot/`), add the env vars, deploy.

**Render** — `render.yaml` defines a Docker **worker** (no public port) with a 1 GB
persistent disk mounted at `/app/data` so history survives restarts. New → Blueprint →
pick this repo → add the secret env vars.

Either way the process is `npm run start`, which runs the cron loop and an immediate
first cycle on boot.

## History format

`data/history.json` is an array of per-cycle records:

```json
{
  "ts": "2026-06-15T12:00:00.000Z",
  "cycle": 42,
  "vaultIdleUsdc": "0.0",
  "vaultTotalAssetsUsdc": "150.02",
  "strategyDeployedUsdc": "150.0",
  "strategyIdleUsdc": "0.0",
  "accruedYieldUsdc": "0.021",
  "allocationPct": 99.98,
  "paused": false,
  "pushedToStrategyUsdc": "120.0",
  "suppliedToAaveUsdc": "120.0",
  "txHashes": ["0x…", "0x…"],
  "dryRun": false
}
```

## Safety notes

- The bot only ever *deploys* capital and *monitors*. It never withdraws to an
  external address; withdrawals are user-driven through the vault.
- All writes are simulated before sending.
- Respects the strategy's `paused` flag and `maxSupplyPercentage` guardrail.
- Keep the keeper wallet funded with gas; it only needs the keeper role, not owner.
