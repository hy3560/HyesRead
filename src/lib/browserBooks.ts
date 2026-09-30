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

export async function saveBrowserBooks(books: { id: string; name: string; type: string; data: string }[]) {
  if (!books.length) return;
  const database = await openDatabase();
  await new Promise<void>((resolve, reject) => {
    const transaction = database.transaction(STORE, "readwrite");
    let settled = false;
    const fail = (error: DOMException | Error | null) => {
      if (settled) return;
      settled = true;
      database.close();
      reject(error || new Error("无法保存书籍文件"));
    };
    transaction.oncomplete = () => {
      if (settled) return;
      settled = true;
      database.close();
      resolve();
    };
    transaction.onerror = () => fail(transaction.error);
    transaction.onabort = () => fail(transaction.error);
    try {
      const store = transaction.objectStore(STORE);
      for (const book of books) {
        const binary = atob(book.data);
        const bytes = new Uint8Array(binary.length);
        for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
        const content = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
        store.put(new File([content], book.name, { type: book.type }), book.id);
      }
    } catch (error) {
      try { transaction.abort(); } catch {}
      fail(error instanceof Error ? error : new Error(String(error)));
    }
  });
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
