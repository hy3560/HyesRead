import { listen } from "@tauri-apps/api/event";
import { invoke } from "./platform";

export type ScanProgress<T> = { scanId: string; scanned: number; skipped: number; books: T[] };
export type ScanResult<T> = { books: T[]; scanned: number; skipped: number; cancelled: boolean; complete: boolean; warnings: string[] };
export type ScanBackend<T> = {
  subscribe: (callback: (progress: ScanProgress<T>) => void) => Promise<() => void>;
  start: (folderPath: string, scanId: string) => Promise<ScanResult<T>>;
  cancel: (scanId: string) => Promise<unknown>;
};

// Subscribe before starting so the first batch cannot be lost. Cancellation during
// subscription must never start a native task; listeners always leave with the task.
export async function runLibraryScan<T>(
  folderPath: string,
  signal: AbortSignal,
  onProgress: (progress: ScanProgress<T>) => void,
  backend: ScanBackend<T> = {
    subscribe: callback => listen<ScanProgress<T>>("hyesread:scan-progress", event => callback(event.payload)),
    start: (root, scanId) => invoke<ScanResult<T>>("scan_library_incremental", { folderPath: root, scanId }),
    cancel: scanId => invoke("cancel_library_scan", { scanId }),
  },
): Promise<ScanResult<T> | null> {
  if (signal.aborted) return null;
  const scanId = crypto.randomUUID();
  let cancellation: Promise<unknown> | undefined;
  const cancel = () => {
    cancellation = backend.cancel(scanId);
    void cancellation.catch(() => undefined);
  };
  const unsubscribe = await backend.subscribe(progress => {
    if (progress.scanId !== scanId) return;
    if (signal.aborted) { cancel(); return; }
    onProgress(progress);
  });
  if (signal.aborted) { unsubscribe(); return null; }
  signal.addEventListener("abort", cancel, { once: true });
  try {
    const result = await backend.start(folderPath, scanId);
    if (cancellation) await cancellation;
    return signal.aborted || result.cancelled ? null : result;
  } finally {
    signal.removeEventListener("abort", cancel);
    unsubscribe();
  }
}
