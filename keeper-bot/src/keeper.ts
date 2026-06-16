import { formatUnits, parseUnits, type Abi, type Address } from "viem";
import { config } from "./config.js";
import { publicClient, getWalletClient } from "./clients.js";
import { VAULT_ABI, STRATEGY_ABI, ERC20_ABI } from "./abi.js";
import { log, recordHistory, type HistoryRecord } from "./logger.js";

let usdcDecimals: number | undefined;
let cycleCounter = 0;

async function getUsdcDecimals(): Promise<number> {
  if (usdcDecimals !== undefined) return usdcDecimals;
  usdcDecimals = await publicClient.readContract({
    address: config.usdcAddress,
    abi: ERC20_ABI,
    functionName: "decimals",
  });
  return usdcDecimals;
}

export interface ChainState {
  decimals: number;
  vaultIdle: bigint; // real USDC token balance held by the vault
  vaultTotalIdleAccounting: bigint; // vault.totalIdleDeposits()
  vaultTotalAssets: bigint;
  strategyTotalDeposited: bigint; // totalDepositedInContract
  strategyDeployed: bigint; // totalDeployed
  strategyIdle: bigint; // idleBalanceInVault (deposited - deployed)
  accruedYield: bigint;
  maxSupplyPct: bigint;
  paused: boolean;
}

export async function readState(): Promise<ChainState> {
  const decimals = await getUsdcDecimals();
  const vault = { address: config.vaultAddress, abi: VAULT_ABI } as const;
  const strat = { address: config.strategyAddress, abi: STRATEGY_ABI } as const;

  const results = await publicClient.multicall({
    allowFailure: false,
    contracts: [
      { ...vault, functionName: "idleBalance" },
      { ...vault, functionName: "totalIdleDeposits" },
      { ...vault, functionName: "totalAssets" },
      { ...strat, functionName: "totalDepositedInContract" },
      { ...strat, functionName: "totalDeployed" },
      { ...strat, functionName: "idleBalanceInVault" },
      { ...strat, functionName: "accruedYield" },
      { ...strat, functionName: "maxSupplyPercentage" },
      { ...strat, functionName: "paused" },
    ],
  });

  return {
    decimals,
    vaultIdle: results[0] as bigint,
    vaultTotalIdleAccounting: results[1] as bigint,
    vaultTotalAssets: results[2] as bigint,
    strategyTotalDeposited: results[3] as bigint,
    strategyDeployed: results[4] as bigint,
    strategyIdle: results[5] as bigint,
    accruedYield: results[6] as bigint,
    maxSupplyPct: results[7] as bigint,
    paused: results[8] as boolean,
  };
}

function fmt(v: bigint, decimals: number): string {
  return formatUnits(v, decimals);
}

function allocationPct(state: ChainState): number {
  if (state.vaultTotalAssets === 0n) return 0;
  // share of total assets currently earning in Aave
  return Number((state.strategyDeployed * 10000n) / state.vaultTotalAssets) / 100;
}

function logSnapshot(state: ChainState) {
  const d = state.decimals;
  log.info("On-chain snapshot:", {
    vaultIdleUSDC: fmt(state.vaultIdle, d),
    vaultTotalAssetsUSDC: fmt(state.vaultTotalAssets, d),
    strategyDeployedUSDC: fmt(state.strategyDeployed, d),
    strategyIdleUSDC: fmt(state.strategyIdle, d),
    accruedYieldUSDC: fmt(state.accruedYield, d),
    allocationPct: `${allocationPct(state)}%`,
    maxSupplyPct: `${state.maxSupplyPct}%`,
    paused: state.paused,
  });
}

/** Amount (wei) we can safely supply to Aave without tripping the guardrail. */
function computeSupplyable(state: ChainState): bigint {
  const total = state.strategyTotalDeposited;
  if (total === 0n) return 0n;
  const maxNewDeployed = (state.maxSupplyPct * total) / 100n; // floor — matches contract math
  const headroom = maxNewDeployed > state.strategyDeployed ? maxNewDeployed - state.strategyDeployed : 0n;
  return state.strategyIdle < headroom ? state.strategyIdle : headroom;
}

async function sendTx(
  address: Address,
  abi: Abi,
  functionName: string,
  args: readonly unknown[],
  label: string
): Promise<string> {
  const { walletClient, account } = getWalletClient();
  // Simulate first so we surface reverts (with decoded custom errors) before spending gas.
  const { request } = await publicClient.simulateContract({
    address,
    abi,
    functionName: functionName as never,
    args: args as never,
    account,
  });
  const hash = await walletClient.writeContract(request);
  log.action(`${label} → tx submitted: ${hash}`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") {
    throw new Error(`${label} reverted (tx ${hash})`);
  }
  log.action(`${label} → confirmed in block ${receipt.blockNumber}`);
  return hash;
}

export async function runCycle(): Promise<HistoryRecord> {
  cycleCounter += 1;
  const cycle = cycleCounter;
  log.info(`──────── cycle #${cycle} ${config.dryRun ? "(DRY RUN)" : ""} ────────`);

  let state = await readState();
  logSnapshot(state);

  const d = state.decimals;
  const txHashes: string[] = [];
  let pushedToStrategy: bigint | null = null;
  let suppliedToAave: bigint | null = null;
  let note: string | undefined;

  const threshold = parseUnits(String(config.idleThresholdUsdc), d);
  const reserve = parseUnits(String(config.idleReserveUsdc), d);
  const minSupply = parseUnits(String(config.minSupplyUsdc), d);

  if (state.paused) {
    note = "strategy is paused — skipping deployment";
    log.warn(note);
  } else {
    // ── Step 1: push idle vault USDC → strategy ──
    const pushable0 =
      state.vaultIdle < state.vaultTotalIdleAccounting ? state.vaultIdle : state.vaultTotalIdleAccounting;
    const pushable = pushable0 > reserve ? pushable0 - reserve : 0n;

    if (state.vaultIdle < threshold) {
      log.info(
        `Idle ${fmt(state.vaultIdle, d)} USDC below threshold ${config.idleThresholdUsdc} — nothing to push.`
      );
    } else if (pushable === 0n) {
      log.info("Above threshold but nothing pushable after reserve — skipping push.");
    } else if (config.dryRun) {
      pushedToStrategy = pushable;
      log.action(`[DRY RUN] would depositToStrategy(${fmt(pushable, d)} USDC)`);
    } else {
      const hash = await sendTx(
        config.vaultAddress,
        VAULT_ABI,
        "depositToStrategy",
        [pushable],
        `depositToStrategy(${fmt(pushable, d)} USDC)`
      );
      txHashes.push(hash);
      pushedToStrategy = pushable;
      state = await readState(); // refresh so the supply step sees the new strategy balance
    }

    // ── Step 2: supply strategy-idle USDC → Aave (so it actually earns) ──
    const supplyable = computeSupplyable(state);
    if (supplyable < minSupply) {
      log.info(
        `Strategy supplyable ${fmt(supplyable, d)} USDC below min ${config.minSupplyUsdc} — not supplying to Aave.`
      );
    } else if (config.dryRun) {
      suppliedToAave = supplyable;
      log.action(`[DRY RUN] would supplyToAave(${fmt(supplyable, d)} USDC)`);
    } else {
      const hash = await sendTx(
        config.strategyAddress,
        STRATEGY_ABI,
        "supplyToAave",
        [supplyable],
        `supplyToAave(${fmt(supplyable, d)} USDC)`
      );
      txHashes.push(hash);
      suppliedToAave = supplyable;
      state = await readState();
    }
  }

  if (txHashes.length > 0) {
    log.info("Post-action snapshot:");
    logSnapshot(state);
  }

  const record: HistoryRecord = {
    ts: new Date().toISOString(),
    cycle,
    vaultIdleUsdc: fmt(state.vaultIdle, d),
    vaultTotalAssetsUsdc: fmt(state.vaultTotalAssets, d),
    strategyDeployedUsdc: fmt(state.strategyDeployed, d),
    strategyIdleUsdc: fmt(state.strategyIdle, d),
    accruedYieldUsdc: fmt(state.accruedYield, d),
    allocationPct: allocationPct(state),
    paused: state.paused,
    pushedToStrategyUsdc: pushedToStrategy === null ? null : fmt(pushedToStrategy, d),
    suppliedToAaveUsdc: suppliedToAave === null ? null : fmt(suppliedToAave, d),
    txHashes,
    dryRun: config.dryRun,
    note,
  };
  await recordHistory(record);
  return record;
}
