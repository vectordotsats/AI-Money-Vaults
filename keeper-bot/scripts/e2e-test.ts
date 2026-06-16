// End-to-end test of the full Axis loop on a live network (Sepolia by default).
//
//   deposit USDC → depositToStrategy → supplyToAave → [wait] → withdraw
//
// It asserts balances/shares/yield at every step and prints a PASS/FAIL summary.
// This SENDS REAL TRANSACTIONS and spends gas — run it against a testnet with a
// funded keeper that is also the vault/strategy keeper (run `npm run wiring:fix`
// first if needed).
//
//   RPC_URL=... PRIVATE_KEY=... npm run e2e
//
// Config:
//   E2E_AMOUNT_USDC    deposit size (default 10)
//   E2E_WAIT_SECONDS   pause before withdraw to let yield accrue (default 0; try 3600 for ~1h)

import { formatUnits, parseUnits, type Address, type Abi } from "viem";
import { config } from "../src/config.js";
import { publicClient, getWalletClient } from "../src/clients.js";
import { VAULT_ABI, STRATEGY_ABI, ERC20_ABI } from "../src/abi.js";
import { log } from "../src/logger.js";

const AMOUNT_USDC = Number(process.env.E2E_AMOUNT_USDC ?? "10");
const WAIT_SECONDS = Number(process.env.E2E_WAIT_SECONDS ?? "0");

let passed = 0;
let failed = 0;

function assert(cond: boolean, msg: string) {
  if (cond) {
    passed += 1;
    log.action(`  ✓ ${msg}`);
  } else {
    failed += 1;
    log.error(`  ✗ ${msg}`);
  }
}

async function write(address: Address, abi: Abi, functionName: string, args: readonly unknown[], label: string) {
  const { walletClient, account } = getWalletClient();
  const { request } = await publicClient.simulateContract({
    address,
    abi,
    functionName: functionName as never,
    args: args as never,
    account,
  });
  const hash = await walletClient.writeContract(request);
  log.info(`  ${label} → ${hash}`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`${label} reverted (${hash})`);
  return hash;
}

async function main() {
  const { account } = getWalletClient();
  const me = account.address;
  const d = await publicClient.readContract({ address: config.usdcAddress, abi: ERC20_ABI, functionName: "decimals" });
  const amount = parseUnits(String(AMOUNT_USDC), d);
  const f = (v: bigint) => formatUnits(v, d);

  const vault = { address: config.vaultAddress, abi: VAULT_ABI } as const;
  const strat = { address: config.strategyAddress, abi: STRATEGY_ABI } as const;
  const usdc = { address: config.usdcAddress, abi: ERC20_ABI } as const;

  const readUsdc = (who: Address) => publicClient.readContract({ ...usdc, functionName: "balanceOf", args: [who] });
  const readShares = (who: Address) => publicClient.readContract({ ...vault, functionName: "balanceOf", args: [who] });
  const readVaultIdle = () => publicClient.readContract({ ...vault, functionName: "idleBalance" });
  const readDeployed = () => publicClient.readContract({ ...strat, functionName: "totalDeployed" });
  const readStratTotal = () => publicClient.readContract({ ...strat, functionName: "totalDepositedInContract" });
  const readYield = () => publicClient.readContract({ ...strat, functionName: "accruedYield" });
  const readMaxWithdraw = () => publicClient.readContract({ ...vault, functionName: "maxWithdraw", args: [me] });

  log.info("════════ Axis E2E test ════════", {
    network: config.chainId,
    signer: me,
    vault: config.vaultAddress,
    strategy: config.strategyAddress,
    amountUSDC: AMOUNT_USDC,
    waitSeconds: WAIT_SECONDS,
  });

  // ── Preconditions ──
  log.info("Step 0: preconditions");
  const myUsdc = await readUsdc(me);
  assert(myUsdc >= amount, `signer holds >= ${AMOUNT_USDC} USDC (has ${f(myUsdc)})`);
  const [vKeeper, vOwner, sKeeper] = await Promise.all([
    publicClient.readContract({ ...vault, functionName: "keeper" }),
    publicClient.readContract({ ...vault, functionName: "owner" }),
    publicClient.readContract({ ...strat, functionName: "keeper" }),
  ]);
  const eq = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();
  assert(eq(vKeeper, me) || eq(vOwner, me), "signer can call depositToStrategy (vault keeper or owner)");
  assert(eq(sKeeper, me), "signer can call supplyToAave (strategy keeper)");
  const wiredStrategy = await publicClient.readContract({ ...vault, functionName: "strategy" });
  assert(eq(wiredStrategy, config.strategyAddress), "vault.strategy() points at STRATEGY_ADDRESS");
  if (failed > 0) {
    log.error("Preconditions failed — aborting before sending value. Fix with `npm run wiring:fix`.");
    process.exit(1);
  }

  // ── Step 1: deposit ──
  log.info(`Step 1: deposit ${AMOUNT_USDC} USDC`);
  const allowance = await publicClient.readContract({ ...usdc, functionName: "allowance", args: [me, config.vaultAddress] });
  if (allowance < amount) await write(config.usdcAddress, ERC20_ABI as Abi, "approve", [config.vaultAddress, amount], "approve");
  const shares0 = await readShares(me);
  const usdc0 = await readUsdc(me);
  await write(config.vaultAddress, VAULT_ABI as Abi, "deposit", [amount, me], "deposit");
  const shares1 = await readShares(me);
  const usdc1 = await readUsdc(me);
  assert(shares1 > shares0, `received aiVLT shares (+${f(shares1 - shares0)})`);
  assert(usdc0 - usdc1 === amount, `USDC debited by exactly ${AMOUNT_USDC} (−${f(usdc0 - usdc1)})`);

  // ── Step 2: depositToStrategy ──
  log.info("Step 2: depositToStrategy (vault → strategy)");
  const vaultIdle1 = await readVaultIdle();
  const stratTotal0 = await readStratTotal();
  await write(config.vaultAddress, VAULT_ABI as Abi, "depositToStrategy", [amount], "depositToStrategy");
  const vaultIdle2 = await readVaultIdle();
  const stratTotal1 = await readStratTotal();
  assert(vaultIdle1 - vaultIdle2 === amount, `vault idle decreased by ${AMOUNT_USDC}`);
  assert(stratTotal1 - stratTotal0 === amount, `strategy accounting increased by ${AMOUNT_USDC}`);

  // ── Step 3: supplyToAave ──
  log.info("Step 3: supplyToAave (strategy → Aave)");
  const deployed0 = await readDeployed();
  await write(config.strategyAddress, STRATEGY_ABI as Abi, "supplyToAave", [amount], "supplyToAave");
  const deployed1 = await readDeployed();
  assert(deployed1 - deployed0 === amount, `strategy deployed to Aave increased by ${AMOUNT_USDC}`);

  // ── Step 4: optional wait for yield ──
  if (WAIT_SECONDS > 0) {
    log.info(`Step 4: waiting ${WAIT_SECONDS}s for yield to accrue…`);
    await new Promise((r) => setTimeout(r, WAIT_SECONDS * 1000));
    const y = await readYield();
    log.info(`  accrued yield so far: ${f(y)} USDC`);
    assert(y >= 0n, "accruedYield() readable (yield may be dust on small amounts/short waits)");
  } else {
    log.info("Step 4: skipping wait (set E2E_WAIT_SECONDS=3600 to measure ~1h of yield)");
  }

  // ── Step 5: withdraw everything (vault auto-pulls from Aave) ──
  log.info("Step 5: withdraw (auto-pull from Aave)");
  const maxW = await readMaxWithdraw();
  const usdcBeforeW = await readUsdc(me);
  await write(config.vaultAddress, VAULT_ABI as Abi, "withdraw", [maxW, me, me], "withdraw");
  const usdcAfterW = await readUsdc(me);
  const got = usdcAfterW - usdcBeforeW;
  assert(got > 0n, `received USDC back from withdraw (+${f(got)})`);
  assert(got >= amount - 1n, `recovered at least the principal (got ${f(got)} vs deposited ${AMOUNT_USDC})`);

  // ── Summary ──
  log.info("════════ E2E summary ════════", {
    principalUSDC: AMOUNT_USDC,
    recoveredUSDC: f(got),
    netVsPrincipalUSDC: f(got - amount),
    checksPassed: passed,
    checksFailed: failed,
  });
  if (failed > 0) {
    log.error(`E2E FAILED (${failed} checks failed)`);
    process.exit(1);
  }
  log.action("E2E PASSED ✅ — the full deposit→deploy→earn→withdraw loop works on-chain.");
}

main().catch((err) => {
  log.error(`E2E crashed: ${(err as Error).message}`, { stack: (err as Error).stack });
  process.exit(1);
});
