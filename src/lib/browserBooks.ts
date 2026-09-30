const DATABASE = "hyesread-browser-books";
const STORE = "books";

function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(STORE);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function withBook<T>(mode: IDBTransactionMode, id: string, action: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const database = await openDatabase();
  return new Promise((resolve, reject) => {
    const transaction = database.transaction(STORE, mode);
    const request = action(transaction.objectStore(STORE));
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
    transaction.oncomplete = () => database.close();
    transaction.onerror = () => reject(transaction.error);
  });
}

export function isBrowserBook(path: string) { return path.startsWith("browser-book:"); }

export async function saveBrowserBook(id: string, file: File) {
  await withBook("readwrite", id, store => store.put(file, id));
}

export async function getBrowserBook(id: string): Promise<File | undefined> {
  return withBook("readonly", id, store => store.get(id));
}

export async function removeBrowserBook(id: string) {
  await withBook("readwrite", id, store => store.delete(id));
}

export async function listBrowserBooks(ids: string[]): Promise<{ id: string; file: File }[]> {
  const uniqueIds = Array.from(new Set(ids.filter(isBrowserBook)));
  const database = await openDatabase();
  return new Promise((resolve, reject) => {
    const transaction = database.transaction(STORE, "readonly");
    const store = transaction.objectStore(STORE);
    const result: { id: string; file: File }[] = [];
    let pending = uniqueIds.length;
    if (!pending) { database.close(); resolve(result); return; }
    for (const id of uniqueIds) {
      const request = store.get(id);
      request.onsuccess = () => {
        if (request.result instanceof Blob) result.push({ id, file: request.result instanceof File ? request.result : new File([request.result], id, { type: request.result.type }) });
        pending -= 1;
        if (!pending) { database.close(); resolve(result); }
      };
      request.onerror = () => { database.close(); reject(request.error); };
    }
    transaction.onerror = () => { database.close(); reject(transaction.error); };
  });
}
