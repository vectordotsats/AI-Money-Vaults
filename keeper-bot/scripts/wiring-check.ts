// Verifies (and optionally fixes) the cross-wiring between the vault, the
// strategy, and the keeper signer.
//
//   npm run wiring         → read-only report
//   npm run wiring:fix     → also send the txns needed to correct it
//
// Wiring must satisfy:
//   vault.strategy()  == STRATEGY_ADDRESS
//   strategy.vault()  == VAULT_ADDRESS
//   vault.keeper()    == signer            (so depositToStrategy works)
//   strategy.keeper() == signer            (so supplyToAave works)
//
// Fixes require the signer to be the OWNER of each contract:
//   vault.setStrategy(), vault.setKeeper()       (onlyOwner)
//   strategy.updateVault(), strategy.updateKeeper() (onlyOwner)

import { type Abi, type Address } from "viem";
import { config } from "../src/config.js";
import { publicClient, getAccount, getWalletClient } from "../src/clients.js";
import { VAULT_ABI, STRATEGY_ABI } from "../src/abi.js";
import { log } from "../src/logger.js";

const FIX = process.argv.includes("--fix");

function eq(a: string, b: string) {
  return a.toLowerCase() === b.toLowerCase();
}

async function readWiring() {
  const v = { address: config.vaultAddress, abi: VAULT_ABI } as const;
  const s = { address: config.strategyAddress, abi: STRATEGY_ABI } as const;
  const [vStrategy, vKeeper, vOwner, sVault, sKeeper, sOwner] = await Promise.all([
    publicClient.readContract({ ...v, functionName: "strategy" }),
    publicClient.readContract({ ...v, functionName: "keeper" }),
    publicClient.readContract({ ...v, functionName: "owner" }),
    publicClient.readContract({ ...s, functionName: "vault" }),
    publicClient.readContract({ ...s, functionName: "keeper" }),
    publicClient.readContract({ ...s, functionName: "owner" }),
  ]);
  return { vStrategy, vKeeper, vOwner, sVault, sKeeper, sOwner } as Record<string, Address>;
}

async function sendFix(
  address: Address,
  abi: Abi,
  functionName: string,
  args: readonly unknown[],
  label: string
) {
  const { walletClient, account } = getWalletClient();
  const { request } = await publicClient.simulateContract({
    address,
    abi,
    functionName: functionName as never,
    args: args as never,
    account,
  });
  const hash = await walletClient.writeContract(request);
  log.action(`${label} → ${hash}`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`${label} reverted (${hash})`);
  log.action(`${label} → confirmed`);
}

async function main() {
  log.info("Wiring check", {
    vault: config.vaultAddress,
    strategy: config.strategyAddress,
    mode: FIX ? "fix" : "read-only",
  });

  const w = await readWiring();
  const signer = getAccount()?.address;

  const checks = [
    {
      name: "vault.strategy() == STRATEGY_ADDRESS",
      ok: eq(w.vStrategy, config.strategyAddress),
      actual: w.vStrategy,
      expected: config.strategyAddress,
      fix: () => sendFix(config.vaultAddress, VAULT_ABI, "setStrategy", [config.strategyAddress], "vault.setStrategy"),
      fixOwner: w.vOwner,
    },
    {
      name: "strategy.vault() == VAULT_ADDRESS",
      ok: eq(w.sVault, config.vaultAddress),
      actual: w.sVault,
      expected: config.vaultAddress,
      fix: () => sendFix(config.strategyAddress, STRATEGY_ABI, "updateVault", [config.vaultAddress], "strategy.updateVault"),
      fixOwner: w.sOwner,
    },
  ];

  // Keeper checks only matter if we have a signer to point them at.
  if (signer) {
    checks.push(
      {
        name: "vault.keeper() == signer",
        ok: eq(w.vKeeper, signer),
        actual: w.vKeeper,
        expected: signer,
        fix: () => sendFix(config.vaultAddress, VAULT_ABI, "setKeeper", [signer], "vault.setKeeper"),
        fixOwner: w.vOwner,
      },
      {
        name: "strategy.keeper() == signer",
        ok: eq(w.sKeeper, signer),
        actual: w.sKeeper,
        expected: signer,
        fix: () => sendFix(config.strategyAddress, STRATEGY_ABI, "updateKeeper", [signer], "strategy.updateKeeper"),
        fixOwner: w.sOwner,
      }
    );
  } else {
    log.warn("No PRIVATE_KEY set — skipping keeper checks (can't determine signer).");
  }

  let allOk = true;
  for (const c of checks) {
    if (c.ok) {
      log.info(`PASS  ${c.name}`);
      continue;
    }
    allOk = false;
    log.warn(`FAIL  ${c.name}\n        expected ${c.expected}\n        actual   ${c.actual}`);

    if (!FIX) continue;
    if (!signer) {
      log.error("  → cannot fix without PRIVATE_KEY.");
      continue;
    }
    if (!eq(c.fixOwner, signer)) {
      log.error(`  → cannot fix: signer ${signer} is not the owner (${c.fixOwner}) of this contract.`);
      continue;
    }
    log.action(`  → fixing: ${c.name}`);
    await c.fix();
  }

  if (allOk) {
    log.info("✅ Wiring is correct. The keeper loop can run.");
  } else if (FIX) {
    log.info("Re-checking after fixes…");
    const after = await readWiring();
    const stillBroken =
      !eq(after.vStrategy, config.strategyAddress) ||
      !eq(after.sVault, config.vaultAddress) ||
      (!!signer && (!eq(after.vKeeper, signer) || !eq(after.sKeeper, signer)));
    if (stillBroken) {
      log.error("Some wiring is still incorrect (see ownership warnings above).");
      process.exit(1);
    }
    log.info("✅ Wiring corrected.");
  } else {
    log.warn("Wiring has problems. Re-run with `npm run wiring:fix` (signer must be contract owner).");
    process.exit(1);
  }
}

main().catch((err) => {
  log.error(`wiring-check failed: ${(err as Error).message}`);
  process.exit(1);
});
