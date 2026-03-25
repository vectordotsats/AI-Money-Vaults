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

/* ── Utility ── */
const fmt = (v: bigint | undefined) =>
  v
    ? Number(formatEther(v)).toLocaleString("en-US", {
        maximumFractionDigits: 4,
      })
    : "0";

const formatSeconds = (seconds: bigint) => {
  const total = Number(seconds);
  const d = (total / 86400) | 0;
  const h = ((total % 86400) / 3600) | 0;
  const m = ((total % 3600) / 60) | 0;
  const s = total % 60;
  const parts: string[] = [];
  if (d) parts.push(`${d}d`);
  if (h) parts.push(`${h}h`);
  if (m) parts.push(`${m}m`);
  if (s || !parts.length) parts.push(`${s}s`);
  return parts.join(" ");
};

/* ── Stat Card ── */
function StatCard({
  label,
  value,
  unit,
  accent = false,
}: {
  label: string;
  value: string;
  unit?: string;
  accent?: boolean;
}) {
  return (
    <div className="group relative overflow-hidden rounded-2xl border border-white/[0.06] bg-[#14151A] p-5 transition-all duration-300 hover:border-white/[0.12]">
      {accent && (
        <div className="absolute -right-6 -top-6 h-24 w-24 rounded-full bg-[#2563EB]/10 blur-2xl transition-all duration-500 group-hover:bg-[#2563EB]/20" />
      )}
      <p className="text-[13px] font-medium tracking-wide text-[#7A7E8F] uppercase">
        {label}
      </p>
      <p className="mt-2 text-2xl font-semibold tracking-tight text-white">
        {value}
        {unit && (
          <span className="ml-1.5 text-sm font-normal text-[#7A7E8F]">
            {unit}
          </span>
        )}
      </p>
    </div>
  );
}

/* ── Toast / Transaction Feedback ── */
function TxToast({
  show,
  message,
  type = "success",
  onClose,
}: {
  show: boolean;
  message: string;
  type?: "success" | "pending";
  onClose: () => void;
}) {
  useEffect(() => {
    if (show && type === "success") {
      const t = setTimeout(onClose, 5000);
      return () => clearTimeout(t);
    }
  }, [show, type, onClose]);

  if (!show) return null;

  const colors =
    type === "success"
      ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-400"
      : "border-blue-500/30 bg-blue-500/10 text-blue-400";

  return (
    <div
      className={`fixed bottom-6 right-6 z-50 flex items-center gap-3 rounded-xl border px-5 py-3.5 shadow-2xl backdrop-blur-sm transition-all duration-300 ${colors}`}
    >
      {type === "pending" && (
        <svg className="h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none">
          <circle
            className="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            strokeWidth="3"
          />
          <path
            className="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
          />
        </svg>
      )}
      {type === "success" && (
        <svg className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
          <path
            fillRule="evenodd"
            d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
            clipRule="evenodd"
          />
        </svg>
      )}
      <span className="text-sm font-medium">{message}</span>
      <button
        onClick={onClose}
        className="ml-2 opacity-60 hover:opacity-100 transition"
      >
        ✕
      </button>
    </div>
  );
}

/* ── Main App ── */
export default function App() {
  const { address, isConnected } = useAccount();
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [mounted, setMounted] = useState(false);
  const [activeTab, setActiveTab] = useState<"deposit" | "withdraw">("deposit");
  const [toastVisible, setToastVisible] = useState(false);
  const [toastMsg, setToastMsg] = useState("");

  const [depositStep, setDepositStep] = useState<"approve" | "deposit" | null>(
    null,
  );
  const [pendingAmount, setPendingAmount] = useState<bigint>(0n);

  useEffect(() => setMounted(true), []);

  /* ── Contract Hooks ── */
  const {
    writeContract: writeDeposit,
    data: depositTxHash,
    isPending: isDepositPending,
  } = useWriteContract();
  const { isLoading: isDepositConfirming, isSuccess: isDepositSuccess } =
    useWaitForTransactionReceipt({ hash: depositTxHash });

  const {
    writeContract: writeWithdraw,
    data: withdrawTxHash,
    isPending: isWithdrawPending,
  } = useWriteContract();
  const { isLoading: isWithdrawConfirming, isSuccess: isWithdrawSuccess } =
    useWaitForTransactionReceipt({ hash: withdrawTxHash });

  /* ── Deposit two-step ── */
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
      setToastMsg("Deposit confirmed");
      setToastVisible(true);
      refetchTotal();
      refetchShares();
      refetchTime();
    }
  }, [isDepositSuccess, depositStep, pendingAmount, address, writeDeposit]);

  useEffect(() => {
    if (isWithdrawSuccess) {
      setWithdrawAmount("");
      setToastMsg("Withdrawal confirmed");
      setToastVisible(true);
      refetchTotal();
      refetchShares();
      refetchTime();
    }
  }, [isWithdrawSuccess]);

  /* ── Reads ── */
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

  /* ── Handlers ── */
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

  /* ── Derived State ── */
  const isDepositing = isDepositPending || isDepositConfirming;
  const isWithdrawing = isWithdrawPending || isWithdrawConfirming;
  const isTxPending = isDepositing || isWithdrawing;

  const depositButtonLabel = isDepositPending
    ? "Confirm in wallet…"
    : isDepositConfirming
      ? depositStep === "approve"
        ? "Approving USDC…"
        : "Depositing…"
      : "Deposit";

  const withdrawButtonLabel = isWithdrawPending
    ? "Confirm in wallet…"
    : isWithdrawConfirming
      ? "Withdrawing…"
      : "Withdraw";

  /* ── Render ── */
  return (
    <main className="relative min-h-screen bg-[#0B0C10] text-white selection:bg-blue-600/30">
      {/* Subtle background gradient */}
      <div className="pointer-events-none absolute inset-0 overflow-hidden">
        <div className="absolute -top-[40%] left-1/2 h-[800px] w-[800px] -translate-x-1/2 rounded-full bg-[#2563EB]/[0.04] blur-[120px]" />
      </div>

      <div className="relative mx-auto max-w-[90%] px-5 py-8">
        {/* ── Header ── */}
        <header className="flex items-center justify-between mb-10">
          <div className="flex items-center gap-3">
            {/* Logo mark */}
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[#2563EB]/10 border border-[#2563EB]/20">
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#2563EB"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M12 2L2 7l10 5 10-5-10-5z" />
                <path d="M2 17l10 5 10-5" />
                <path d="M2 12l10 5 10-5" />
              </svg>
            </div>
            <div>
              <h1 className="text-lg font-semibold tracking-tight">AI Vault</h1>
              <p className="text-xs text-[#7A7E8F]">
                Autonomous yield · Sepolia
              </p>
            </div>
          </div>
          <ConnectButton />
        </header>

        {/* ── Stats Row ── */}
        <div className="mb-8 grid grid-cols-1 gap-6 sm:grid-cols-3">
          <StatCard
            label="Total Value Locked"
            value={fmt(totalDeposits as bigint | undefined)}
            unit="USDC"
            accent
          />
          <StatCard
            label="Your Shares"
            value={fmt(userShares as bigint | undefined)}
            unit="aiVLT"
          />
          <StatCard
            label="Time in Vault"
            value={timeInVault ? formatSeconds(timeInVault as bigint) : "—"}
          />
        </div>

        {/* ── Vault Action Panel ── */}
        {!mounted ? null : !!isConnected ? (
          <div className="mx-auto max-w-[480px]">
            <div className="rounded-2xl border border-white/[0.06] bg-[#14151A] overflow-hidden">
              {/* Tabs */}
              <div className="flex border-b border-white/[0.06]">
                {(["deposit", "withdraw"] as const).map((tab) => (
                  <button
                    key={tab}
                    onClick={() => setActiveTab(tab)}
                    className={`flex-1 py-3.5 text-sm font-medium capitalize transition-colors ${
                      activeTab === tab
                        ? "text-white border-b-2 border-[#2563EB]"
                        : "text-[#7A7E8F] hover:text-white/70"
                    }`}
                  >
                    {tab}
                  </button>
                ))}
              </div>

              {/* Panel Content */}
              <div className="p-6">
                {activeTab === "deposit" ? (
                  <>
                    <label className="mb-2 block text-xs font-medium text-[#7A7E8F] uppercase tracking-wide">
                      Amount
                    </label>
                    <div className="relative mb-5">
                      <input
                        type="number"
                        placeholder="0.00"
                        value={depositAmount}
                        onChange={(e) => setDepositAmount(e.target.value)}
                        className="w-full rounded-xl border border-white/[0.06] bg-[#0B0C10] px-4 py-3.5 pr-20 text-lg font-medium text-white placeholder-[#3A3D4A] outline-none transition focus:border-[#2563EB]/40 focus:ring-1 focus:ring-[#2563EB]/20"
                      />
                      <span className="absolute right-4 top-1/2 -translate-y-1/2 text-sm font-medium text-[#7A7E8F]">
                        USDC
                      </span>
                    </div>

                    {/* Step indicator */}
                    {depositStep && (
                      <div className="mb-4 flex items-center gap-2 rounded-lg bg-blue-500/5 border border-blue-500/10 px-3 py-2">
                        <div className="flex gap-1.5">
                          <div
                            className={`h-1.5 w-6 rounded-full transition-colors ${depositStep === "approve" ? "bg-blue-500 animate-pulse" : "bg-blue-500"}`}
                          />
                          <div
                            className={`h-1.5 w-6 rounded-full transition-colors ${depositStep === "deposit" ? "bg-blue-500 animate-pulse" : "bg-[#3A3D4A]"}`}
                          />
                        </div>
                        <span className="text-xs text-blue-400">
                          Step{" "}
                          {depositStep === "approve"
                            ? "1/2 · Approve"
                            : "2/2 · Deposit"}
                        </span>
                      </div>
                    )}

                    <button
                      onClick={handleDeposit}
                      disabled={isDepositing || !depositAmount}
                      className="w-full rounded-xl bg-[#2563EB] py-3.5 text-sm font-semibold text-white transition-all hover:bg-[#1D4ED8] disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      {isDepositing && (
                        <svg
                          className="mr-2 inline h-4 w-4 animate-spin"
                          viewBox="0 0 24 24"
                          fill="none"
                        >
                          <circle
                            className="opacity-25"
                            cx="12"
                            cy="12"
                            r="10"
                            stroke="currentColor"
                            strokeWidth="3"
                          />
                          <path
                            className="opacity-75"
                            fill="currentColor"
                            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                          />
                        </svg>
                      )}
                      {depositButtonLabel}
                    </button>
                  </>
                ) : (
                  <>
                    <label className="mb-2 block text-xs font-medium text-[#7A7E8F] uppercase tracking-wide">
                      Amount
                    </label>
                    <div className="relative mb-5">
                      <input
                        type="number"
                        placeholder="0.00"
                        value={withdrawAmount}
                        onChange={(e) => setWithdrawAmount(e.target.value)}
                        className="w-full rounded-xl border border-white/[0.06] bg-[#0B0C10] px-4 py-3.5 pr-20 text-lg font-medium text-white placeholder-[#3A3D4A] outline-none transition focus:border-red-500/40 focus:ring-1 focus:ring-red-500/20"
                      />
                      <span className="absolute right-4 top-1/2 -translate-y-1/2 text-sm font-medium text-[#7A7E8F]">
                        USDC
                      </span>
                    </div>

                    {!!userShares && (
                      <p className="mb-4 text-xs text-[#7A7E8F]">
                        Available:{" "}
                        <span className="text-white">
                          {fmt(userShares as bigint)}
                        </span>{" "}
                        aiVLT
                      </p>
                    )}

                    <button
                      onClick={handleWithdraw}
                      disabled={isWithdrawing || !withdrawAmount}
                      className="w-full rounded-xl bg-[#DC2626] py-3.5 text-sm font-semibold text-white transition-all hover:bg-[#B91C1C] disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      {isWithdrawing && (
                        <svg
                          className="mr-2 inline h-4 w-4 animate-spin"
                          viewBox="0 0 24 24"
                          fill="none"
                        >
                          <circle
                            className="opacity-25"
                            cx="12"
                            cy="12"
                            r="10"
                            stroke="currentColor"
                            strokeWidth="3"
                          />
                          <path
                            className="opacity-75"
                            fill="currentColor"
                            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                          />
                        </svg>
                      )}
                      {withdrawButtonLabel}
                    </button>
                  </>
                )}
              </div>
            </div>

            {/* Protocol info */}
            <div className="mt-4 rounded-xl border border-white/[0.04] bg-[#14151A]/50 px-5 py-4">
              <div className="flex justify-between text-xs text-[#7A7E8F]">
                <span>Vault Standard</span>
                <span className="text-white/60">ERC-4626</span>
              </div>
              <div className="mt-2 flex justify-between text-xs text-[#7A7E8F]">
                <span>Network</span>
                <span className="text-white/60">Sepolia Testnet</span>
              </div>
              <div className="mt-2 flex justify-between text-xs text-[#7A7E8F]">
                <span>Share Token</span>
                <span className="text-white/60">aiVLT</span>
              </div>
            </div>
          </div>
        ) : (
          <div className="mx-auto max-w-[480px] rounded-2xl border border-white/[0.06] bg-[#14151A] p-12 text-center">
            <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-[#2563EB]/10">
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#2563EB"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                <path d="M7 11V7a5 5 0 0110 0v4" />
              </svg>
            </div>
            <p className="text-sm text-[#7A7E8F]">
              Connect your wallet to interact with the vault
            </p>
          </div>
        )}
      </div>

      {/* ── Transaction Toasts ── */}
      <TxToast
        show={isTxPending}
        message={isDepositing ? "Transaction pending…" : "Transaction pending…"}
        type="pending"
        onClose={() => {}}
      />
      <TxToast
        show={toastVisible && !isTxPending}
        message={toastMsg}
        type="success"
        onClose={() => setToastVisible(false)}
      />
    </main>
  );
}
