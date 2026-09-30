import type { BookAddedAt } from "./bookOrder";

const READER_PATH_PREFIXES = ["hyes-reader-location:", "hyes-bookmarks:", "hyes-highlights:", "hyesread:"];

export type PortableBackupData = {
  master: {
    discreteFiles: string[];
    excludedFiles: string[];
    lastOpenedBook: string;
    bookAddedAt: BookAddedAt;
  };
  sessions: { date: string; duration: number; bookPath: string }[];
  readerData: Record<string, string>;
};

export function remapBackupPaths(backup: PortableBackupData, mappings: [string, string][]): PortableBackupData {
  const pathMapping = new Map(mappings);
  const remapPath = (path: string) => pathMapping.get(path) || path;
  const readerData: Record<string, string> = {};
  for (const [key, value] of Object.entries(backup.readerData)) {
    const prefix = READER_PATH_PREFIXES.find(item => key.startsWith(item));
    readerData[prefix ? `${prefix}${remapPath(key.slice(prefix.length))}` : key] = value;
  }
  return {
    master: {
      ...backup.master,
      discreteFiles: backup.master.discreteFiles.map(remapPath),
      excludedFiles: backup.master.excludedFiles.map(remapPath),
      lastOpenedBook: remapPath(backup.master.lastOpenedBook),
      bookAddedAt: Object.fromEntries(Object.entries(backup.master.bookAddedAt).map(([path, addedAt]) => [remapPath(path), addedAt])),
    },
    sessions: backup.sessions.map(session => ({ ...session, bookPath: remapPath(session.bookPath) })),
    readerData,
  };
}
