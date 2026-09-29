"use client";

import { invoke as tauriInvoke, isTauri } from "@tauri-apps/api/core";
import { load } from "@tauri-apps/plugin-store";

export async function readValue<T>(file: string, key: string, fallback: T): Promise<T> {
  if (isTauri()) {
    try { const store = await load(file); return (await store.get<T>(key)) ?? fallback; } catch { /* browser fallback */ }
  }
  try { const data = JSON.parse(localStorage.getItem(`hyes:${file}`) || "{}"); return data[key] ?? fallback; } catch { return fallback; }
}

export async function writeValue<T>(file: string, key: string, value: T): Promise<void> {
  if (isTauri()) {
    try { const store = await load(file); await store.set(key, value); await store.save(); return; } catch { /* browser fallback */ }
  }
  const data = JSON.parse(localStorage.getItem(`hyes:${file}`) || "{}");
  localStorage.setItem(`hyes:${file}`, JSON.stringify({ ...data, [key]: value }));
}

export async function invoke<T>(command: string, args: Record<string, unknown> = {}): Promise<T> {
  if (!isTauri()) throw new Error("此操作需要 HyesRead 桌面版");
  return tauriInvoke<T>(command, args);
}

export function isDesktop() { return isTauri(); }
