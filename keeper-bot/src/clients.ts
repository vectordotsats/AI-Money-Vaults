import {
  createPublicClient,
  createWalletClient,
  http,
  defineChain,
  type Account,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia } from "viem/chains";
import { config } from "./config.js";

// Use viem's built-in Sepolia definition when chainId matches; otherwise build
// a minimal chain object so the bot can point at any EVM network/RPC.
function resolveChain() {
  if (config.chainId === sepolia.id) {
    return sepolia;
  }
  return defineChain({
    id: config.chainId,
    name: `chain-${config.chainId}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [config.rpcUrl] } },
  });
}

export const chain = resolveChain();

// Types are inferred (not annotated with viem's broad base types) to avoid
// generic-variance friction under `strict`.
export const publicClient = createPublicClient({
  chain,
  transport: http(config.rpcUrl),
});

let _account: Account | undefined;
let _walletClient: ReturnType<typeof createWalletClient> | undefined;

/** The keeper account derived from PRIVATE_KEY, or undefined in read-only mode. */
export function getAccount(): Account | undefined {
  if (_account) return _account;
  if (!config.privateKey) return undefined;
  _account = privateKeyToAccount(config.privateKey);
  return _account;
}

/** Wallet client for sending transactions. Throws if no PRIVATE_KEY is set. */
export function getWalletClient(): {
  walletClient: ReturnType<typeof createWalletClient>;
  account: Account;
} {
  const account = getAccount();
  if (!account) {
    throw new Error("No PRIVATE_KEY configured — cannot send transactions.");
  }
  if (!_walletClient) {
    _walletClient = createWalletClient({ account, chain, transport: http(config.rpcUrl) });
  }
  return { walletClient: _walletClient, account };
}
