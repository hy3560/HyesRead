export type BookAddedAt = Record<string, number>;

export function mergeBookAddedAt(current: BookAddedAt, paths: string[], now = Date.now()): BookAddedAt {
  const addedAt: BookAddedAt = {};
  let latest = now;
  for (const [path, timestamp] of Object.entries(current)) {
    if (Number.isFinite(timestamp) && timestamp >= 0) {
      addedAt[path] = timestamp;
      latest = Math.max(latest, timestamp);
    }
  }
  for (const path of paths) {
    if (typeof path === "string" && path && !Object.hasOwn(addedAt, path)) {
      latest += 1;
      addedAt[path] = latest;
    }
  }
  return addedAt;
}

export function removeBookAddedAt(current: BookAddedAt, path: string): BookAddedAt {
  const next = { ...current };
  delete next[path];
  return next;
}
