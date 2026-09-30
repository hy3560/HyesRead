import { readValue, updateValue, writeValue } from "./platform";
import { mergeBookAddedAt, type BookAddedAt } from "./bookOrder";

const FORMAT = "hyesread-backup";
const VERSION = 1;
const MAX_IMPORT_BYTES = 50 * 1024 * 1024;
const READER_KEY_PREFIXES = ["hyes-reader-location:", "hyes-bookmarks:", "hyes-highlights:", "hyesread:"];

type ReadingSession = { date: string; duration: number; bookPath: string };
type CatalogSource = { name: string; url: string };
type BackupFile = {
  format: typeof FORMAT;
  version: number;
  exportedAt: string;
  master: { libraryPath: string; discreteFiles: string[]; excludedFiles: string[]; lastOpenedBook: string; bookAddedAt: BookAddedAt };
  sessions: ReadingSession[];
  catalogs: CatalogSource[];
  readerData: Record<string, string>;
};

const isObject = (value: unknown): value is Record<string, unknown> => !!value && typeof value === "object" && !Array.isArray(value);
const strings = (value: unknown): string[] => Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
const timestamps = (value: unknown): BookAddedAt => isObject(value)
  ? Object.fromEntries(Object.entries(value).filter((entry): entry is [string, number] => typeof entry[0] === "string" && Number.isFinite(entry[1]) && Number(entry[1]) >= 0))
  : {};

export async function createBackup(): Promise<BackupFile> {
  const [libraryPath, discreteFiles, excludedFiles, lastOpenedBook, bookAddedAt, sessions, catalogs] = await Promise.all([
    readValue("hyes_master.json", "library_path", ""),
    readValue<string[]>("hyes_master.json", "discrete_files", []),
    readValue<string[]>("hyes_master.json", "excluded_files", []),
    readValue("hyes_master.json", "last_opened_book", ""),
    readValue<BookAddedAt>("hyes_master.json", "book_added_at", {}),
    readValue<ReadingSession[]>("hyes_stats.json", "sessions", []),
    readValue<CatalogSource[]>("hyes_catalogs.json", "sources", []),
  ]);

  const readerData: Record<string, string> = {};
  for (let index = 0; index < localStorage.length; index += 1) {
    const key = localStorage.key(index);
    if (key && READER_KEY_PREFIXES.some(prefix => key.startsWith(prefix))) {
      const value = localStorage.getItem(key);
      if (value !== null) readerData[key] = value;
    }
  }

  return {
    format: FORMAT,
    version: VERSION,
    exportedAt: new Date().toISOString(),
    master: { libraryPath, discreteFiles, excludedFiles, lastOpenedBook, bookAddedAt },
    sessions,
    catalogs,
    readerData,
  };
}

function parseBackup(value: unknown): BackupFile {
  if (!isObject(value) || value.format !== FORMAT || value.version !== VERSION) {
    throw new Error("备份文件格式或版本不受支持");
  }
  if (!isObject(value.master) || !Array.isArray(value.sessions) || !Array.isArray(value.catalogs) || !isObject(value.readerData)) {
    throw new Error("备份文件内容不完整");
  }
  if (!value.sessions.every(item => isObject(item) && typeof item.date === "string" && typeof item.bookPath === "string" && Number.isFinite(item.duration) && Number(item.duration) >= 0)) {
    throw new Error("备份中的阅读统计格式无效");
  }
  if (!value.catalogs.every(item => isObject(item) && typeof item.url === "string" && typeof item.name === "string")) {
    throw new Error("备份中的目录来源格式无效");
  }
  const readerData: Record<string, string> = {};
  for (const [key, data] of Object.entries(value.readerData)) {
    if (!READER_KEY_PREFIXES.some(prefix => key.startsWith(prefix)) || typeof data !== "string") continue;
    try { JSON.parse(data); } catch { throw new Error(`备份中的阅读数据无效：${key}`); }
    readerData[key] = data;
  }
  return {
    format: FORMAT,
    version: VERSION,
    exportedAt: typeof value.exportedAt === "string" ? value.exportedAt : "",
    master: {
      libraryPath: typeof value.master.libraryPath === "string" ? value.master.libraryPath : "",
      discreteFiles: strings(value.master.discreteFiles),
      excludedFiles: strings(value.master.excludedFiles),
      lastOpenedBook: typeof value.master.lastOpenedBook === "string" ? value.master.lastOpenedBook : "",
      bookAddedAt: timestamps(value.master.bookAddedAt),
    },
    sessions: value.sessions as ReadingSession[],
    catalogs: value.catalogs as CatalogSource[],
    readerData,
  };
}

function mergeRecords<T extends { id: string; createdAt?: number }>(current: unknown, incoming: unknown): T[] {
  const merged = new Map<string, T>();
  for (const record of Array.isArray(current) ? current : []) {
    if (isObject(record) && typeof record.id === "string") merged.set(record.id, record as T);
  }
  for (const record of Array.isArray(incoming) ? incoming : []) {
    if (!isObject(record) || typeof record.id !== "string") continue;
    const existing = merged.get(record.id);
    if (!existing || (Number(record.createdAt) || 0) > (Number(existing.createdAt) || 0)) merged.set(record.id, record as T);
  }
  return Array.from(merged.values());
}

function mergeLocalValue(key: string, importedText: string) {
  const incoming = JSON.parse(importedText) as unknown;
  const currentText = localStorage.getItem(key);
  if (!currentText) {
    localStorage.setItem(key, importedText);
    return;
  }
  let current: unknown;
  try { current = JSON.parse(currentText); } catch {
    localStorage.setItem(key, importedText);
    return;
  }
  if (key.startsWith("hyes-bookmarks:") || key.startsWith("hyes-highlights:")) {
    localStorage.setItem(key, JSON.stringify(mergeRecords(current, incoming)));
  } else if (key.startsWith("hyes-reader-location:") || key.startsWith("hyesread:")) {
    // Existing progress and reader preferences are retained on import.
    return;
  } else if (key.startsWith("hyes:")) {
    if (!isObject(current) || !isObject(incoming)) return;
    const merged = { ...incoming, ...current };
    const allowedStoreKeys: Record<string, string[]> = {
      "hyes:hyes_master.json": ["discrete_files", "book_added_at"],
      "hyes:hyes_stats.json": ["sessions"],
      "hyes:hyes_catalogs.json": ["sources"],
    };
    for (const storeKey of allowedStoreKeys[key] || []) {
      if (storeKey === "discrete_files") merged[storeKey] = Array.from(new Set([...strings(incoming[storeKey]), ...strings(current[storeKey])]));
      if (storeKey === "book_added_at") merged[storeKey] = { ...timestamps(incoming[storeKey]), ...timestamps(current[storeKey]) };
      if (storeKey === "sessions") merged[storeKey] = mergeSessions(current[storeKey] as ReadingSession[], incoming[storeKey] as ReadingSession[]);
      if (storeKey === "sources") merged[storeKey] = mergeCatalogs(current[storeKey] as CatalogSource[], incoming[storeKey] as CatalogSource[]);
    }
    localStorage.setItem(key, JSON.stringify(merged));
  }
}

function mergeSessions(current: ReadingSession[] = [], incoming: ReadingSession[] = []) {
  const sessions = new Map<string, ReadingSession>();
  for (const session of [...(Array.isArray(incoming) ? incoming : []), ...(Array.isArray(current) ? current : [])]) {
    if (!session || typeof session.date !== "string" || typeof session.bookPath !== "string" || !Number.isFinite(session.duration)) continue;
    const key = `${session.date}\u0000${session.bookPath}`;
    const previous = sessions.get(key);
    if (!previous || session.duration > previous.duration) sessions.set(key, session);
  }
  return Array.from(sessions.values());
}

function mergeCatalogs(current: CatalogSource[] = [], incoming: CatalogSource[] = []) {
  const sources = new Map<string, CatalogSource>();
  for (const source of [...(Array.isArray(incoming) ? incoming : []), ...(Array.isArray(current) ? current : [])]) {
    if (source && typeof source.url === "string" && typeof source.name === "string") sources.set(source.url, source);
  }
  return Array.from(sources.values());
}

export async function restoreBackup(text: string): Promise<void> {
  if (new TextEncoder().encode(text).byteLength > MAX_IMPORT_BYTES) throw new Error("备份文件超过 50 MB 限制");
  let parsed: unknown;
  try { parsed = JSON.parse(text); } catch { throw new Error("无法解析备份文件"); }
  const backup = parseBackup(parsed);

  const [existingDiscrete, existingExcluded] = await Promise.all([
    readValue<string[]>("hyes_master.json", "discrete_files", []),
    readValue<string[]>("hyes_master.json", "excluded_files", []),
  ]);
  const mergedDiscrete = Array.from(new Set([...existingDiscrete, ...backup.master.discreteFiles]));
  const mergedExcluded = Array.from(new Set([...existingExcluded, ...backup.master.excludedFiles])).filter(path => !mergedDiscrete.includes(path));
  await writeValue("hyes_master.json", "discrete_files", mergedDiscrete);
  await writeValue("hyes_master.json", "excluded_files", mergedExcluded);
  const currentBookAddedAt = await readValue<BookAddedAt>("hyes_master.json", "book_added_at", {});
  await writeValue("hyes_master.json", "book_added_at", { ...timestamps(backup.master.bookAddedAt), ...timestamps(currentBookAddedAt) });
  await updateValue<ReadingSession[]>("hyes_stats.json", "sessions", [], current => mergeSessions(current, backup.sessions));
  await updateValue<CatalogSource[]>("hyes_catalogs.json", "sources", [], current => mergeCatalogs(current, backup.catalogs));
  const currentLibraryPath = await readValue("hyes_master.json", "library_path", "");
  if (!currentLibraryPath && backup.master.libraryPath) await writeValue("hyes_master.json", "library_path", backup.master.libraryPath);
  const currentLastOpened = await readValue("hyes_master.json", "last_opened_book", "");
  if (!currentLastOpened && backup.master.lastOpenedBook) await writeValue("hyes_master.json", "last_opened_book", backup.master.lastOpenedBook);
  for (const [key, value] of Object.entries(backup.readerData)) mergeLocalValue(key, value);
}

export function downloadBackup(backup: BackupFile) {
  const blob = new Blob([JSON.stringify(backup, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `hyesread-backup-${new Date().toISOString().slice(0, 10)}.json`;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 30_000);
}
