"use client";

import { readValue, writeValue } from "./platform";

const SYSTEM_STORE = "hyes_system.json";
export const CURRENT_DATA_SCHEMA_VERSION = 1;

export type DataSchemaState = {
  version: number;
  migratedAt: string;
};

function dedupeStrings(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return Array.from(new Set(value.filter((item): item is string => typeof item === "string" && item.length > 0)));
}

function normalizeTimestamps(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const normalized: Record<string, number> = {};
  for (const [path, timestamp] of Object.entries(value as Record<string, unknown>)) {
    if (path.length > 0 && typeof timestamp === "number" && Number.isFinite(timestamp) && timestamp >= 0) normalized[path] = timestamp;
  }
  return normalized;
}

export async function ensureDataSchema(): Promise<DataSchemaState> {
  const version = await readValue<number>(SYSTEM_STORE, "schema_version", 0);
  if (!Number.isInteger(version) || version < 0) throw new Error("本地数据版本信息无效");
  if (version > CURRENT_DATA_SCHEMA_VERSION) {
    throw new Error(`本地数据由更高版本 HyesRead 创建（schema ${version}），当前版本仅支持到 ${CURRENT_DATA_SCHEMA_VERSION}`);
  }

  let current = version;
  if (current < 1) {
    const [discreteFiles, excludedFiles, bookAddedAt] = await Promise.all([
      readValue<unknown>("hyes_master.json", "discrete_files", []),
      readValue<unknown>("hyes_master.json", "excluded_files", []),
      readValue<unknown>("hyes_master.json", "book_added_at", {}),
    ]);
    await writeValue("hyes_master.json", "discrete_files", dedupeStrings(discreteFiles));
    await writeValue("hyes_master.json", "excluded_files", dedupeStrings(excludedFiles));
    await writeValue("hyes_master.json", "book_added_at", normalizeTimestamps(bookAddedAt));
    current = 1;
    await writeValue(SYSTEM_STORE, "schema_version", current);
  }

  const migratedAt = new Date().toISOString();
  await writeValue(SYSTEM_STORE, "last_schema_check", migratedAt);
  return { version: current, migratedAt };
}

export async function readDataSchemaVersion() {
  return readValue<number>(SYSTEM_STORE, "schema_version", 0);
}
