"use client";

import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { parseEther, formatEther } from "viem";
import { useState } from "react";
import { VAULT_ADDRESS, USDC_ADDRESS } from "./constants/addresses";
import { VAULT_ABI, ERC20_USDC_ABI } from "./constants/abi";

export default function App() {
  const { address, isConnected } = useAccount();
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");

  const { writeContract, data: txHash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const { data: totalDeposits } = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: "totalDeposits",
  });

  const { data: userShares } = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: "balanceOf",
    args: [address!],
    query: { enabled: !!address },
  });

  const { data: timeInVault } = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: "timeInVault",
    args: [address!],
    query: { enabled: !!address },
  });

  async function handleDeposit() {
    if (!depositAmount) return;
    const amount = parseEther(depositAmount);
    writeContract({
      address: USDC_ADDRESS,
      abi: ERC20_USDC_ABI,
      functionName: "approve",
      args: [VAULT_ADDRESS, amount],
    });
  }

  async function handleWithdraw() {
    if (!withdrawAmount) return;
    const amount = parseEther(withdrawAmount);
    writeContract({
      address: VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: "withdraw",
      args: [amount, address!, address!],
    });
  }

  const formatSeconds = (seconds: bigint) => {
    const days = Number(seconds) / 86400;
    return `${days.toFixed(1)} days`;
  };

  return (
    <main className="min-h-screen bg-gray-950 text-white p-8">
      <div className="max-w-3xl mx-auto">
        {/* Header */}
        <div className="flex justify-between items-center mb-12">
          <div>
            <h1 className="text-2xl font-bold">AIVault</h1>
            <p className="text-gray-400 text-sm">Deposit. Earn. Withdraw.</p>
          </div>
          <ConnectButton />
        </div>

        {/* Vault Stats */}
        <div className="grid grid-cols-3 gap-4 mb-8">
          <div className="bg-gray-900 rounded-xl p-5">
            <p className="text-gray-400 text-sm mb-1">Total Deposits</p>
            <p className="text-xl font-semibold">
              {totalDeposits ? formatEther(totalDeposits as bigint) : "0"} USDC
            </p>
          </div>
          <div className="bg-gray-900 rounded-xl p-5">
            <p className="text-gray-400 text-sm mb-1">Your Balance</p>
            <p className="text-xl font-semibold">
              {userShares ? formatEther(userShares as bigint) : "0"} aiVLT
            </p>
          </div>
          <div className="bg-gray-900 rounded-xl p-5">
            <p className="text-gray-400 text-sm mb-1">Time in Vault</p>
            <p className="text-xl font-semibold">
              {timeInVault ? formatSeconds(timeInVault as bigint) : "0 days"}
            </p>
          </div>
        </div>

        {/* Actions */}
        {isConnected ? (
          <div className="grid grid-cols-2 gap-4">
            <div className="bg-gray-900 rounded-xl p-6">
              <h2 className="text-lg font-semibold mb-4">Deposit</h2>
              <input
                type="number"
                placeholder="Amount in USDC"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                className="w-full bg-gray-800 rounded-lg px-4 py-3 mb-4 text-white placeholder-gray-500 outline-none"
              />
              <button
                onClick={handleDeposit}
                disabled={isPending || isConfirming}
                className="w-full bg-blue-600 hover:bg-blue-700 disabled:opacity-50 rounded-lg py-3 font-semibold transition"
              >
                {isPending
                  ? "Approving..."
                  : isConfirming
                    ? "Confirming..."
                    : "Deposit"}
              </button>
            </div>

            <div className="bg-gray-900 rounded-xl p-6">
              <h2 className="text-lg font-semibold mb-4">Withdraw</h2>
              <input
                type="number"
                placeholder="Amount in USDC"
                value={withdrawAmount}
                onChange={(e) => setWithdrawAmount(e.target.value)}
                className="w-full bg-gray-800 rounded-lg px-4 py-3 mb-4 text-white placeholder-gray-500 outline-none"
              />
              <button
                onClick={handleWithdraw}
                disabled={isPending || isConfirming}
                className="w-full bg-red-600 hover:bg-red-700 disabled:opacity-50 rounded-lg py-3 font-semibold transition"
              >
                {isPending
                  ? "Processing..."
                  : isConfirming
                    ? "Confirming..."
                    : "Withdraw"}
              </button>
            </div>
          </div>
        ) : (
          <div className="text-center py-20 text-gray-500">
            Connect your wallet to interact with the vault
          </div>
        )}

        {isSuccess && (
          <div className="mt-4 bg-green-900 text-green-300 rounded-xl p-4 text-center">
            Transaction confirmed successfully
          </div>
        )}
      </div>
    </main>
  );
}
