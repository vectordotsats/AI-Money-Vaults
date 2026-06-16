import { appendFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname } from "node:path";
import { config } from "./config.js";

type Level = "INFO" | "WARN" | "ERROR" | "ACTION" | "DEBUG";

const COLORS: Record<Level, string> = {
  INFO: "\x1b[36m", // cyan
  WARN: "\x1b[33m", // yellow
  ERROR: "\x1b[31m", // red
  ACTION: "\x1b[32m", // green
  DEBUG: "\x1b[90m", // gray
};
const RESET = "\x1b[0m";

function ts(): string {
  return new Date().toISOString();
}

function emit(level: Level, msg: string, extra?: unknown) {
  const color = COLORS[level] ?? "";
  const line = `${color}[${ts()}] [${level}]${RESET} ${msg}`;
  // eslint-disable-next-line no-console
  console.log(line);
  if (extra !== undefined) {
    // eslint-disable-next-line no-console
    console.log(JSON.stringify(extra, null, 2));
  }
}

export const log = {
  info: (m: string, e?: unknown) => emit("INFO", m, e),
  warn: (m: string, e?: unknown) => emit("WARN", m, e),
  error: (m: string, e?: unknown) => emit("ERROR", m, e),
  action: (m: string, e?: unknown) => emit("ACTION", m, e),
  debug: (m: string, e?: unknown) => {
    if (process.env.DEBUG) emit("DEBUG", m, e);
  },
};

// ── JSON history: one record per cycle, persisted to disk ──
export interface HistoryRecord {
  ts: string;
  cycle: number;
  // snapshot (all human-readable USDC units as strings to avoid float drift)
  vaultIdleUsdc: string;
  vaultTotalAssetsUsdc: string;
  strategyDeployedUsdc: string;
  strategyIdleUsdc: string;
  accruedYieldUsdc: string;
  allocationPct: number;
  paused: boolean;
  // actions taken this cycle
  pushedToStrategyUsdc: string | null;
  suppliedToAaveUsdc: string | null;
  txHashes: string[];
  dryRun: boolean;
  note?: string;
}

export async function recordHistory(record: HistoryRecord): Promise<void> {
  const file = config.historyFile;
  try {
    await mkdir(dirname(file), { recursive: true });
    let records: HistoryRecord[] = [];
    if (existsSync(file)) {
      try {
        const raw = await readFile(file, "utf8");
        records = raw.trim() ? (JSON.parse(raw) as HistoryRecord[]) : [];
        if (!Array.isArray(records)) records = [];
      } catch {
        // corrupt history — back it up and start fresh rather than crash the bot
        await appendFile(`${file}.corrupt`, (await readFile(file, "utf8").catch(() => "")) + "\n");
        records = [];
      }
    }
    records.push(record);
    if (records.length > config.historyMaxRecords) {
      records = records.slice(records.length - config.historyMaxRecords);
    }
    await writeFile(file, JSON.stringify(records, null, 2));
  } catch (err) {
    log.warn(`Could not write history to ${file}: ${(err as Error).message}`);
  }
}
