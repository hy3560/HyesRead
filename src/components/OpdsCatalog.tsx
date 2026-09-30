"use client";

import { useEffect, useMemo, useState } from "react";
import { save as saveDialog } from "@tauri-apps/plugin-dialog";
import { ArrowLeft, ArrowRight, BookOpen, Download, FolderOpen, Loader2, Plus, Search, Trash2 } from "lucide-react";
import { invoke, readValue, writeValue } from "../lib/platform";

type CatalogLink = {
  href: string;
  rel: string;
  media_type: string;
  title: string;
  length: number | null;
};

type CatalogEntry = {
  id: string;
  title: string;
  author: string;
  summary: string;
  links: CatalogLink[];
};

type CatalogFeed = {
  title: string;
  entries: CatalogEntry[];
  links: CatalogLink[];
};

type CatalogSource = { url: string; title: string };
type ReadingBook = { title: string; author: string; path: string; format: string; size: number; cover: string | null };

const CATALOG_STORE = "hyes_catalogs.json";
const BOOK_EXTENSIONS = ["epub", "pdf", "mobi", "azw3", "kf8", "fb2", "fbz", "cbz", "txt", "md"];

function isAcquisition(link: CatalogLink) {
  return link.rel.startsWith("http://opds-spec.org/acquisition") || link.rel.startsWith("https://opds-spec.org/acquisition");
}

function isCatalogNavigation(link: CatalogLink) {
  return link.rel === "subsection" || link.rel === "collection" || link.media_type.includes("opds-catalog") ||
    (link.media_type.includes("atom+xml") && !isAcquisition(link));
}

function filenamePart(value: string) {
  return value.replace(/[<>:"/\\|?*\u0000-\u001f]/g, "_").replace(/[. ]+$/g, "").trim().slice(0, 100) || "book";
}

function linkExtension(link: CatalogLink) {
  const pathname = new URL(link.href).pathname;
  const suffix = pathname.split("/").pop()?.split(".").pop()?.toLowerCase() || "";
  if (BOOK_EXTENSIONS.includes(suffix)) return suffix;
  const mediaTypes: Record<string, string> = {
    "application/epub+zip": "epub",
    "application/pdf": "pdf",
    "application/x-mobipocket-ebook": "mobi",
    "application/x-cbz": "cbz",
    "text/plain": "txt",
    "text/markdown": "md",
  };
  return mediaTypes[link.media_type.toLowerCase()] || "epub";
}

function acquisitionUrl(linkUrl: string, sourceUrl: string) {
  try {
    const source = new URL(sourceUrl);
    const target = new URL(linkUrl);
    if (source.origin === target.origin && (source.username || source.password)) {
      target.username = decodeURIComponent(source.username);
      target.password = decodeURIComponent(source.password);
    }
    return target.toString();
  } catch {
    return linkUrl;
  }
}

export default function OpdsCatalog({ onImported }: { onImported: (path: string) => Promise<boolean> }) {
  const [sources, setSources] = useState<CatalogSource[]>([]);
  const [sourceUrl, setSourceUrl] = useState("");
  const [activeUrl, setActiveUrl] = useState("");
  const [trail, setTrail] = useState<CatalogSource[]>([]);
  const [feed, setFeed] = useState<CatalogFeed | null>(null);
  const [filter, setFilter] = useState("");
  const [busy, setBusy] = useState(false);
  const [downloading, setDownloading] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    readValue<CatalogSource[]>(CATALOG_STORE, "sources", []).then(setSources).catch(reason => setError(`无法读取目录列表：${String(reason)}`));
  }, []);

  const visibleEntries = useMemo(() => {
    const query = filter.trim().toLocaleLowerCase();
    return (feed?.entries || []).filter(entry => !query || `${entry.title} ${entry.author} ${entry.summary}`.toLocaleLowerCase().includes(query));
  }, [feed, filter]);

  const fetchFeed = async (url: string) => invoke<CatalogFeed>("fetch_opds_feed", { url });

  const openSource = async (source: CatalogSource) => {
    setBusy(true);
    setError("");
    try {
      const nextFeed = await fetchFeed(source.url);
      setActiveUrl(source.url);
      setTrail([{ url: source.url, title: nextFeed.title || source.title }]);
      setFeed(nextFeed);
      setFilter("");
    } catch (reason) {
      setError(`目录读取失败：${String(reason)}`);
    } finally {
      setBusy(false);
    }
  };

  const addSource = async () => {
    const url = sourceUrl.trim();
    try {
      const parsed = new URL(url);
      if (!["http:", "https:"].includes(parsed.protocol) || !parsed.hostname) throw new Error("地址无效");
    } catch {
      setError("请输入有效的 HTTP 或 HTTPS 目录地址。");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const nextFeed = await fetchFeed(url);
      const nextSources = [...sources.filter(source => source.url !== url), { url, title: nextFeed.title }];
      await writeValue(CATALOG_STORE, "sources", nextSources);
      setSources(nextSources);
      setSourceUrl("");
      setActiveUrl(url);
      setTrail([{ url, title: nextFeed.title }]);
      setFeed(nextFeed);
      setFilter("");
    } catch (reason) {
      setError(`目录读取失败：${String(reason)}`);
    } finally {
      setBusy(false);
    }
  };

  const removeSource = async (url: string) => {
    const nextSources = sources.filter(source => source.url !== url);
    try {
      await writeValue(CATALOG_STORE, "sources", nextSources);
      setSources(nextSources);
      if (activeUrl === url) {
        setActiveUrl("");
        setTrail([]);
        setFeed(null);
      }
    } catch (reason) {
      setError(`无法移除目录：${String(reason)}`);
    }
  };

  const navigateTo = async (link: CatalogLink) => {
    setBusy(true);
    setError("");
    try {
      const nextFeed = await fetchFeed(link.href);
      setTrail(current => [...current, { url: link.href, title: nextFeed.title || link.title || "目录" }]);
      setFeed(nextFeed);
      setFilter("");
    } catch (reason) {
      setError(`目录读取失败：${String(reason)}`);
    } finally {
      setBusy(false);
    }
  };

  const goBack = async () => {
    if (trail.length < 2) return;
    const nextTrail = trail.slice(0, -1);
    setBusy(true);
    setError("");
    try {
      const nextFeed = await fetchFeed(nextTrail[nextTrail.length - 1].url);
      setTrail(nextTrail);
      setFeed(nextFeed);
      setFilter("");
    } catch (reason) {
      setError(`目录读取失败：${String(reason)}`);
    } finally {
      setBusy(false);
    }
  };

  const loadNextPage = async () => {
    const next = feed?.links.find(link => link.rel === "next");
    if (!next) return;
    setBusy(true);
    setError("");
    try {
      const nextFeed = await fetchFeed(next.href);
      setFeed(current => {
        if (!current) return nextFeed;
        const merged = new Map<string, CatalogEntry>();
        for (const entry of [...current.entries, ...nextFeed.entries]) merged.set(entry.id || entry.title, entry);
        return { ...nextFeed, title: current.title, entries: Array.from(merged.values()) };
      });
    } catch (reason) {
      setError(`下一页读取失败：${String(reason)}`);
    } finally {
      setBusy(false);
    }
  };

  const downloadEntry = async (entry: CatalogEntry, link: CatalogLink) => {
    const extension = linkExtension(link);
    const label = filenamePart(entry.title);
    setError("");
    try {
      const destination = await saveDialog({
        defaultPath: `${label}.${extension}`,
        filters: [{ name: "电子书", extensions: BOOK_EXTENSIONS }],
      });
      if (!destination) return;
      setDownloading(link.href);
      const path = await invoke<string>("download_opds_book", { url: acquisitionUrl(link.href, activeUrl), destination });
      if (!await onImported(path)) setError("电子书已保存，但没有加入书架。");
    } catch (reason) {
      setError(`下载失败：${String(reason)}`);
    } finally {
      setDownloading("");
    }
  };

  return (
    <div className="grid min-h-full grid-cols-[minmax(220px,280px)_minmax(0,1fr)] gap-6 max-[760px]:grid-cols-1">
      <aside className="space-y-5 rounded-2xl border border-white/5 bg-white/[0.02] p-4">
        <h2 className="flex items-center gap-2 text-sm font-semibold text-white"><FolderOpen size={17} className="text-orange-400" />书目来源</h2>
        <form className="flex items-end gap-2" onSubmit={event => { event.preventDefault(); void addSource(); }}>
          <label className="min-w-0 flex-1"><span className="mb-1 block text-xs text-zinc-500">OPDS 地址</span><input aria-label="OPDS 地址" type="url" value={sourceUrl} onChange={event => setSourceUrl(event.target.value)} className="w-full rounded-lg border border-white/10 bg-black/40 px-3 py-2 text-xs text-white outline-none focus:border-orange-500/60" /></label>
          <button type="submit" aria-label="添加目录" disabled={busy || !sourceUrl.trim()} className="rounded-lg border border-white/10 px-3 text-zinc-300 hover:bg-white/10 disabled:opacity-40"><Plus size={16} /></button>
        </form>
        <div className="space-y-2">
          {sources.map(source => (
            <div key={source.url} className={`group flex items-center gap-1 rounded-xl border px-2 py-1 ${activeUrl === source.url ? "border-orange-500/30 bg-orange-500/5" : "border-transparent hover:bg-white/5"}`}>
              <button type="button" onClick={() => void openSource(source)} className="min-w-0 flex-1 truncate px-2 py-2 text-left text-sm text-zinc-300">{source.title}</button>
              <button type="button" aria-label={`移除目录 ${source.title}`} onClick={() => void removeSource(source.url)} className="rounded-md p-2 text-zinc-600 hover:bg-white/10 hover:text-red-300"><Trash2 size={14} /></button>
            </div>
          ))}
        </div>
      </aside>

      <section className="min-w-0 space-y-5 rounded-2xl border border-white/5 bg-white/[0.02] p-5">
        <div className="flex flex-wrap items-center gap-3">
          {trail.length > 1 && <button type="button" aria-label="返回上级目录" onClick={() => void goBack()} className="rounded-lg p-2 text-zinc-300 hover:bg-white/10"><ArrowLeft size={17} /></button>}
          <h2 className="min-w-0 flex-1 truncate text-lg font-serif text-white">{feed?.title || "目录"}</h2>
          {feed && <label className="flex items-center gap-2 rounded-lg border border-white/10 px-3 py-2 text-zinc-500"><Search size={14} /><input aria-label="搜索当前目录" value={filter} onChange={event => setFilter(event.target.value)} className="w-40 bg-transparent text-sm text-white outline-none max-[640px]:w-28" /></label>}
        </div>
        {error && <div role="alert" className="flex items-start justify-between gap-3 rounded-lg border border-red-500/20 bg-red-500/5 px-3 py-2 text-sm text-red-300"><span>{error}</span><button type="button" aria-label="关闭错误信息" onClick={() => setError("")}>×</button></div>}
        {busy && <div aria-label="正在读取" className="flex justify-center py-12 text-orange-400"><Loader2 size={24} className="animate-spin" /></div>}
        {!busy && feed && (
          <>
            <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
              {visibleEntries.map((entry, index) => {
                const acquisitions = entry.links.filter(isAcquisition);
                const navigation = entry.links.find(isCatalogNavigation);
                return (
                  <article key={entry.id || `${entry.title}-${index}`} className="flex min-w-0 flex-col gap-3 rounded-xl border border-white/5 bg-black/20 p-4">
                    <div className="min-w-0">
                      <h3 className="line-clamp-2 text-sm font-medium text-white">{entry.title}</h3>
                      {entry.author && <p className="mt-1 truncate text-xs text-zinc-500">{entry.author}</p>}
                      {entry.summary && <p className="mt-2 line-clamp-3 text-xs leading-5 text-zinc-400">{entry.summary}</p>}
                    </div>
                    <div className="mt-auto flex flex-wrap gap-2">
                      {navigation && <button type="button" aria-label={`打开 ${navigation.title || entry.title}`} onClick={() => void navigateTo(navigation)} className="flex items-center gap-1 rounded-lg border border-white/10 px-3 py-2 text-xs text-zinc-300 hover:bg-white/10">打开<ArrowRight size={13} /></button>}
                      {acquisitions.map((link, linkIndex) => (
                        <button key={`${link.href}-${linkIndex}`} type="button" disabled={Boolean(downloading)} onClick={() => void downloadEntry(entry, link)} className="flex items-center gap-1 rounded-lg bg-white/10 px-3 py-2 text-xs text-white hover:bg-orange-500/20 disabled:opacity-50">
                          {downloading === link.href ? <Loader2 size={13} className="animate-spin" /> : <Download size={13} />}{link.title || linkExtension(link).toUpperCase()}
                        </button>
                      ))}
                    </div>
                  </article>
                );
              })}
            </div>
            {feed.links.some(link => link.rel === "next") && <button type="button" disabled={busy} onClick={() => void loadNextPage()} className="mx-auto flex items-center gap-2 rounded-lg border border-white/10 px-4 py-2 text-sm text-zinc-300 hover:bg-white/10 disabled:opacity-40">下一页<ArrowRight size={15} /></button>}
          </>
        )}
        {!busy && !feed && <div aria-hidden="true" className="flex min-h-64 items-center justify-center text-zinc-700"><BookOpen size={38} /></div>}
      </section>
    </div>
  );
}
