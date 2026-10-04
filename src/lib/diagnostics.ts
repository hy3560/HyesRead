"use client";

import { isTauri } from "@tauri-apps/api/core";
import { invoke, isMobileUserAgent, readValue } from "./platform";
import { readDataSchemaVersion } from "./dataSchema";

export type DiagnosticLevel = "error" | "warn" | "info";

export type DiagnosticEvent = {
  timestamp: string;
  level: DiagnosticLevel;
  source: string;
  message: string;
};

type NativeDiagnosticInfo = {
  app_version: string;
  platform: string;
  arch: string;
  log_file: string;
};

export type DiagnosticReport = {
  format: "hyesread-diagnostics";
  version: 1;
  generatedAt: string;
  app: {
    version: string;
    runtime: "tauri" | "web";
    mobile: boolean;
    platform: string;
    arch: string;
  };
  storage: {
    schemaVersion: number;
    bookRecordCount: number;
    readingSessionCount: number;
    catalogCount: number;
    recentDiagnosticCount: number;
  };
  nativeLogFile: string;
  recentEvents: DiagnosticEvent[];
};

const STORAGE_KEY = "hyesread:diagnostics";
const MAX_EVENTS = 80;
const MAX_TEXT = 12_000;

export function sanitizeDiagnosticText(input: unknown): string {
  let text: string;
  if (input instanceof Error) {
    text = `${input.name}: ${input.message}${input.stack ? `\n${input.stack}` : ""}`;
  } else if (typeof input === "string") {
    text = input;
  } else {
    try {
      text = JSON.stringify(input) ?? String(input);
    } catch {
      text = String(input);
    }
  }

  return text
    .replace(/([a-z][a-z0-9+.-]*:\/\/)[^/\s:@]+:[^@\s/]+@/gi, "$1***:***@")
    .replace(/([A-Za-z]:\\Users\\)[^\\/\s]+/g, "$1***")
    .replace(/(\/Users\/|\/home\/)[^/\s]+/g, "$1***")
    .replace(/\u0000/g, "")
    .slice(0, MAX_TEXT);
}

function eventList(): DiagnosticEvent[] {
  if (typeof window === "undefined") return [];
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]");
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((item): item is DiagnosticEvent => !!item
      && typeof item.timestamp === "string"
      && ["error", "warn", "info"].includes(item.level)
      && typeof item.source === "string"
      && typeof item.message === "string").slice(-MAX_EVENTS);
  } catch {
    return [];
  }
}

function persistEvent(event: DiagnosticEvent) {
  try {
    const next = [...eventList(), event].slice(-MAX_EVENTS);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    // Diagnostics must never break the reader if browser storage is unavailable.
  }
}

export async function recordDiagnosticEvent(level: DiagnosticLevel, message: unknown, source = "app") {
  if (typeof window === "undefined") return;
  const event: DiagnosticEvent = {
    timestamp: new Date().toISOString(),
    level,
    source: sanitizeDiagnosticText(source).slice(0, 200),
    message: sanitizeDiagnosticText(message),
  };
  persistEvent(event);
  if (isTauri()) {
    try {
      await invoke<void>("report_client_event", { level: event.level, message: event.message, context: event.source });
    } catch {
      // Native logging is best-effort. The bounded browser-side ring buffer remains available.
    }
  }
}

function renderConsoleArgs(args: unknown[]) {
  return args.map(value => sanitizeDiagnosticText(value)).join(" ").slice(0, MAX_TEXT);
}

export function installGlobalDiagnostics() {
  if (typeof window === "undefined") return () => undefined;
  const originalConsoleError = console.error;
  const wrappedConsoleError = (...args: unknown[]) => {
    originalConsoleError(...args);
    void recordDiagnosticEvent("error", renderConsoleArgs(args), "console.error");
  };
  console.error = wrappedConsoleError;

  const onError = (event: ErrorEvent) => {
    const detail = event.error instanceof Error ? event.error : event.message;
    void recordDiagnosticEvent("error", detail, "window.error");
  };
  const onUnhandledRejection = (event: PromiseRejectionEvent) => {
    void recordDiagnosticEvent("error", event.reason, "unhandledrejection");
  };
  window.addEventListener("error", onError);
  window.addEventListener("unhandledrejection", onUnhandledRejection);

  return () => {
    if (console.error === wrappedConsoleError) console.error = originalConsoleError;
    window.removeEventListener("error", onError);
    window.removeEventListener("unhandledrejection", onUnhandledRejection);
  };
}

export async function createDiagnosticReport(): Promise<DiagnosticReport> {
  const [schemaVersion, bookRecords, sessions, catalogs] = await Promise.all([
    readDataSchemaVersion(),
    readValue<string[]>("hyes_master.json", "discrete_files", []),
    readValue<unknown[]>("hyes_stats.json", "sessions", []),
    readValue<unknown[]>("hyes_catalogs.json", "sources", []),
  ]);

  let nativeInfo: NativeDiagnosticInfo | null = null;
  if (isTauri()) {
    try {
      nativeInfo = await invoke<NativeDiagnosticInfo>("diagnostic_info");
    } catch (error) {
      await recordDiagnosticEvent("warn", error, "diagnostic_info");
    }
  }
  const recentEvents = eventList();
  const userAgent = typeof navigator === "undefined" ? "" : navigator.userAgent;

  return {
    format: "hyesread-diagnostics",
    version: 1,
    generatedAt: new Date().toISOString(),
    app: {
      version: nativeInfo?.app_version || process.env.NEXT_PUBLIC_APP_VERSION || "unknown",
      runtime: isTauri() ? "tauri" : "web",
      mobile: isMobileUserAgent(userAgent),
      platform: nativeInfo?.platform || "web",
      arch: nativeInfo?.arch || "unknown",
    },
    storage: {
      schemaVersion,
      bookRecordCount: Array.isArray(bookRecords) ? bookRecords.length : 0,
      readingSessionCount: Array.isArray(sessions) ? sessions.length : 0,
      catalogCount: Array.isArray(catalogs) ? catalogs.length : 0,
      recentDiagnosticCount: recentEvents.length,
    },
    nativeLogFile: sanitizeDiagnosticText(nativeInfo?.log_file || ""),
    recentEvents,
  };
}

export async function runSelfCheck() {
  const report = await createDiagnosticReport();
  return {
    report,
    summary: `书架记录 ${report.storage.bookRecordCount}，阅读记录 ${report.storage.readingSessionCount}，目录 ${report.storage.catalogCount}，近期诊断事件 ${report.storage.recentDiagnosticCount}。`,
  };
}

export function downloadDiagnosticReport(report: DiagnosticReport) {
  const blob = new Blob([JSON.stringify(report, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `hyesread-diagnostics-${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 30_000);
}
