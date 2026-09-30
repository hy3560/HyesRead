"use client";

import { invoke as tauriInvoke, isTauri } from "@tauri-apps/api/core";
import { load } from "@tauri-apps/plugin-store";

export async function readValue<T>(file: string, key: string, fallback: T): Promise<T> {
  if (isTauri()) {
    const store = await load(file);
    return (await store.get<T>(key)) ?? fallback;
  }
  const data = JSON.parse(localStorage.getItem(`hyes:${file}`) || "{}");
  return data[key] ?? fallback;
}

export async function writeValue<T>(file: string, key: string, value: T): Promise<void> {
  if (isTauri()) {
    const store = await load(file);
    await store.set(key, value);
    await store.save();
    return;
  }
  const data = JSON.parse(localStorage.getItem(`hyes:${file}`) || "{}");
  localStorage.setItem(`hyes:${file}`, JSON.stringify({ ...data, [key]: value }));
}

const updateQueues = new Map<string, Promise<unknown>>();

export async function updateValue<T>(file: string, key: string, fallback: T, update: (current: T) => T): Promise<T> {
  const queueKey = `${file}:${key}`;
  const previous = updateQueues.get(queueKey) ?? Promise.resolve();
  const operation = previous.catch(() => undefined).then(async () => {
    if (isTauri()) {
      const store = await load(file);
      const current = (await store.get<T>(key)) ?? fallback;
      const next = update(current);
      await store.set(key, next);
      await store.save();
      return next;
    }

    const storageKey = `hyes:${file}`;
    const data = JSON.parse(localStorage.getItem(storageKey) || "{}");
    const next = update((data[key] as T | undefined) ?? fallback);
    localStorage.setItem(storageKey, JSON.stringify({ ...data, [key]: next }));
    return next;
  });
  updateQueues.set(queueKey, operation);
  try {
    return await operation;
  } finally {
    if (updateQueues.get(queueKey) === operation) updateQueues.delete(queueKey);
  }
}

export async function invoke<T>(command: string, args: Record<string, unknown> = {}): Promise<T> {
  if (!isTauri()) throw new Error("此操作需要 HyesRead 桌面版");
  return tauriInvoke<T>(command, args);
}

export function isMobileUserAgent(userAgent: string) {
  return /Android|iPhone|iPad|iPod/i.test(userAgent);
}

export function isDesktop() {
  const userAgent = typeof navigator === "undefined" ? "" : navigator.userAgent;
  return isTauri() && !isMobileUserAgent(userAgent);
}
