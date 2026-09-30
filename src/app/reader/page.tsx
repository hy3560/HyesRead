"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { convertFileSrc } from "@tauri-apps/api/core";
import { invoke, isDesktop, updateValue, writeValue } from "../../lib/platform";
import { getBrowserBook, isBrowserBook } from "../../lib/browserBooks";

type ReaderLocation = { fraction: number; location?: number; href?: string; chapter?: string };
type Bookmark = { id: string; label: string; location: ReaderLocation; createdAt: number };
type Highlight = { id: string; value: string; text: string; note: string; color: string; createdAt: number };
type TextSelection = { value: string; text: string };
type TextSettings = { fontSize: number; spacing: number; theme: "light" | "sepia" | "dark" };

export default function ReaderPage() {
  return <Suspense fallback={<main className="h-screen bg-[#050505]" />}><ReaderContent /></Suspense>;
}

function ReaderContent() {
  const router = useRouter();
  const params = useSearchParams();
  const [error, setError] = useState("");
  const [bookTitle, setBookTitle] = useState("");
  const [readerReady, setReaderReady] = useState(false);
  const [textReady, setTextReady] = useState(false);
  const [textSettingsOpen, setTextSettingsOpen] = useState(false);
  const [textSettings, setTextSettings] = useState<TextSettings>({ fontSize: 18, spacing: 1.9, theme: "light" });
  const [currentLocation, setCurrentLocation] = useState<ReaderLocation | null>(null);
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([]);
  const [bookmarksOpen, setBookmarksOpen] = useState(false);
  const [highlights, setHighlights] = useState<Highlight[]>([]);
  const [pendingHighlights, setPendingHighlights] = useState<Set<string>>(() => new Set());
  const [selection, setSelection] = useState<TextSelection | null>(null);
  const [highlightsOpen, setHighlightsOpen] = useState(false);
  const bookPath = params.get("path");
  const currentFormat = (bookTitle || bookPath || "").split(".").pop()?.toLowerCase();
  const supportsTextSearch = ["epub", "mobi", "azw3", "kf8", "fb2", "fbz", "pdf"].includes(currentFormat || "");

  useEffect(() => {
    const path = bookPath;
    setReaderReady(false);
    setTextReady(false);
    setTextSettingsOpen(false);
    setBookmarksOpen(false);
    setHighlightsOpen(false);
    setPendingHighlights(new Set());
    setSelection(null);
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
    const highlightKey = `hyes-highlights:${path}`;
    try {
      const stored = JSON.parse(localStorage.getItem(bookmarkKey) || "[]");
      setBookmarks(Array.isArray(stored) ? stored.filter((item): item is Bookmark => typeof item?.id === "string" && Number.isFinite(item?.location?.fraction) && item.location.fraction >= 0 && item.location.fraction <= 1) : []);
      const savedHighlights = JSON.parse(localStorage.getItem(highlightKey) || "[]");
      setHighlights(Array.isArray(savedHighlights) ? savedHighlights.filter((item): item is Highlight => typeof item?.id === "string" && typeof item?.value === "string" && typeof item?.text === "string") : []);
      const location = JSON.parse(localStorage.getItem(key) || "null");
      if (typeof location?.fraction === "number") setCurrentLocation(location);
    } catch {
      setBookmarks([]);
      setCurrentLocation(null);
    }
    let lastCheckAt = 0;
    let isReading = false;
    let isVisible = document.visibilityState === "visible";
    const pendingReadingMs = new Map<string, number>();
    let flushQueue = Promise.resolve();
    const dateKey = (timestamp: number) => {
      const date = new Date(timestamp);
      return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
    };
    const collectReadingTime = (now: number) => {
      if (isReading && isVisible && lastCheckAt > 0 && now > lastCheckAt) {
        let cursor = lastCheckAt;
        while (cursor < now) {
          const nextDay = new Date(cursor);
          nextDay.setHours(24, 0, 0, 0);
          const segmentEnd = Math.min(now, nextDay.getTime());
          const day = dateKey(cursor);
          pendingReadingMs.set(day, (pendingReadingMs.get(day) || 0) + segmentEnd - cursor);
          cursor = segmentEnd;
        }
      }
      lastCheckAt = now;
    };
    const flushReadingTime = () => {
      const now = Date.now();
      collectReadingTime(now);
      if (!pendingReadingMs.size) return flushQueue;
      const pending = Array.from(pendingReadingMs);
      pendingReadingMs.clear();
      flushQueue = flushQueue.then(async () => {
          for (const [day, elapsedMs] of pending) {
            const minutes = Math.round((elapsedMs / 60_000) * 10_000) / 10_000;
            if (minutes <= 0) continue;
            await updateValue<{ date: string; duration: number; bookPath: string }[]>("hyes_stats.json", "sessions", [], sessions => {
              const existing = sessions.find(session => session.date === day && session.bookPath === path);
              if (existing) existing.duration += minutes;
              else sessions.push({ date: day, duration: minutes, bookPath: path });
              return sessions;
            });
          }
        }).catch(error => {
          for (const [day, elapsedMs] of pending) pendingReadingMs.set(day, (pendingReadingMs.get(day) || 0) + elapsedMs);
          console.error("保存阅读时长失败", error);
        });
      return flushQueue;
    };
    const startReadingTimer = () => {
      if (isReading) return;
      isReading = true;
      isVisible = document.visibilityState === "visible";
      lastCheckAt = Date.now();
      timer = setInterval(() => { void flushReadingTime(); }, 15_000);
    };
    reportTime = () => { void flushReadingTime(); };
    const handleVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        collectReadingTime(Date.now());
        isVisible = false;
      } else {
        lastCheckAt = Date.now();
        isVisible = true;
      }
      void flushReadingTime();
    };
    document.addEventListener("visibilitychange", handleVisibilityChange);
    window.addEventListener("pagehide", reportTime);
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
          const text = browserBook
            ? await browserBook.text()
            : isDesktop() ? await invoke<string>("read_text_book", { path }) : await fetch(path).then(response => response.text());
          frame.addEventListener("load", () => {
            const article = frame.contentDocument?.querySelector("article");
            const textWindow = frame.contentWindow;
            if (!article || !textWindow) return;
            article.replaceChildren(document.createTextNode(text));
            let restoredTextSettings: TextSettings = { fontSize: 18, spacing: 1.9, theme: "light" };
            try {
              const savedSettings = JSON.parse(localStorage.getItem("hyesread:reader-settings") || "{}");
              const style = savedSettings.style || {};
              restoredTextSettings = {
                fontSize: Number.isFinite(Number(style.fontSize)) ? Math.min(32, Math.max(14, Number(style.fontSize))) : 18,
                spacing: Number.isFinite(Number(style.spacing)) ? Math.min(2.2, Math.max(1.2, Number(style.spacing))) : 1.9,
                theme: ["light", "sepia", "dark"].includes(style.theme) ? style.theme : "light",
              };
            } catch {
              restoredTextSettings = { fontSize: 18, spacing: 1.9, theme: "light" };
            }
            setTextSettings(restoredTextSettings);
            const textThemes = { light: ["#fff", "#27272a"], sepia: ["#f4ecd8", "#433b30"], dark: ["#181818", "#d8d2c8"] } as const;
            const [background, color] = textThemes[restoredTextSettings.theme];
            Object.assign(textWindow.document.body.style, {
              background,
              color,
              fontSize: `${restoredTextSettings.fontSize}px`,
              lineHeight: String(restoredTextSettings.spacing),
            });
            const scrollElement = textWindow.document.scrollingElement || textWindow.document.documentElement;
            const maxScroll = () => Math.max(0, scrollElement.scrollHeight - textWindow.innerHeight);
            const reportLocation = () => {
              const fraction = maxScroll() ? scrollElement.scrollTop / maxScroll() : 0;
              try { localStorage.setItem(key, JSON.stringify({ fraction })); } catch (e) { setError(`无法保存阅读位置：${e}`); }
              setCurrentLocation({ fraction });
            };
            const saved = localStorage.getItem(key);
            if (saved) textWindow.scrollTo(0, Math.max(0, Number(JSON.parse(saved).fraction) || 0) * maxScroll());
            textWindow.document.addEventListener("scroll", () => {
              reportLocation();
            }, { passive: true });
            reportLocation();
            setTextReady(true);
            startReadingTimer();
          }, { once: true });
          frame.srcdoc = `<meta charset="utf-8"><style>html,body{height:100%;margin:0}body{box-sizing:border-box;max-width:46rem;margin:0 auto;padding:3rem 2rem 5rem;color:#27272a;background:#fff;font:18px/1.9 system-ui;white-space:pre-wrap;overflow-wrap:anywhere;overflow-y:auto}article{min-height:100%}</style><article></article>`;
        } catch (e) { setError(`无法读取文本：${e}`); }
      };
      void loadText();
      return;
    }
    const source = new URL("assets/web_reader/foliate-js/reader.html", document.baseURI);
    if (isDesktop() && !browserBook) source.searchParams.set("url", convertFileSrc(path));
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
        startReadingTimer();
        let saved = null;
        try { saved = JSON.parse(localStorage.getItem(key) || "null"); } catch { saved = null; }
        frame.contentWindow?.postMessage({ type: "hyesread:restore", location: saved }, "*");
        let savedHighlights: Highlight[] = [];
        try { savedHighlights = JSON.parse(localStorage.getItem(highlightKey) || "[]"); } catch { savedHighlights = []; }
        frame.contentWindow?.postMessage({ type: "hyesread:annotations", annotations: savedHighlights.map(({ value, note, color }) => ({ value, note, color })) }, "*");
      } else if (event.data?.type === "hyesread:selection") {
        const next = event.data.selection;
        if (typeof next?.value === "string" && typeof next?.text === "string" && next.text.trim()) setSelection({ value: next.value, text: next.text });
      } else if (event.data?.type === "hyesread:annotation-open") {
        setHighlightsOpen(true);
      } else if (event.data?.type === "hyesread:annotation-added" && typeof event.data.value === "string") {
        setPendingHighlights(current => { const next = new Set(current); next.delete(event.data.value); return next; });
      } else if (event.data?.type === "hyesread:annotation-error" && typeof event.data.value === "string") {
        const failedValue = event.data.value;
        setPendingHighlights(current => { const next = new Set(current); next.delete(failedValue); return next; });
        try {
          const savedHighlights = JSON.parse(localStorage.getItem(highlightKey) || "[]");
          const next = Array.isArray(savedHighlights) ? savedHighlights.filter(item => item?.value !== failedValue) : [];
          localStorage.setItem(highlightKey, JSON.stringify(next));
          setHighlights(next);
        } catch { setHighlights(current => current.filter(item => item.value !== failedValue)); }
        setError(`无法恢复或显示高亮：${event.data.message || "书籍位置无效"}`);
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

  useEffect(() => {
    if (!textReady) return;
    const frame = document.getElementById("foliate-reader") as HTMLIFrameElement | null;
    const body = frame?.contentDocument?.body;
    if (!body) return;
    const themes = {
      light: ["#fff", "#27272a"],
      sepia: ["#f4ecd8", "#433b30"],
      dark: ["#181818", "#d8d2c8"],
    } as const;
    const [background, color] = themes[textSettings.theme];
    body.style.background = background;
    body.style.color = color;
    body.style.fontSize = `${textSettings.fontSize}px`;
    body.style.lineHeight = String(textSettings.spacing);
    try {
      const current = JSON.parse(localStorage.getItem("hyesread:reader-settings") || "{}");
      localStorage.setItem("hyesread:reader-settings", JSON.stringify({
        ...current,
        style: { ...current.style, fontSize: textSettings.fontSize, spacing: textSettings.spacing, theme: textSettings.theme },
      }));
    } catch (e) {
      setError(`无法保存阅读设置：${e}`);
    }
  }, [textReady, textSettings]);

  const addBookmark = () => {
    if (!bookPath || !currentLocation) return;
    const existing = bookmarks.find(mark => mark.location.href === currentLocation.href && Math.abs(mark.location.fraction - currentLocation.fraction) < 0.003);
    const next = existing ? bookmarks.filter(mark => mark.id !== existing.id) : [
      { id: crypto.randomUUID(), label: currentLocation.chapter || `阅读位置 ${Math.round(currentLocation.fraction * 100)}%`, location: currentLocation, createdAt: Date.now() },
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
    if (textReady) {
      const frame = document.getElementById("foliate-reader") as HTMLIFrameElement | null;
      const textWindow = frame?.contentWindow;
      const scrollElement = textWindow?.document.scrollingElement || textWindow?.document.documentElement;
      const maxScroll = Math.max(0, (scrollElement?.scrollHeight ?? 0) - (textWindow?.innerHeight ?? 0));
      textWindow?.scrollTo(0, bookmark.location.fraction * maxScroll);
      setBookmarksOpen(false);
      return;
    }
    (document.getElementById("foliate-reader") as HTMLIFrameElement | null)?.contentWindow?.postMessage({ type: "hyesread:restore", location: bookmark.location }, "*");
    setBookmarksOpen(false);
  };

  const addHighlight = () => {
    if (!bookPath || !selection || !supportsTextSearch) return;
    if (highlights.some(item => item.value === selection.value)) { setSelection(null); return; }
    const annotation: Highlight = {
      id: crypto.randomUUID(), value: selection.value, text: selection.text,
      note: selection.text, color: "#facc15", createdAt: Date.now(),
    };
    const next = [annotation, ...highlights].slice(0, 1000);
    try {
      localStorage.setItem(`hyes-highlights:${bookPath}`, JSON.stringify(next));
      setHighlights(next);
      setPendingHighlights(current => new Set(current).add(annotation.value));
      (document.getElementById("foliate-reader") as HTMLIFrameElement | null)?.contentWindow?.postMessage({
        type: "hyesread:add-annotation", annotation: { value: annotation.value, note: annotation.note, color: annotation.color },
      }, "*");
      setSelection(null);
    } catch (e) { setError(`无法保存高亮：${e}`); }
  };

  const openHighlight = (highlight: Highlight) => {
    (document.getElementById("foliate-reader") as HTMLIFrameElement | null)?.contentWindow?.postMessage({
      type: "hyesread:show-annotation", value: highlight.value,
    }, "*");
    setHighlightsOpen(false);
  };

  const deleteHighlight = (highlight: Highlight) => {
    if (!bookPath) return;
    const next = highlights.filter(item => item.id !== highlight.id);
    try {
      localStorage.setItem(`hyes-highlights:${bookPath}`, JSON.stringify(next));
      setHighlights(next);
      (document.getElementById("foliate-reader") as HTMLIFrameElement | null)?.contentWindow?.postMessage({
        type: "hyesread:remove-annotation", value: highlight.value,
      }, "*");
    } catch (e) { setError(`无法删除高亮：${e}`); }
  };

  return (
    <main className="h-screen w-screen bg-[#050505] text-zinc-100 flex flex-col">
      <header className="relative h-14 shrink-0 border-b border-white/10 flex items-center gap-3 px-5 max-[640px]:gap-1 max-[640px]:px-2">
        <button onClick={() => router.push("/")} className="rounded-lg px-3 py-2 hover:bg-white/10">← 返回书库</button>
        <span className="min-w-0 flex-1 text-sm text-zinc-400 truncate">{bookTitle || bookPath?.split(/[\\/]/).pop()}</span>
        {readerReady && supportsTextSearch && <button type="button" aria-label="搜索正文" onClick={() => (document.getElementById("foliate-reader") as HTMLIFrameElement | null)?.contentWindow?.postMessage({ type: "hyesread:toggle-search" }, "*")} className="rounded-lg px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 max-[640px]:px-2">搜索</button>}
        {readerReady && supportsTextSearch && <button type="button" aria-label="高亮所选文字" onClick={addHighlight} disabled={!selection} className="rounded-lg px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 disabled:opacity-40 max-[640px]:px-2">高亮</button>}
        {readerReady && supportsTextSearch && <button type="button" aria-label="打开高亮列表" onClick={() => setHighlightsOpen(open => !open)} className="rounded-lg px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 max-[640px]:px-2">标注 {highlights.length}</button>}
        {(readerReady || textReady) && <button type="button" aria-label="阅读设置" onClick={() => {
          if (textReady) setTextSettingsOpen(open => !open);
          else (document.getElementById("foliate-reader") as HTMLIFrameElement | null)?.contentWindow?.postMessage({ type: "hyesread:toggle-settings" }, "*");
        }} className="rounded-lg px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 max-[640px]:px-2">设置</button>}
        {(readerReady || textReady) && <button type="button" aria-label="添加或移除当前书签" onClick={addBookmark} disabled={!currentLocation} className="rounded-lg px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 disabled:opacity-40 max-[640px]:px-2">{bookmarks.some(mark => mark.location.href === currentLocation?.href && Math.abs(mark.location.fraction - (currentLocation?.fraction || 0)) < 0.003) ? "已标记" : "书签"}</button>}
        {(readerReady || textReady) && <button type="button" aria-label="打开书签列表" onClick={() => setBookmarksOpen(value => !value)} className="rounded-lg px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 max-[640px]:px-2">{bookmarks.length}</button>}
        {bookmarksOpen && <section aria-label="书签列表" className="absolute right-4 top-14 z-20 max-h-[65vh] w-80 overflow-auto rounded-xl border border-white/10 bg-[#141414] p-3 shadow-2xl max-[640px]:right-1 max-[640px]:w-[calc(100vw-8px)]">{bookmarks.length ? bookmarks.map(mark => <div key={mark.id} className="flex items-center gap-2 border-b border-white/5 py-1 last:border-0"><button type="button" onClick={() => goToBookmark(mark)} className="min-w-0 flex-1 truncate rounded-lg px-2 py-2 text-left text-sm text-zinc-200 hover:bg-white/10">{mark.label} · {Math.round(mark.location.fraction * 100)}%</button><button type="button" aria-label={`删除书签 ${mark.label}`} onClick={() => { const next = bookmarks.filter(item => item.id !== mark.id); try { localStorage.setItem(`hyes-bookmarks:${bookPath}`, JSON.stringify(next)); setBookmarks(next); } catch (e) { setError(`无法删除书签：${e}`); } }} className="px-2 py-2 text-zinc-500 hover:text-red-300">×</button></div>) : <div aria-hidden="true" className="h-10" />}</section>}
        {highlightsOpen && <section aria-label="高亮列表" className="absolute right-4 top-14 z-20 max-h-[65vh] w-80 overflow-auto rounded-xl border border-white/10 bg-[#141414] p-3 shadow-2xl max-[640px]:right-1 max-[640px]:w-[calc(100vw-8px)]">{highlights.length ? highlights.map(item => <div key={item.id} className="flex items-center gap-2 border-b border-white/5 py-1 last:border-0"><button type="button" onClick={() => openHighlight(item)} className="min-w-0 flex-1 rounded-lg px-2 py-2 text-left text-sm text-zinc-200 hover:bg-white/10 line-clamp-3">{item.text}</button><button type="button" aria-label="删除高亮" disabled={pendingHighlights.has(item.value)} onClick={() => deleteHighlight(item)} className="px-2 py-2 text-zinc-500 hover:text-red-300 disabled:opacity-40">×</button></div>) : <div aria-hidden="true" className="h-10" />}</section>}
        {textReady && textSettingsOpen && <section aria-label="阅读设置" className="absolute right-4 top-14 z-20 grid w-80 gap-4 rounded-xl border border-white/10 bg-[#141414] p-4 shadow-2xl max-[640px]:right-1 max-[640px]:w-[calc(100vw-8px)]">
          <label className="flex items-center justify-between gap-3 text-sm text-zinc-300">字号<input aria-label="字号" type="range" min="14" max="32" step="1" value={textSettings.fontSize} onChange={event => setTextSettings(settings => ({ ...settings, fontSize: Number(event.target.value) }))} /></label>
          <label className="flex items-center justify-between gap-3 text-sm text-zinc-300">行距<input aria-label="行距" type="range" min="1.2" max="2.2" step="0.1" value={textSettings.spacing} onChange={event => setTextSettings(settings => ({ ...settings, spacing: Number(event.target.value) }))} /></label>
          <label className="flex items-center justify-between gap-3 text-sm text-zinc-300">背景<select aria-label="背景" value={textSettings.theme} onChange={event => setTextSettings(settings => ({ ...settings, theme: event.target.value as TextSettings["theme"] }))} className="rounded-md bg-zinc-800 px-2 py-1"><option value="light">浅色</option><option value="sepia">护眼</option><option value="dark">深色</option></select></label>
        </section>}
        {error && <span role="alert" className="text-red-400">{error}</span>}
      </header>
      <iframe id="foliate-reader" title="电子书阅读器" className="min-h-0 flex-1 border-0 bg-white" />
    </main>
  );
}
