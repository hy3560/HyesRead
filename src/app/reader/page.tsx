"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { convertFileSrc } from "@tauri-apps/api/core";
import { invoke, isDesktop, updateValue, writeValue } from "../../lib/platform";
import { getBrowserBook, isBrowserBook } from "../../lib/browserBooks";

type ReaderLocation = { fraction: number; location?: number; href?: string; chapter?: string };
type Bookmark = { id: string; label: string; location: ReaderLocation; createdAt: number };

export default function ReaderPage() {
  return <Suspense fallback={<main className="h-screen bg-[#050505]" />}><ReaderContent /></Suspense>;
}

function ReaderContent() {
  const router = useRouter();
  const params = useSearchParams();
  const [error, setError] = useState("");
  const [bookTitle, setBookTitle] = useState("");
  const [readerReady, setReaderReady] = useState(false);
  const [currentLocation, setCurrentLocation] = useState<ReaderLocation | null>(null);
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([]);
  const [bookmarksOpen, setBookmarksOpen] = useState(false);
  const bookPath = params.get("path");

  useEffect(() => {
    const path = bookPath;
    setReaderReady(false);
    setBookmarksOpen(false);
    if (!path) {
      setError("缺少书籍路径");
      return;
    }
    let timer: ReturnType<typeof setInterval> | undefined;
    const frame = document.getElementById("foliate-reader") as HTMLIFrameElement | null;
    if (!frame) return;
    let onMessage: ((event: MessageEvent) => void) | undefined;
    let onLoad: (() => void) | undefined;
    let reportTime: (() => void) | undefined;
    const key = `hyes-reader-location:${path}`;
    const bookmarkKey = `hyes-bookmarks:${path}`;
    try {
      const stored = JSON.parse(localStorage.getItem(bookmarkKey) || "[]");
      setBookmarks(Array.isArray(stored) ? stored.filter((item): item is Bookmark => typeof item?.id === "string" && Number.isFinite(item?.location?.fraction) && item.location.fraction >= 0 && item.location.fraction <= 1) : []);
      const location = JSON.parse(localStorage.getItem(key) || "null");
      if (typeof location?.fraction === "number") setCurrentLocation(location);
    } catch {
      setBookmarks([]);
      setCurrentLocation(null);
    }
    let lastCheckAt = Date.now();
    let unrecordedMs = 0;
    let flushQueue = Promise.resolve();
    const flushReadingTime = (assumeVisible = false) => {
      const now = Date.now();
      if (assumeVisible || document.visibilityState === "visible") unrecordedMs += Math.max(0, now - lastCheckAt);
      lastCheckAt = now;
      const minutes = Math.floor(unrecordedMs / 60_000);
      if (minutes < 1) return;
      unrecordedMs -= minutes * 60_000;
      flushQueue = flushQueue.then(async () => {
          const date = new Date();
          const day = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
          await updateValue<{ date: string; duration: number; bookPath: string }[]>("hyes_stats.json", "sessions", [], sessions => {
            const last = sessions[sessions.length - 1];
            if (last?.date === day && last.bookPath === path) last.duration += minutes;
            else sessions.push({ date: day, duration: minutes, bookPath: path });
            return sessions;
          });
        }).catch(error => {
          unrecordedMs += minutes * 60_000;
          console.error("保存阅读时长失败", error);
        });
    };
    reportTime = () => flushReadingTime();
    const handleVisibilityChange = () => {
      const wasVisible = document.visibilityState === "hidden";
      flushReadingTime(wasVisible);
    };
    document.addEventListener("visibilitychange", handleVisibilityChange);
    window.addEventListener("pagehide", reportTime);
    timer = setInterval(reportTime, 60_000);
    let cancelled = false;
    void (async () => {
    const browserBook = isBrowserBook(path) ? await getBrowserBook(path) : undefined;
    if (cancelled) return;
    if (isBrowserBook(path) && !browserBook) { setError("这本书在浏览器中已不可用，请重新添加文件。"); return; }
    setBookTitle(browserBook?.name || path.split(/[\\/]/).pop() || "");
    const ext = (browserBook?.name || path).split(".").pop()?.toLowerCase();
    if (ext === "txt" || ext === "md") {
      const loadText = async () => {
        try {
          const text = isDesktop()
            ? await invoke<string>("read_text_book", { path })
            : browserBook ? await browserBook.text() : await fetch(path).then(response => response.text());
          frame.addEventListener("load", () => {
            const article = frame.contentDocument?.querySelector("article");
            const textWindow = frame.contentWindow;
            if (!article || !textWindow) return;
            article.replaceChildren(document.createTextNode(text));
            const saved = localStorage.getItem(key);
            if (saved) textWindow.scrollTo(0, Math.max(0, Number(JSON.parse(saved).fraction) || 0) * (textWindow.document.documentElement.scrollHeight - textWindow.innerHeight));
            textWindow.addEventListener("scroll", () => {
              const maxScroll = textWindow.document.documentElement.scrollHeight - textWindow.innerHeight;
              localStorage.setItem(key, JSON.stringify({ fraction: maxScroll > 0 ? textWindow.scrollY / maxScroll : 0 }));
            }, { passive: true });
          }, { once: true });
          frame.srcdoc = `<meta charset="utf-8"><style>body{max-width:46rem;margin:4rem auto;padding:0 2rem;color:#27272a;font:18px/1.9 system-ui;white-space:pre-wrap;overflow-wrap:anywhere}</style><article></article>`;
        } catch (e) { setError(`无法读取文本：${e}`); }
      };
      void loadText();
      return;
    }
    const source = new URL("assets/web_reader/foliate-js/reader.html", document.baseURI);
    if (isDesktop()) source.searchParams.set("url", convertFileSrc(path));
    onMessage = (event: MessageEvent) => {
      if (event.source !== frame.contentWindow) return;
      if (event.data?.type === "hyesread:relocate") {
        try {
          localStorage.setItem(key, JSON.stringify(event.data.location));
          setCurrentLocation(event.data.location);
        } catch (e) {
          setError(`无法保存阅读位置：${e}`);
        }
      } else if (event.data?.type === "hyesread:ready") {
        setReaderReady(true);
        let saved = null;
        try { saved = JSON.parse(localStorage.getItem(key) || "null"); } catch { saved = null; }
        frame.contentWindow?.postMessage({ type: "hyesread:restore", location: saved }, "*");
      } else if (event.data?.type === "hyesread:error") {
        setError(`无法打开这本书：${event.data.message || "文件格式或内容无效"}`);
      }
    };
    window.addEventListener("message", onMessage);
    onLoad = () => {
      let saved = null;
      try { saved = JSON.parse(localStorage.getItem(key) || "null"); } catch { saved = null; }
      frame.contentWindow?.postMessage({ type: "hyesread:restore", location: saved }, "*");
      if (browserBook) frame.contentWindow?.postMessage({ type: "hyesread:open-file", file: browserBook }, "*");
    };
    frame.addEventListener("load", onLoad);
    frame.src = source.toString();
    })().catch(e => setError(`无法打开这本书：${e}`));

    return () => {
      cancelled = true;
      flushReadingTime();
      if (timer) clearInterval(timer);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      if (onMessage) window.removeEventListener("message", onMessage);
      if (reportTime) window.removeEventListener("pagehide", reportTime);
      if (onLoad) frame.removeEventListener("load", onLoad);
    };
  }, [bookPath]);

  const addBookmark = () => {
    if (!bookPath || !currentLocation) return;
    const existing = bookmarks.find(mark => mark.location.href === currentLocation.href && Math.abs(mark.location.fraction - currentLocation.fraction) < 0.003);
    const next = existing ? bookmarks.filter(mark => mark.id !== existing.id) : [
      { id: crypto.randomUUID(), label: currentLocation.chapter || `${Math.round(currentLocation.fraction * 100)}%`, location: currentLocation, createdAt: Date.now() },
      ...bookmarks,
    ].slice(0, 500);
    try {
      localStorage.setItem(`hyes-bookmarks:${bookPath}`, JSON.stringify(next));
      setBookmarks(next);
    } catch (e) {
      setError(`无法保存书签：${e}`);
    }
  };

  const goToBookmark = (bookmark: Bookmark) => {
    (document.getElementById("foliate-reader") as HTMLIFrameElement | null)?.contentWindow?.postMessage({ type: "hyesread:restore", location: bookmark.location }, "*");
    setBookmarksOpen(false);
  };

  return (
    <main className="h-screen w-screen bg-[#050505] text-zinc-100 flex flex-col">
      <header className="relative h-14 shrink-0 border-b border-white/10 flex items-center gap-3 px-5 max-[640px]:gap-1 max-[640px]:px-2">
        <button onClick={() => router.back()} className="rounded-lg px-3 py-2 hover:bg-white/10">← 返回书库</button>
        <span className="min-w-0 flex-1 text-sm text-zinc-400 truncate">{bookTitle || bookPath?.split(/[\\/]/).pop()}</span>
        {readerReady && <button type="button" aria-label="搜索正文" onClick={() => (document.getElementById("foliate-reader") as HTMLIFrameElement | null)?.contentWindow?.postMessage({ type: "hyesread:toggle-search" }, "*")} className="rounded-lg px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 max-[640px]:px-2">搜索</button>}
        {readerReady && <button type="button" aria-label="阅读设置" onClick={() => (document.getElementById("foliate-reader") as HTMLIFrameElement | null)?.contentWindow?.postMessage({ type: "hyesread:toggle-settings" }, "*")} className="rounded-lg px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 max-[640px]:px-2">设置</button>}
        {readerReady && <button type="button" aria-label="添加或移除当前书签" onClick={addBookmark} disabled={!currentLocation} className="rounded-lg px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 disabled:opacity-40 max-[640px]:px-2">{bookmarks.some(mark => mark.location.href === currentLocation?.href && Math.abs(mark.location.fraction - (currentLocation?.fraction || 0)) < 0.003) ? "已标记" : "书签"}</button>}
        {readerReady && <button type="button" aria-label="打开书签列表" onClick={() => setBookmarksOpen(value => !value)} className="rounded-lg px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 max-[640px]:px-2">{bookmarks.length}</button>}
        {bookmarksOpen && <section aria-label="书签列表" className="absolute right-4 top-14 z-20 max-h-[65vh] w-80 overflow-auto rounded-xl border border-white/10 bg-[#141414] p-3 shadow-2xl max-[640px]:right-1 max-[640px]:w-[calc(100vw-8px)]">{bookmarks.length ? bookmarks.map(mark => <div key={mark.id} className="flex items-center gap-2 border-b border-white/5 py-1 last:border-0"><button type="button" onClick={() => goToBookmark(mark)} className="min-w-0 flex-1 truncate rounded-lg px-2 py-2 text-left text-sm text-zinc-200 hover:bg-white/10">{mark.label} · {Math.round(mark.location.fraction * 100)}%</button><button type="button" aria-label={`删除书签 ${mark.label}`} onClick={() => { const next = bookmarks.filter(item => item.id !== mark.id); try { localStorage.setItem(`hyes-bookmarks:${bookPath}`, JSON.stringify(next)); setBookmarks(next); } catch (e) { setError(`无法删除书签：${e}`); } }} className="px-2 py-2 text-zinc-500 hover:text-red-300">×</button></div>) : <div aria-hidden="true" className="h-10" />}</section>}
        {error && <span role="alert" className="text-red-400">{error}</span>}
      </header>
      <iframe id="foliate-reader" title="电子书阅读器" className="min-h-0 flex-1 border-0 bg-white" />
    </main>
  );
}
