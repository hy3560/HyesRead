"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { listen } from "@tauri-apps/api/event";
import { invoke, isDesktop, updateValue, writeValue } from "../lib/platform";
import { mergeBookAddedAt, type BookAddedAt } from "../lib/bookOrder";
import { ensureDataSchema } from "../lib/dataSchema";

interface ImportedBook {
  path: string;
}

export default function OpenFilesBridge() {
  const router = useRouter();
  const queue = useRef<Promise<void>>(Promise.resolve());

  useEffect(() => {
    if (!isDesktop()) return;
    let disposed = false;
    let unlisten: (() => void) | undefined;

    const enqueue = (paths: string[]) => {
      queue.current = queue.current
        .catch(() => undefined)
        .then(async () => {
          const uniquePaths = Array.from(new Set(paths.filter(path => path.trim().length > 0)));
          if (!uniquePaths.length) return;

          await ensureDataSchema();
          const books = await invoke<ImportedBook[]>("import_files", { filePaths: uniquePaths });
          if (!books.length) return;

          const importedPaths = books.map(book => book.path);
          await updateValue<string[]>("hyes_master.json", "discrete_files", [], existingPaths => Array.from(new Set([...existingPaths, ...importedPaths])));
          await updateValue<string[]>("hyes_master.json", "excluded_files", [], existingPaths => existingPaths.filter(path => !importedPaths.includes(path)));
          await updateValue<BookAddedAt>("hyes_master.json", "book_added_at", {}, existing => mergeBookAddedAt(existing, importedPaths));

          const book = books.find(candidate => candidate.path === uniquePaths[0]) ?? books[0];
          await invoke("prepare_book_read", { path: book.path });
          await writeValue("hyes_master.json", "last_opened_book", book.path);
          router.push(`/reader?path=${encodeURIComponent(book.path)}`);
        });
      return queue.current;
    };

    void (async () => {
      unlisten = await listen<string[]>("hyesread:open-files", event => {
        void enqueue(event.payload).catch(error => console.error("无法打开系统传入的书籍", error));
      });
      if (disposed) {
        unlisten();
        return;
      }

      const pendingPaths = await invoke<string[]>("take_open_files");
      if (!disposed && pendingPaths.length) await enqueue(pendingPaths);
    })().catch(error => console.error("系统书籍打开队列初始化失败", error));

    return () => {
      disposed = true;
      unlisten?.();
    };
  }, [router]);

  return null;
}
