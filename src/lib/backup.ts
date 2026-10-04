import { invoke, readValue, updateValue, writeValue } from "./platform";
import type { BookAddedAt } from "./bookOrder";
import { mapBookPaths } from "./bookPaths";
import { remapBackupPaths } from "./backupPaths";
import { isBrowserBook, listBrowserBooks, saveBrowserBooks } from "./browserBooks";

const FORMAT = "hyesread-backup";
const VERSION = 2;
const LEGACY_VERSIONS = new Set([1, VERSION]);
const MAX_BACKUP_BYTES = 2 * 1024 * 1024 * 1024;
const READER_KEY_PREFIXES = ["hyes-reader-location:", "hyes-bookmarks:", "hyes-highlights:", "hyesread:"];

type ReadingSession = { date: string; duration: number; bookPath: string };
type CatalogSource = { name: string; url: string };
type BrowserBookBackup = { id: string; name: string; type: string; data: string; sha256?: string };
type BackupIntegrity = { algorithm: "SHA-256"; manifestSha256: string };

type BackupFile = {
  format: typeof FORMAT;
  version: number;
  exportedAt: string;
  master: { libraryPath: string; discreteFiles: string[]; excludedFiles: string[]; lastOpenedBook: string; bookAddedAt: BookAddedAt };
  sessions: ReadingSession[];
  catalogs: CatalogSource[];
  readerData: Record<string, string>;
  browserBooks?: BrowserBookBackup[];
  integrity?: BackupIntegrity;
};

type PortableBackupFile = BackupFile;

export type BackupRestoreResult = { bookPathMappings: [string, string][]; discoveredPaths: string[]; restoredBrowserPaths: string[] };

const isObject = (value: unknown): value is Record<string, unknown> => !!value && typeof value === "object" && !Array.isArray(value);
const strings = (value: unknown): string[] => Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
const timestamps = (value: unknown): BookAddedAt => isObject(value)
  ? Object.fromEntries(Object.entries(value).filter((entry): entry is [string, number] => typeof entry[0] === "string" && Number.isFinite(entry[1]) && Number(entry[1]) >= 0))
  : {};

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (!isObject(value)) return value;
  return Object.fromEntries(
    Object.keys(value)
      .filter(key => value[key] !== undefined)
      .sort()
      .map(key => [key, canonicalize(value[key])]),
  );
}

function backupManifest(backup: BackupFile) {
  return {
    format: backup.format,
    version: backup.version,
    exportedAt: backup.exportedAt,
    master: backup.master,
    sessions: backup.sessions,
    catalogs: backup.catalogs,
    readerData: backup.readerData,
    browserBooks: (backup.browserBooks || []).map(book => ({
      id: book.id,
      name: book.name,
      type: book.type,
      sha256: book.sha256 || "",
    })),
  };
}

async function manifestSha256(backup: BackupFile) {
  const encoded = new TextEncoder().encode(JSON.stringify(canonicalize(backupManifest(backup))));
  return sha256(encoded);
}

function catalogForBackup(source: CatalogSource): CatalogSource {
  try {
    const url = new URL(source.url);
    url.username = "";
    url.password = "";
    return { ...source, url: url.toString() };
  } catch {
    return source;
  }
}

export async function createBackup(): Promise<PortableBackupFile> {
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

  const backup: PortableBackupFile = {
    format: FORMAT,
    version: VERSION,
    exportedAt: new Date().toISOString(),
    master: { libraryPath, discreteFiles, excludedFiles, lastOpenedBook, bookAddedAt },
    sessions,
    catalogs: catalogs.map(catalogForBackup),
    readerData,
  };
  const files = await listBrowserBooks(discreteFiles);
  const estimatedBytes = new TextEncoder().encode(JSON.stringify(backup)).byteLength
    + files.reduce((total, { file }) => total + 4 * Math.ceil(file.size / 3) + file.name.length + file.type.length + 256, 0);
  if (estimatedBytes > MAX_BACKUP_BYTES) throw new Error("备份文件超过 2 GB 限制");
  backup.browserBooks = [];
  for (const { id, file } of files) {
    const data = await blobToBase64(file);
    backup.browserBooks.push({ id, name: file.name, type: file.type, data, sha256: await sha256(base64ToBytes(data)) });
  }
  backup.integrity = { algorithm: "SHA-256", manifestSha256: await manifestSha256(backup) };
  return backup;
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",", 2)[1] || "");
    reader.onerror = () => reject(reader.error || new Error("读取书籍文件失败"));
    reader.readAsDataURL(blob);
  });
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

function parseBackup(value: unknown): BackupFile {
  if (!isObject(value) || value.format !== FORMAT || typeof value.version !== "number" || !LEGACY_VERSIONS.has(value.version)) {
    throw new Error("备份文件格式或版本不受支持");
  }
  const version = value.version;
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
  const browserBooks = value.browserBooks === undefined ? [] : value.browserBooks;
  if (!Array.isArray(browserBooks) || !browserBooks.every(item => isObject(item)
    && typeof item.id === "string" && isBrowserBook(item.id)
    && typeof item.name === "string" && typeof item.type === "string" && typeof item.data === "string"
    && (version === 1
      ? item.sha256 === undefined || (typeof item.sha256 === "string" && /^[a-f0-9]{64}$/i.test(item.sha256))
      : typeof item.sha256 === "string" && /^[a-f0-9]{64}$/i.test(item.sha256)))) {
    throw new Error("备份中的书籍文件格式无效");
  }
  let integrity: BackupIntegrity | undefined;
  if (version >= 2) {
    if (!isObject(value.integrity)
      || value.integrity.algorithm !== "SHA-256"
      || typeof value.integrity.manifestSha256 !== "string"
      || !/^[a-f0-9]{64}$/i.test(value.integrity.manifestSha256)) {
      throw new Error("备份完整性信息缺失或无效");
    }
    integrity = { algorithm: "SHA-256", manifestSha256: value.integrity.manifestSha256.toLowerCase() };
  }
  const ids = new Set<string>();
  for (const item of browserBooks) {
    if (ids.has(item.id as string)) throw new Error("备份中包含重复的书籍文件");
    if (!strings(value.master.discreteFiles).includes(item.id as string)) throw new Error("备份中的书籍文件没有对应的书架记录");
    try {
      const bytes = base64ToBytes(item.data as string);
      if (bytes.byteLength > MAX_BACKUP_BYTES) throw new Error("备份文件超过 2 GB 限制");
    } catch (error) {
      if (error instanceof Error && error.message.includes("2 GB")) throw error;
      throw new Error("备份中的书籍文件已损坏");
    }
    ids.add(item.id as string);
  }
  return {
    format: FORMAT,
    version,
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
    browserBooks: browserBooks as PortableBackupFile["browserBooks"],
    integrity,
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

function mapLibraryPaths(backup: BackupFile, libraryPath: string, discoveredPaths: string[]): [string, string][] {
  const sourcePaths = new Set<string>([
    ...backup.master.discreteFiles,
    ...backup.sessions.map(session => session.bookPath),
    ...Object.keys(backup.readerData).flatMap(key => {
      const prefix = READER_KEY_PREFIXES.find(item => key.startsWith(item));
      return prefix ? [key.slice(prefix.length)] : [];
    }),
  ]);
  return mapBookPaths(backup.master.libraryPath, libraryPath, Array.from(sourcePaths), discoveredPaths);
}

export async function restoreBackup(text: string, selectedLibraryPath = ""): Promise<BackupRestoreResult> {
  if (new TextEncoder().encode(text).byteLength > MAX_BACKUP_BYTES) throw new Error("备份文件超过 2 GB 限制");
  let parsed: unknown;
  try { parsed = JSON.parse(text); } catch { throw new Error("无法解析备份文件"); }
  const backup = parseBackup(parsed);
  if (backup.version >= 2) {
    const expectedManifest = backup.integrity?.manifestSha256;
    const actualManifest = await manifestSha256(backup);
    if (!expectedManifest || actualManifest !== expectedManifest) throw new Error("备份清单校验失败，文件可能已损坏或被修改");
  }
  const totalBookBytes = (backup.browserBooks || []).reduce((total, book) => total + Math.floor(book.data.length * 3 / 4), 0);
  if (new TextEncoder().encode(text).byteLength + totalBookBytes > MAX_BACKUP_BYTES) throw new Error("备份文件超过 2 GB 限制");
  for (const book of backup.browserBooks || []) {
    if (!book.sha256) continue;
    if (await sha256(base64ToBytes(book.data)) !== book.sha256.toLowerCase()) throw new Error(`备份中的书籍文件校验失败：${book.name}`);
  }

  const currentLibraryPath = selectedLibraryPath || await readValue("hyes_master.json", "library_path", "");
  let discoveredPaths: string[] = [];
  if (currentLibraryPath) {
    try {
      const books = await invoke<{ path: string }[]>("scan_library", { folderPath: currentLibraryPath });
      discoveredPaths = books.map(book => book.path);
    } catch {
      // An inaccessible current library must not prevent restoring its other data.
    }
  }
  const bookPathMappings = mapLibraryPaths(backup, currentLibraryPath, discoveredPaths);
  const remappedBackup = remapBackupPaths(backup, bookPathMappings);

  const restoredBrowserPaths: string[] = [];
  await saveBrowserBooks(backup.browserBooks || []);
  restoredBrowserPaths.push(...(backup.browserBooks || []).map(book => book.id));

  const [existingDiscrete, existingExcluded] = await Promise.all([
    readValue<string[]>("hyes_master.json", "discrete_files", []),
    readValue<string[]>("hyes_master.json", "excluded_files", []),
  ]);
  const remappedDiscrete = [...remappedBackup.master.discreteFiles, ...restoredBrowserPaths];
  const mergedDiscrete = Array.from(new Set([...existingDiscrete, ...remappedDiscrete]));
  const remappedExcluded = remappedBackup.master.excludedFiles;
  const mergedExcluded = Array.from(new Set([...existingExcluded, ...remappedExcluded])).filter(path => !mergedDiscrete.includes(path));
  await writeValue("hyes_master.json", "discrete_files", mergedDiscrete);
  await writeValue("hyes_master.json", "excluded_files", mergedExcluded);
  const currentBookAddedAt = await readValue<BookAddedAt>("hyes_master.json", "book_added_at", {});
  await writeValue("hyes_master.json", "book_added_at", { ...timestamps(remappedBackup.master.bookAddedAt), ...timestamps(currentBookAddedAt) });
  await updateValue<ReadingSession[]>("hyes_stats.json", "sessions", [], current => mergeSessions(current, remappedBackup.sessions));
  await updateValue<CatalogSource[]>("hyes_catalogs.json", "sources", [], current => mergeCatalogs(current, backup.catalogs));
  if (!currentLibraryPath && backup.master.libraryPath) await writeValue("hyes_master.json", "library_path", backup.master.libraryPath);
  if (selectedLibraryPath) await writeValue("hyes_master.json", "library_path", selectedLibraryPath);
  const currentLastOpened = await readValue("hyes_master.json", "last_opened_book", "");
  if (!currentLastOpened && remappedBackup.master.lastOpenedBook) await writeValue("hyes_master.json", "last_opened_book", remappedBackup.master.lastOpenedBook);
  for (const [key, value] of Object.entries(remappedBackup.readerData)) mergeLocalValue(key, value);
  const visibleDiscoveredPaths = discoveredPaths.filter(path => !mergedExcluded.includes(path));
  return { bookPathMappings, discoveredPaths: visibleDiscoveredPaths, restoredBrowserPaths };
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
