"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { convertFileSrc } from "@tauri-apps/api/core";
import { invoke, isDesktop, updateValue, writeValue } from "../../lib/platform";
import { getBrowserBook, isBrowserBook } from "../../lib/browserBooks";

export default function ReaderPage() {
  return <Suspense fallback={<main className="h-screen bg-[#050505]" />}><ReaderContent /></Suspense>;
}

function ReaderContent() {
  const router = useRouter();
  const params = useSearchParams();
  const [error, setError] = useState("");
  const [bookTitle, setBookTitle] = useState("");
  const bookPath = params.get("path");

  useEffect(() => {
    const path = bookPath;
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
        localStorage.setItem(key, JSON.stringify(event.data.location));
      } else if (event.data?.type === "hyesread:ready") {
        const saved = localStorage.getItem(key);
        frame.contentWindow?.postMessage({ type: "hyesread:restore", location: saved ? JSON.parse(saved) : null }, "*");
      } else if (event.data?.type === "hyesread:error") {
        setError(`无法打开这本书：${event.data.message || "文件格式或内容无效"}`);
      }
    };
    window.addEventListener("message", onMessage);
    onLoad = () => {
      const saved = localStorage.getItem(key);
      frame.contentWindow?.postMessage({ type: "hyesread:restore", location: saved ? JSON.parse(saved) : null }, "*");
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

  return (
    <main className="h-screen w-screen bg-[#050505] text-zinc-100 flex flex-col">
      <header className="h-14 shrink-0 border-b border-white/10 flex items-center gap-4 px-5">
        <button onClick={() => router.back()} className="rounded-lg px-3 py-2 hover:bg-white/10">← 返回书库</button>
        <span className="text-sm text-zinc-400 truncate">{bookTitle || bookPath?.split(/[\\/]/).pop()}</span>
        {error && <span role="alert" className="text-red-400">{error}</span>}
      </header>
      <iframe id="foliate-reader" title="电子书阅读器" className="min-h-0 flex-1 border-0 bg-white" />
    </main>
  );
}
