import "dotenv/config";
import { type Address, getAddress, isAddress } from "viem";

// ── Defaults match the live Sepolia deployment (see ../ai-vault-app/app/constants/addresses.tsx) ──
const DEFAULTS = {
  VAULT_ADDRESS: "0x88fb46a354e4771f987c786bcacf026f0792030c",
  STRATEGY_ADDRESS: "0x635161055158b304740958811bc0d5d9999cdb57",
  USDC_ADDRESS: "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8",
  CHAIN_ID: 11155111, // Sepolia
} as const;

function required(name: string): string {
  const v = process.env[name];
  if (!v || v.trim() === "") {
    throw new Error(`Missing required env var: ${name}. See .env.example.`);
  }
  return v.trim();
}

function addr(name: string, fallback?: string): Address {
  const raw = (process.env[name] ?? fallback ?? "").trim();
  if (!isAddress(raw)) {
    throw new Error(`Env var ${name} is not a valid address: "${raw}"`);
  }
  return getAddress(raw); // checksummed
}

function num(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw.trim() === "") return fallback;
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) {
    throw new Error(`Env var ${name} must be a non-negative number, got "${raw}"`);
  }
  return n;
}

function bool(name: string, fallback = false): boolean {
  const raw = process.env[name];
  if (raw === undefined) return fallback;
  return ["1", "true", "yes", "on"].includes(raw.trim().toLowerCase());
}

// PRIVATE_KEY is only required for write operations. Read-only / dry-run mode
// can start without it, so we resolve it lazily and validate format if present.
function optionalPrivateKey(): `0x${string}` | undefined {
  const raw = process.env.PRIVATE_KEY?.trim();
  if (!raw) return undefined;
  const normalized = (raw.startsWith("0x") ? raw : `0x${raw}`) as `0x${string}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(normalized)) {
    throw new Error("PRIVATE_KEY must be a 32-byte hex string (64 hex chars, optional 0x prefix).");
  }
  return normalized;
}

export const config = {
  rpcUrl: required("RPC_URL"),
  chainId: num("CHAIN_ID", DEFAULTS.CHAIN_ID),

  vaultAddress: addr("VAULT_ADDRESS", DEFAULTS.VAULT_ADDRESS),
  strategyAddress: addr("STRATEGY_ADDRESS", DEFAULTS.STRATEGY_ADDRESS),
  usdcAddress: addr("USDC_ADDRESS", DEFAULTS.USDC_ADDRESS),

  privateKey: optionalPrivateKey(),

  // Cron schedule for the monitoring loop. Default: every 5 minutes.
  cronSchedule: process.env.CRON_SCHEDULE?.trim() || "*/5 * * * *",

  // Minimum idle USDC (human units) in the vault before we push to the strategy.
  idleThresholdUsdc: num("IDLE_THRESHOLD_USDC", 100),

  // Keep this much idle USDC in the vault as a withdrawal buffer (human units).
  idleReserveUsdc: num("IDLE_RESERVE_USDC", 0),

  // Don't bother supplying to Aave unless at least this much (human units) can be deployed.
  minSupplyUsdc: num("MIN_SUPPLY_USDC", 1),

  // If true, log decisions but never send transactions.
  dryRun: bool("DRY_RUN", false),

  // Where to append the JSON history (one record per cycle).
  historyFile: process.env.HISTORY_FILE?.trim() || "data/history.json",

  // Hard cap on history records kept on disk (older ones are trimmed).
  historyMaxRecords: num("HISTORY_MAX_RECORDS", 5000),
} as const;

export type KeeperConfig = typeof config;

export function requirePrivateKey(): `0x${string}` {
  if (!config.privateKey) {
    throw new Error(
      "This action requires a signer. Set PRIVATE_KEY in the environment (or run with DRY_RUN=true to simulate)."
    );
  }
  return config.privateKey;
}
