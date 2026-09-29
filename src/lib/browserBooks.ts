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
