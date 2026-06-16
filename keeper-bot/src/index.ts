import cron from "node-cron";
import { config } from "./config.js";
import { publicClient, getAccount } from "./clients.js";
import { VAULT_ABI, STRATEGY_ABI } from "./abi.js";
import { runCycle } from "./keeper.js";
import { log } from "./logger.js";

const runOnce = process.argv.includes("--once");

async function preflight() {
  log.info("Axis Keeper Bot starting up");
  log.info("Configuration:", {
    chainId: config.chainId,
    vault: config.vaultAddress,
    strategy: config.strategyAddress,
    usdc: config.usdcAddress,
    schedule: config.cronSchedule,
    idleThresholdUsdc: config.idleThresholdUsdc,
    idleReserveUsdc: config.idleReserveUsdc,
    minSupplyUsdc: config.minSupplyUsdc,
    dryRun: config.dryRun,
    mode: runOnce ? "once" : "scheduled",
  });

  const block = await publicClient.getBlockNumber();
  log.info(`RPC reachable — current block ${block}`);

  const account = getAccount();
  if (!account) {
    if (!config.dryRun) {
      log.warn("No PRIVATE_KEY set — running read-only. Set DRY_RUN=true to silence write attempts.");
    }
    return;
  }
  log.info(`Keeper signer: ${account.address}`);

  // Authorization sanity check: warn loudly if this signer can't actually act.
  const [vaultKeeper, vaultOwner, strategyKeeper, strategyPaused] = await Promise.all([
    publicClient.readContract({ address: config.vaultAddress, abi: VAULT_ABI, functionName: "keeper" }),
    publicClient.readContract({ address: config.vaultAddress, abi: VAULT_ABI, functionName: "owner" }),
    publicClient.readContract({ address: config.strategyAddress, abi: STRATEGY_ABI, functionName: "keeper" }),
    publicClient.readContract({ address: config.strategyAddress, abi: STRATEGY_ABI, functionName: "paused" }),
  ]);

  const canPush = eq(account.address, vaultKeeper) || eq(account.address, vaultOwner);
  const canSupply = eq(account.address, strategyKeeper);

  if (!canPush) {
    log.warn(
      `Signer is neither vault keeper (${vaultKeeper}) nor owner (${vaultOwner}) — depositToStrategy() will revert. Run \`npm run wiring:fix\`.`
    );
  }
  if (!canSupply) {
    log.warn(
      `Signer is not the strategy keeper (${strategyKeeper}) — supplyToAave() will revert. Run \`npm run wiring:fix\`.`
    );
  }
  if (strategyPaused) log.warn("Strategy is PAUSED — deployments will be skipped until unpaused.");
  if (canPush && canSupply && !strategyPaused) log.info("Authorization OK — signer can push and supply.");
}

function eq(a: string, b: string) {
  return a.toLowerCase() === b.toLowerCase();
}

async function safeCycle() {
  try {
    await runCycle();
  } catch (err) {
    // Never let one bad cycle kill the scheduler.
    log.error(`Cycle failed: ${(err as Error).message}`, { stack: (err as Error).stack });
  }
}

async function main() {
  await preflight();

  if (runOnce) {
    await safeCycle();
    log.info("Single cycle complete (--once). Exiting.");
    return;
  }

  if (!cron.validate(config.cronSchedule)) {
    throw new Error(`Invalid CRON_SCHEDULE: "${config.cronSchedule}"`);
  }

  log.info(`Scheduling keeper loop: "${config.cronSchedule}"`);
  cron.schedule(config.cronSchedule, safeCycle);

  // Run one cycle immediately so we don't wait a full interval on boot.
  await safeCycle();

  log.info("Keeper running. Press Ctrl+C to stop.");
}

process.on("SIGINT", () => {
  log.info("SIGINT received — shutting down.");
  process.exit(0);
});
process.on("SIGTERM", () => {
  log.info("SIGTERM received — shutting down.");
  process.exit(0);
});
process.on("unhandledRejection", (reason) => {
  log.error(`Unhandled rejection: ${String(reason)}`);
});

main().catch((err) => {
  log.error(`Fatal: ${(err as Error).message}`, { stack: (err as Error).stack });
  process.exit(1);
});
