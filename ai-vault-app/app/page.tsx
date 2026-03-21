"use client";

import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { parseEther, formatEther } from "viem";
import { useState, useEffect } from "react";
import { VAULT_ADDRESS, USDC_ADDRESS } from "./constants/addresses";
import { VAULT_ABI, ERC20_USDC_ABI } from "./constants/abi";

export default function App() {
  const { address, isConnected } = useAccount();
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [mounted, setMounted] = useState(false);

  const [depositStep, setDepositStep] = useState<"approve" | "deposit" | null>(
    null,
  );
  const [pendingAmount, setPendingAmount] = useState<bigint>(0n);

  // Use Effects.
  useEffect(() => {
    setMounted(true);
  }, []);

  // Deposit Flow Hook
  const {
    writeContract: writeDeposit,
    data: depositTxHash,
    isPending: isDepositPending,
  } = useWriteContract();
  const { isLoading: isDepositConfirming, isSuccess: isDepositSuccess } =
    useWaitForTransactionReceipt({ hash: depositTxHash });

  // Withdraw Flow Hook
  const {
    writeContract: writeWithdraw,
    data: withdrawTxHash,
    isPending: isWithdrawPending,
  } = useWriteContract();
  const { isLoading: isWithdrawConfirming, isSuccess: isWithdrawSuccess } =
    useWaitForTransactionReceipt({ hash: withdrawTxHash });

  // Deposit two-step flow
  useEffect(() => {
    if (isDepositSuccess && depositStep === "approve") {
      setDepositStep("deposit");
      writeDeposit({
        address: VAULT_ADDRESS,
        abi: VAULT_ABI,
        functionName: "deposit",
        args: [pendingAmount, address!],
      });
    }
    if (isDepositSuccess && depositStep === "deposit") {
      setDepositStep(null);
      setPendingAmount(0n);
      setDepositAmount("");
      refetchTotal();
      refetchShares();
      refetchTime();
    }
  }, [isDepositSuccess, depositStep, pendingAmount, address, writeDeposit]);

  // UseEffect watching withdrawals
  useEffect(() => {
    if (isWithdrawSuccess) {
      setWithdrawAmount("");
      refetchTotal();
      refetchShares();
      refetchTime();
    }
  }, [isWithdrawSuccess]);

  const { data: totalDeposits, refetch: refetchTotal } = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: "totalDeposits",
  });

  const { data: userShares, refetch: refetchShares } = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: "balanceOf",
    args: [address!],
    query: { enabled: !!address },
  });

  const { data: timeInVault, refetch: refetchTime } = useReadContract({
    address: VAULT_ADDRESS,
    abi: VAULT_ABI,
    functionName: "timeInVault",
    args: [address!],
    query: { enabled: !!address },
  });

  // async function handleDeposit() {
  //   if (!depositAmount) return;
  //   const amount = parseEther(depositAmount);
  //   writeContract({
  //     address: USDC_ADDRESS,
  //     abi: ERC20_USDC_ABI,
  //     functionName: "approve",
  //     args: [VAULT_ADDRESS, amount],
  //   });
  // }

  async function handleDeposit() {
    if (!depositAmount) return;
    const amount = parseEther(depositAmount);
    setPendingAmount(amount);
    setDepositStep("approve");
    writeDeposit({
      address: USDC_ADDRESS,
      abi: ERC20_USDC_ABI,
      functionName: "approve",
      args: [VAULT_ADDRESS, amount],
    });
  }

  async function handleWithdraw() {
    if (!withdrawAmount) return;
    const amount = parseEther(withdrawAmount);
    writeWithdraw({
      address: VAULT_ADDRESS,
      abi: VAULT_ABI,
      functionName: "withdraw",
      args: [amount, address!, address!],
    });
  }

  const formatSeconds = (seconds: bigint) => {
    const total = Number(seconds);
    const days = (total / 86400) | 0;
    const hours = ((total % 86400) / 3600) | 0;
    const minutes = ((total % 3600) / 60) | 0;
    const secs = total % 60;

    const parts = [];
    if (days > 0) parts.push(`${days}d`);
    if (hours > 0) parts.push(`${hours}h`);
    if (minutes > 0) parts.push(`${minutes}m`);
    if (secs > 0) parts.push(`${secs}s`);

    return parts.length > 0 ? parts.join(" ") : "0s";
  };

  return (
    <main className="min-h-screen bg-gray-900 text-white p-8">
      <div className="w-[90%] mx-auto">
        {/* Header */}
        <div className="flex justify-between items-center mb-12">
          <div>
            <h1 className="text-3xl font-bold">AI Vault</h1>
            <p className="text-gray-400 text-sm">Let Your AI Earn For You</p>
          </div>
          <ConnectButton />
        </div>

        {/* Vault Stats */}
        <div className="grid w-[100%] grid-cols-3 mb-8">
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
        {!mounted ? null : isConnected ? (
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
                disabled={isDepositPending || isDepositConfirming}
                className="w-full bg-blue-600 hover:bg-blue-700 disabled:opacity-50 rounded-lg py-3 font-semibold transition"
              >
                {isDepositPending
                  ? "Waiting..."
                  : isDepositConfirming
                    ? depositStep === "approve"
                      ? "Approving..."
                      : "Depositing..."
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
                disabled={isWithdrawPending || isWithdrawConfirming}
                className="w-full bg-red-600 hover:bg-red-700 disabled:opacity-50 rounded-lg py-3 font-semibold transition"
              >
                {isWithdrawPending
                  ? "Waiting..."
                  : isWithdrawConfirming
                    ? "Withdrawing..."
                    : "Withdraw"}
              </button>
            </div>
          </div>
        ) : (
          <div className="text-center py-20 text-gray-500">
            Connect your wallet to interact with the vault
          </div>
        )}

        {(isDepositSuccess || isWithdrawSuccess) && (
          <div className="mt-4 bg-green-900 text-green-300 rounded-xl p-4 text-center">
            Transaction confirmed successfully
          </div>
        )}
      </div>
    </main>
  );
}
