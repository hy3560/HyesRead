"use client";

import { useEffect, useState, useMemo, useRef } from "react";
import { invoke, isDesktop, readValue, updateValue, writeValue } from "../lib/platform";
import { getBrowserBook, isBrowserBook, removeBrowserBook, saveBrowserBook } from "../lib/browserBooks";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { useRouter } from "next/navigation";
import OpdsCatalog from "../components/OpdsCatalog";
import { createBackup, downloadBackup, restoreBackup } from "../lib/backup";
import { motion, AnimatePresence } from "framer-motion";
import { 
  Library, Settings2, Loader2, Ghost, Globe2,
  Clock, NotebookPen,
  HardDrive, FileType, FolderPlus, FilePlus, Book as BookIcon,
  BookOpen, Timer, Trophy, Activity, CalendarDays,
  Search, List, Save, Download, Upload
} from "lucide-react";
import { 
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer 
} from "recharts";

type ViewType = 'home' | 'library' | 'catalog' | 'stats' | 'settings';

interface Book {
  title: string; author: string; path: string; format: string; size: number; cover: string | null;
}

interface ReadingSession {
  date: string; 
  duration: number; 
  bookPath: string; 
}

interface TrendData {
  date: string;
  hours: number;
}

function mergeBooks(current: Book[], incoming: Book[]) {
  const booksByPath = new Map(current.map(book => [book.path, book]));
  incoming.forEach(book => booksByPath.set(book.path, book));
  return Array.from(booksByPath.values());
}

export default function HyesReadMaster() {
  const router = useRouter();
  const [books, setBooks] = useState<Book[]>([]);
  const [sessions, setSessions] = useState<ReadingSession[]>([]);
  const [chartRange, setChartRange] = useState<'30days' | 'year'>('30days');

  const [activeTab, setActiveTab] = useState<ViewType>('library');
  const [isScanning, setIsScanning] = useState(false);

  const [query, setQuery] = useState("");
  const [sortMode, setSortMode] = useState<"title" | "author" | "recent">("recent");
  const [lastOpenedBook, setLastOpenedBook] = useState("");
  const [operationError, setOperationError] = useState("");
  const [backupMessage, setBackupMessage] = useState("");
  const backupInput = useRef<HTMLInputElement>(null);

  const exportDataBackup = async () => {
    setOperationError("");
    setBackupMessage("");
    try {
      const backup = await createBackup();
      downloadBackup(backup);
      setBackupMessage("备份文件已生成。书籍原文件仍保存在原位置。 ");
    } catch (error) {
      setOperationError(`生成备份失败：${String(error)}`);
    }
  };

  const importDataBackup = async (file?: File) => {
    if (!file) return;
    setOperationError("");
    setBackupMessage("");
    try {
      if (file.size > 50 * 1024 * 1024) throw new Error("备份文件超过 50 MB 限制");
      await restoreBackup(await file.text());
      const [discretePaths, storedSessions] = await Promise.all([
        readValue<string[]>("hyes_master.json", "discrete_files", []),
        readValue<ReadingSession[]>("hyes_stats.json", "sessions", []),
      ]);
      setSessions(storedSessions);
      if (isDesktop()) {
        const restored = await invoke<Book[]>("import_files", { filePaths: discretePaths });
        setBooks(current => mergeBooks(current, restored));
      } else {
        const restored = await Promise.all(discretePaths.filter(isBrowserBook).map(async path => {
          const book = await getBrowserBook(path);
          return book ? { title: book.name.replace(/\.[^.]+$/, ""), author: "", path, format: book.name.split(".").pop()?.toUpperCase() || "BOOK", size: book.size / 1048576, cover: null } satisfies Book : null;
        }));
        setBooks(current => mergeBooks(current, restored.filter((book): book is Book => book !== null)));
      }
      setBackupMessage("备份数据已合并。书籍文件没有复制；缺失的文件请重新导入。 ");
    } catch (error) {
      setOperationError(`恢复备份失败：${String(error)}`);
    } finally {
      if (backupInput.current) backupInput.current.value = "";
    }
  };

  const stats = useMemo(() => {
    const totalCount = books.length;
    const totalSize = books.reduce((acc, b) => acc + b.size, 0);
    const formatDist = books.reduce((acc: any, b) => {
      acc[b.format] = (acc[b.format] || 0) + 1;
      return acc;
    }, {});
    
    const totalReadMinutes = sessions.reduce((acc, s) => acc + s.duration, 0);
    const totalReadHours = (totalReadMinutes / 60).toFixed(1);
    
    const uniqueDays = new Set(sessions.map(s => s.date));
    const activeDays = uniqueDays.size;

    const bookDurationMap = sessions.reduce((acc: any, s) => {
       acc[s.bookPath] = (acc[s.bookPath] || 0) + s.duration;
       return acc;
    }, {});
    
    let longestBookPath = "";
    let maxDuration = 0;
    for (const [path, duration] of Object.entries(bookDurationMap)) {
       if ((duration as number) > maxDuration) {
          maxDuration = duration as number;
          longestBookPath = path;
       }
    }
    
    let longestBookTitle = "暂无记录";
    if (longestBookPath) {
       const b = books.find(b => b.path === longestBookPath);
       if (b) longestBookTitle = b.title;
       else longestBookTitle = "已从书架移除";
    }

    const today = new Date();
    const readingTrendData: TrendData[] = [];

    if (chartRange === '30days') {
        for (let i = 29; i >= 0; i--) {
            const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() - i);
            const y = d.getFullYear();
            const m = String(d.getMonth() + 1).padStart(2, '0');
            const day = String(d.getDate()).padStart(2, '0');
            const dateStr = `${y}-${m}-${day}`;
            const displayDate = `${d.getMonth() + 1}/${d.getDate()}`;
            
            const dayMins = sessions
                .filter(s => s.date === dateStr)
                .reduce((acc, s) => acc + s.duration, 0);
            
            readingTrendData.push({
                date: displayDate,
                hours: Number((dayMins / 60).toFixed(2))
            });
        }
    } else {
        const currentYear = today.getFullYear();
        for (let i = 0; i < 12; i++) {
            const monthStr = `${i + 1}月`;
            const monthMins = sessions
                .filter(s => {
                    if (!s.date) return false;
                    const [y, m, d] = s.date.split('-');
                    return parseInt(y) === currentYear && parseInt(m) === i + 1;
                })
                .reduce((acc, s) => acc + s.duration, 0);

            readingTrendData.push({
                date: monthStr,
                hours: Number((monthMins / 60).toFixed(2))
            });
        }
    }

    return { 
      totalCount, 
      totalSize: totalSize.toFixed(2), 
      formats: Object.keys(formatDist).length, 
      formatDist,
      longestBook: longestBookTitle,
      totalReadHours,
      activeDays,
      readingTrendData
    };
  }, [books, sessions, chartRange]);

  const filteredBooks = useMemo(() => {
    const q = query.trim().toLocaleLowerCase();
    return books
      .filter(book => !q || `${book.title} ${book.author}`.toLocaleLowerCase().includes(q))
      .sort((a, b) => sortMode === "title" ? a.title.localeCompare(b.title) : sortMode === "author" ? a.author.localeCompare(b.author) : 0);
  }, [books, query, sortMode]);

  useEffect(() => {
    (async () => {
      try {
        const path = await readValue("hyes_master.json", "library_path", "");
        const discretePaths = await readValue<string[]>("hyes_master.json", "discrete_files", []);
        const excludedPaths = await readValue<string[]>("hyes_master.json", "excluded_files", []);
        const excluded = new Set(excludedPaths);
        setLastOpenedBook(await readValue("hyes_master.json", "last_opened_book", ""));
        
        if (discretePaths && discretePaths.length > 0) {
          if (isDesktop()) {
            invoke<Book[]>("import_files", { filePaths: discretePaths }).then(res => setBooks(prev => mergeBooks(prev, res.filter(book => !excluded.has(book.path))))).catch(error => {
              console.error("已导入文件恢复失败", error);
              setOperationError(`无法恢复已导入的书籍：${String(error)}`);
            });
          } else {
            const restored = await Promise.all(discretePaths.filter(isBrowserBook).map(async path => {
              const file = await getBrowserBook(path);
              return file && !excluded.has(path) ? { title: file.name.replace(/\.[^.]+$/, ""), author: "", path, format: file.name.split(".").pop()?.toUpperCase() || "BOOK", size: file.size / 1048576, cover: null } satisfies Book : null;
            }));
            setBooks(prev => mergeBooks(prev, restored.filter(book => book !== null)));
          }
        }

        const storedSessions = await readValue<ReadingSession[]>("hyes_stats.json", "sessions", []);
        setSessions(storedSessions);

        if (path) handleScan(path);
      } catch (e) {
        console.error("书架读取失败", e);
        setOperationError(`无法读取本机书架：${String(e)}`);
      }
    })();
  }, []);

  const handleScan = async (targetPath: string) => {
    setOperationError("");
    setIsScanning(true);
    try {
      const result: Book[] = await invoke("scan_library", { folderPath: targetPath });
      await writeValue("hyes_master.json", "library_path", targetPath);
      const excluded = new Set(await readValue<string[]>("hyes_master.json", "excluded_files", []));
      setBooks(prev => {
          const normalizedRoot = targetPath.replace(/[\\/]+$/, "").toLocaleLowerCase();
          const insideRoot = (path: string) => {
            const normalized = path.toLocaleLowerCase();
            return normalized === normalizedRoot || normalized.startsWith(normalizedRoot + "\\") || normalized.startsWith(normalizedRoot + "/");
          };
          return mergeBooks(prev.filter(book => !insideRoot(book.path)), result.filter(book => !excluded.has(book.path)));
      });
    } catch (e: any) {
      console.error(e);
      setOperationError(`扫描书库失败：${String(e)}`);
    }
    finally { setIsScanning(false); }
  };

  const handleImportFiles = async (paths: string[]): Promise<boolean> => {
    setOperationError("");
    setIsScanning(true);
    try {
        const result: Book[] = await invoke("import_files", { filePaths: paths });
        await updateValue<string[]>("hyes_master.json", "discrete_files", [], existing => Array.from(new Set([...existing, ...paths])));
        await updateValue<string[]>("hyes_master.json", "excluded_files", [], existing => existing.filter(path => !paths.includes(path)));
        setBooks(prev => {
            const map = new Map(prev.map(b => [b.path, b]));
            result.forEach(b => map.set(b.path, b));
            return Array.from(map.values());
        });
        return true;
    } catch (e: any) {
        console.error(e);
        setOperationError(`文件导入失败：${String(e)}`);
        return false;
    } finally {
        setIsScanning(false);
    }
  };

  const handleOpenBook = async (path: string) => {
    setOperationError("");
    try {
      if (isDesktop()) await invoke("prepare_book_read", { path });
      await writeValue("hyes_master.json", "last_opened_book", path);
      setLastOpenedBook(path);
      router.push(`/reader?path=${encodeURIComponent(path)}`);
    } catch (e) {
      console.error(e);
      setOperationError(`无法打开这本书：${String(e)}`);
    }
  };

  const handleRemoveBook = async (path: string) => {
    const browserBook = isBrowserBook(path);
    try {
      if (!browserBook) {
        await updateValue<string[]>("hyes_master.json", "excluded_files", [], existing => Array.from(new Set([...existing, path])));
      }
      try {
        await updateValue<string[]>("hyes_master.json", "discrete_files", [], paths => paths.filter(item => item !== path));
      } catch (error) {
        if (!browserBook) await updateValue<string[]>("hyes_master.json", "excluded_files", [], paths => paths.filter(item => item !== path));
        throw error;
      }
      if (browserBook) {
        try {
          await removeBrowserBook(path);
        } catch (error) {
          await updateValue<string[]>("hyes_master.json", "discrete_files", [], paths => Array.from(new Set([...paths, path])));
          throw error;
        }
      }
      setBooks(prev => prev.filter(book => book.path !== path));
      if (lastOpenedBook === path) {
        try {
          await writeValue("hyes_master.json", "last_opened_book", "");
          setLastOpenedBook("");
        } catch (error) {
          console.error("已移除书籍的继续阅读记录未能清理", error);
          setOperationError(`书籍已从书架移除，但继续阅读记录未能清理：${String(error)}`);
        }
      }
    } catch (e) {
      console.error("从书架移除失败", e);
      setOperationError(`无法从书架移除：${String(e)}`);
    }
  };

  return (
    <div className="flex h-screen w-screen bg-[#050505] text-zinc-300 font-sans overflow-hidden">
      <nav className="w-20 flex flex-col items-center py-10 border-r border-white/5 bg-black/40 backdrop-blur-3xl z-30 relative">
        <motion.div 
          animate={{ opacity: [0.3, 1, 0.3] }} 
          transition={{ duration: 2.5, repeat: Infinity, ease: "easeInOut" }}
          className="text-orange-500 mb-12"
        >
          <BookOpen size={26} />
        </motion.div>

        <div className="flex-1 flex flex-col gap-10">
          <NavIcon label="首页" icon={<Clock size={20} />} active={activeTab === 'home'} onClick={() => setActiveTab('home')} />
          <NavIcon label="书架" icon={<Library size={20} />} active={activeTab === 'library'} onClick={() => setActiveTab('library')} />
          {isDesktop() && <NavIcon label="在线目录" icon={<Globe2 size={20} />} active={activeTab === 'catalog'} onClick={() => setActiveTab('catalog')} />}
        </div>
        <div className="mb-4 flex flex-col gap-8">
           <NavIcon label="阅读统计" icon={<NotebookPen size={20} />} active={activeTab === 'stats'} onClick={() => setActiveTab('stats')} className="text-blue-400" />
           <NavIcon label="设置" icon={<Settings2 size={20} />} active={activeTab === 'settings'} onClick={() => setActiveTab('settings')} />
        </div>
      </nav>

      <main className="flex-1 flex flex-col overflow-hidden relative">
        <header className="h-24 flex items-center justify-between gap-2 px-12 border-b border-white/5 z-20 shrink-0 max-[640px]:px-4">
          <div>
            <h1 className="whitespace-nowrap text-2xl font-serif italic text-white max-[640px]:text-lg">Hyes Read</h1>
            <p className="text-sm text-zinc-500 max-[640px]:hidden">你的本地书架</p>
          </div>
          
          <div className="flex shrink-0 items-center gap-4 max-[640px]:gap-2">
                <button onClick={async () => {
                setOperationError("");
                try {
                if (!isDesktop()) {
                  const chosen = await new Promise<File[]>((resolve) => {
                    const input = document.createElement("input"); input.type = "file"; input.multiple = true; input.accept = ".epub,.pdf,.mobi,.azw3,.kf8,.fb2,.fbz,.cbz,.txt,.md";
                    input.onchange = () => resolve(Array.from(input.files || []));
                    input.oncancel = () => resolve([]);
                    input.click();
                  });
                  for (const file of chosen) {
                    const url = `browser-book:${crypto.randomUUID()}`;
                    await saveBrowserBook(url, file);
                    const book: Book = { title: file.name.replace(/\.[^.]+$/, ""), author: "", path: url, format: file.name.split(".").pop()?.toUpperCase() || "BOOK", size: file.size / 1048576, cover: null };
                    await updateValue<string[]>("hyes_master.json", "discrete_files", [], existing => Array.from(new Set([...existing, url])));
                    setBooks(prev => [book, ...prev.filter(item => item.path !== url)]);
                  }
                  return;
                }
                const paths = await openDialog({ 
                    multiple: true, 
                    directory: false,
                    filters: [{ name: 'Books', extensions: ['epub', 'mobi', 'azw3', 'kf8', 'pdf', 'txt', 'md', 'cbz', 'fb2', 'fbz'] }]
                });
                if (paths && Array.isArray(paths)) handleImportFiles(paths as string[]);
                } catch (e) {
                  console.error("文件添加失败", e);
                  setOperationError(`文件添加失败：${String(e)}`);
                }
              }} aria-label="添加文件" className="flex items-center gap-2 bg-white/5 text-zinc-300 border border-white/10 px-5 py-2.5 rounded-2xl font-bold text-xs hover:bg-white/10 hover:text-white transition-all z-20 max-[640px]:h-11 max-[640px]:w-11 max-[640px]:justify-center max-[640px]:p-0">
                <FilePlus size={16} />
                <span className="max-[640px]:hidden">添加文件</span>
            </button>

            {isDesktop() && <button onClick={async () => {
                setOperationError("");
                try {
                const p = await openDialog({ directory: true });
                if (p) handleScan(p as string);
                } catch (e) {
                  console.error("目录选择失败", e);
                  setOperationError(`目录选择失败：${String(e)}`);
                }
              }} aria-label="导入书库" className="flex items-center gap-2 bg-white text-black px-5 py-2.5 rounded-2xl font-black text-xs hover:bg-orange-500 hover:text-white transition-all z-20 shadow-[0_0_15px_rgba(255,255,255,0.1)] hover:shadow-[0_0_20px_rgba(249,115,22,0.4)] max-[640px]:h-11 max-[640px]:w-11 max-[640px]:justify-center max-[640px]:p-0">
                <FolderPlus size={16} />
                <span className="max-[640px]:hidden">导入书库</span>
            </button>}
          </div>
        </header>

        <section className="flex-1 overflow-y-auto p-12 custom-scrollbar relative max-[640px]:p-4">
          {operationError && (
            <div role="alert" className="mb-5 flex items-start justify-between gap-4 rounded-xl border border-red-500/20 bg-red-500/5 px-4 py-3 text-sm text-red-300">
              <span>{operationError}</span>
              <button type="button" aria-label="关闭错误信息" onClick={() => setOperationError("")} className="shrink-0 text-red-200/70 hover:text-red-100">×</button>
            </div>
          )}
          <AnimatePresence mode="wait">
            {isScanning && (
              <motion.div 
                key="loading"
                initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
                className="absolute inset-0 z-50 flex flex-col items-center justify-center bg-[#050505]/70 backdrop-blur-md"
              >
                <motion.div animate={{ rotate: 360 }} transition={{ duration: 2, repeat: Infinity, ease: "linear" }} className="text-orange-500 mb-6">
                  <Loader2 size={48} />
                </motion.div>
                <p className="text-xs tracking-[0.5em] text-white font-bold uppercase">正在读取书籍</p>
              </motion.div>
            )}

            {!isScanning && activeTab === 'home' && (
              <motion.div key="home" initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="h-full w-full flex flex-col">
                <div className="mb-6">
                  <h2 className="text-xl font-serif text-white border-b border-white/5 pb-4">正在阅读的书籍</h2>
                </div>
                {books.length ? (
                  <button onClick={() => handleOpenBook((books.find(book => book.path === lastOpenedBook) || books[0]).path)} className="m-auto flex max-w-lg items-center gap-6 rounded-3xl border border-white/10 bg-white/[0.03] p-6 text-left hover:border-orange-500/40">
                    {(books.find(book => book.path === lastOpenedBook) || books[0]).cover ? <img src={(books.find(book => book.path === lastOpenedBook) || books[0]).cover || ""} alt="" className="h-44 w-32 rounded-xl object-cover" /> : <BookOpen size={48} className="text-orange-400" />}
                    <span><strong className="block text-xl text-white">{(books.find(book => book.path === lastOpenedBook) || books[0]).title}</strong><span className="mt-2 block text-sm text-zinc-500">{(books.find(book => book.path === lastOpenedBook) || books[0]).author}</span><span className="mt-5 block text-xs text-orange-400">继续阅读 →</span></span>
                  </button>
                ) : <div aria-hidden="true" className="flex-1 flex items-center justify-center text-zinc-500"><BookOpen size={48} /></div>}
              </motion.div>
            )}

            {!isScanning && activeTab === 'library' && (
              <div className="space-y-8">
                <div className="flex flex-wrap items-center gap-3">
                  <label className="flex min-w-64 flex-1 items-center gap-3 rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-zinc-500">
                    <Search size={16} /><input aria-label="搜索书名或作者" value={query} onChange={e => setQuery(e.target.value)} placeholder="搜索书名或作者" className="w-full bg-transparent text-sm text-white outline-none placeholder:text-zinc-600" />
                  </label>
                  <label className="flex items-center gap-2 rounded-xl border border-white/10 bg-white/[0.03] px-3 py-3 text-zinc-400"><List size={15} /><select aria-label="书籍排序" value={sortMode} onChange={e => setSortMode(e.target.value as typeof sortMode)} className="bg-transparent text-sm text-white outline-none"><option value="recent">最近加入</option><option value="title">按书名</option><option value="author">按作者</option></select></label>
                </div>
                <motion.div key="grid" initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="grid grid-cols-2 md:grid-cols-5 xl:grid-cols-7 gap-10">
                {filteredBooks.length === 0 ? <EmptyState /> : filteredBooks.map(b => (
                  <BookCard 
                    key={b.path} 
                    book={b} 
                    onOpen={handleOpenBook}
                    onDelete={handleRemoveBook}
                  />
                ))}
                </motion.div>
              </div>
            )}

            {!isScanning && activeTab === 'catalog' && (
              <OpdsCatalog onImported={async path => handleImportFiles([path])} />
            )}

            {!isScanning && activeTab === 'stats' && (
              <motion.div key="stats" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="max-w-6xl w-full space-y-8 pb-12">
                
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                  <StatCard 
                    icon={<Library className="text-orange-500" />} 
                    label="藏书数量"
                    value={`${stats.totalCount} 卷`} 
                    sub={`${stats.formats} 种文件格式`}
                  />
                  <StatCard 
                    icon={<Timer className="text-blue-500" />} 
                    label="累计阅读时长"
                    value={`${stats.totalReadHours} h`} 
                    sub="按实际阅读时间累计"
                  />
                  <StatCard 
                    icon={<Trophy className="text-yellow-500" />} 
                    label="阅读最多的书"
                    value={stats.longestBook} 
                    sub="按累计时长计算"
                    isTextHeavy
                  />
                  <StatCard 
                    icon={<CalendarDays className="text-emerald-500" />} 
                    label="活跃阅读日" 
                    value={`${stats.activeDays} 天`} 
                    sub="有阅读记录的日期"
                  />
                </div>

                <div className="bg-white/[0.02] border border-white/5 p-8 rounded-[2rem] w-full relative overflow-hidden group">
                  <div className="flex items-center justify-between mb-8 relative z-10">
                    <div className="flex items-center gap-3">
                      <Activity className="text-orange-500" />
                      <h2 className="text-lg font-serif text-white">阅读趋势</h2>
                    </div>
                    <div className="flex gap-2 bg-black/50 p-1 rounded-xl border border-white/5">
                      <button 
                        onClick={() => setChartRange('30days')}
                        className={`px-4 py-1.5 text-[10px] font-bold rounded-lg transition-colors ${chartRange === '30days' ? 'bg-white/10 text-white shadow' : 'text-zinc-500 hover:text-white'}`}
                      >
                        近 30 天
                      </button>
                      <button 
                        onClick={() => setChartRange('year')}
                        className={`px-4 py-1.5 text-[10px] font-bold rounded-lg transition-colors ${chartRange === 'year' ? 'bg-white/10 text-white shadow' : 'text-zinc-500 hover:text-white'}`}
                      >
                        今年
                      </button>
                    </div>
                  </div>
                  
                  <div className="h-72 w-full">
                    <ResponsiveContainer width="100%" height="100%">
                      <AreaChart data={stats.readingTrendData} margin={{ top: 10, right: 0, left: -20, bottom: 0 }}>
                        <defs>
                          <linearGradient id="colorHours" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="5%" stopColor="#f97316" stopOpacity={0.3}/>
                            <stop offset="95%" stopColor="#f97316" stopOpacity={0}/>
                          </linearGradient>
                        </defs>
                        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="rgba(255,255,255,0.05)" />
                        <XAxis 
                          dataKey="date" 
                          axisLine={false} 
                          tickLine={false} 
                          tick={{ fill: '#71717a', fontSize: 10, fontWeight: 600 }}
                          dy={10}
                        />
                        <YAxis 
                          axisLine={false} 
                          tickLine={false} 
                          tick={{ fill: '#71717a', fontSize: 10, fontWeight: 600 }}
                          dx={-10}
                        />
                        <Tooltip 
                          contentStyle={{ 
                            backgroundColor: 'rgba(5, 5, 5, 0.9)', 
                            backdropFilter: 'blur(10px)',
                            border: '1px solid rgba(255,255,255,0.1)', 
                            borderRadius: '16px',
                            color: '#fff',
                            boxShadow: '0 10px 40px -10px rgba(0,0,0,0.5)'
                          }}
                          itemStyle={{ color: '#f97316', fontWeight: 'bold' }}
                          labelStyle={{ color: '#71717a', fontSize: '10px', textTransform: 'uppercase', letterSpacing: '0.1em', marginBottom: '4px' }}
                        />
                        <Area 
                          type="monotone" 
                          dataKey="hours" 
                          name="阅读时长 (h)"
                          stroke="#f97316" 
                          strokeWidth={3}
                          fillOpacity={1} 
                          fill="url(#colorHours)" 
                          activeDot={{ r: 6, fill: '#f97316', stroke: '#050505', strokeWidth: 4 }}
                        />
                      </AreaChart>
                    </ResponsiveContainer>
                  </div>
                </div>

                <div className="bg-white/[0.02] border border-white/5 p-8 rounded-[2rem]">
                  <div className="flex items-center gap-3 border-b border-white/5 pb-6 mb-6">
                    <HardDrive className="text-zinc-400" size={20} />
                    <h2 className="text-sm font-bold text-white tracking-widest">书籍文件大小（共 {stats.totalSize} MB）</h2>
                  </div>
                  <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4">
                    {Object.entries(stats.formatDist).map(([fmt, count]: any) => (
                      <div key={fmt} className="bg-black/40 p-4 rounded-2xl border border-white/5 hover:border-white/20 transition-colors group cursor-default">
                          <p className="text-[10px] text-zinc-600 font-mono uppercase group-hover:text-zinc-400 transition-colors">{fmt}</p>
                          <p className="text-2xl text-white font-serif mt-1">{count}</p>
                      </div>
                    ))}
                  </div>
                </div>
              </motion.div>
            )}

            {!isScanning && activeTab === 'settings' && (
              <motion.div key="settings" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="max-w-3xl space-y-8 pb-12">
                <div className="bg-white/[0.02] border border-white/5 p-8 rounded-[2rem] space-y-6">
                  <h2 className="text-lg font-serif text-white">阅读设置</h2>
                  <div className="flex items-center gap-3 text-sm text-zinc-400"><BookOpen size={18} className="text-orange-400" /> 书籍、阅读位置和统计保存在本机。</div>
                  <p className="text-xs text-zinc-600">支持 EPUB、PDF、MOBI/KF8、FB2/FBZ、CBZ、TXT 和 Markdown。</p>
                </div>
                <div className="bg-white/[0.02] border border-white/5 p-8 rounded-[2rem] space-y-5">
                  <div>
                    <h2 className="text-lg font-serif text-white">备份与恢复</h2>
                    <p className="mt-2 text-sm leading-6 text-zinc-400">备份包含书架索引、阅读位置、书签、标注、统计和目录来源。书籍原文件不包含在备份中；换设备后需重新导入书籍。备份文件含本机路径和目录地址，请妥善保存。</p>
                  </div>
                  <div className="flex flex-wrap gap-3">
                    <button type="button" onClick={() => void exportDataBackup()} className="inline-flex items-center gap-2 rounded-xl bg-white px-4 py-3 text-sm font-semibold text-black hover:bg-orange-400"><Download size={16} />导出备份</button>
                    <button type="button" onClick={() => backupInput.current?.click()} className="inline-flex items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-zinc-200 hover:bg-white/10"><Upload size={16} />导入并合并</button>
                    <input ref={backupInput} type="file" accept=".json,application/json" aria-label="选择 HyesRead 备份文件" className="hidden" onChange={event => void importDataBackup(event.target.files?.[0])} />
                  </div>
                  {backupMessage && <p role="status" className="text-sm text-emerald-300">{backupMessage}</p>}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </section>
      </main>
    </div>
  );
}
function BookCard({ book, onOpen, onDelete }: { book: Book, onOpen: (path: string) => void, onDelete: (path: string) => void }) {
  return (
    <motion.div 
      whileHover={{ y: -8 }} 
      className="group relative"
    >
      <button type="button" aria-label={`打开《${book.title}》`} onClick={() => onOpen(book.path)} className="block w-full text-left">
        <div className="aspect-[3/4.2] bg-zinc-900 rounded-2xl overflow-hidden relative border border-white/5 group-hover:border-orange-500/40 transition-all shadow-lg group-hover:shadow-orange-500/10">
        {book.cover ? (
          <img src={book.cover} className="w-full h-full object-cover" />
        ) : (
          <div className="h-full flex flex-col items-center justify-between p-6 bg-gradient-to-br from-zinc-800 to-black">
             <div className="w-full flex justify-between text-[8px] font-mono text-zinc-500">
                <span>{book.format}</span>
                <BookIcon size={12} />
             </div>
             <span className="text-4xl italic font-black text-white/10">{book.title[0]}</span>
             <div className="w-full text-[10px] font-bold text-zinc-400 line-clamp-2 text-center leading-tight">
                {book.title}
             </div>
          </div>
        )}
        <div className="absolute top-3 right-3 text-[8px] bg-black/60 backdrop-blur-md px-2 py-0.5 rounded border border-white/10 text-orange-400 font-mono">
          {book.format}
        </div>
        </div>
        <h3 className="text-[10px] font-bold mt-4 line-clamp-1 text-zinc-500 group-hover:text-white transition-colors">{book.title}</h3>
      </button>
      <div className="absolute top-2 left-2 z-20 flex gap-2 opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100 [@media(hover:none)]:opacity-100 [@media(max-width:640px)]:opacity-100">
        <button type="button" aria-label={`从书架移除《${book.title}》`} onClick={e => { e.stopPropagation(); void onDelete(book.path); }} className="rounded-full bg-zinc-800/90 p-2 text-white shadow-xl hover:bg-zinc-700"><BookIcon size={12} /></button>
      </div>
    </motion.div>
  );
}

function NavIcon({ icon, label, active, onClick, className = "" }: { icon: React.ReactNode; label: string; active: boolean; onClick: () => void; className?: string }) {
  return (
    <button type="button" aria-label={label} aria-current={active ? "page" : undefined} onClick={onClick} className={`relative p-3 transition-all ${active ? 'text-white' : 'text-zinc-600 hover:text-zinc-400'} ${className}`}>
      {icon}
      {active && <motion.div layoutId="nav-glow" className="absolute -left-4 top-1/2 -translate-y-1/2 w-1 h-6 bg-orange-500 rounded-full shadow-[0_0_15px_rgba(249,115,22,0.8)]" />}
    </button>
  );
}

function StatCard({ icon, label, value, sub, isTextHeavy = false }: any) {
  return (
    <div className="bg-white/[0.02] border border-white/5 p-6 rounded-[2rem] flex flex-col justify-between min-h-[140px] hover:bg-white/[0.03] transition-colors relative overflow-hidden group">
      <div className="absolute -right-6 -top-6 opacity-5 group-hover:opacity-10 transition-opacity scale-150">
        {icon}
      </div>
      <div className="flex items-center justify-between w-full relative z-10">
        <div className="p-2 bg-black/40 rounded-xl border border-white/5">
          {icon}
        </div>
        <p className="text-[10px] text-zinc-600 font-bold uppercase tracking-widest">{sub}</p>
      </div>
      <div className="relative z-10 mt-4">
        <p className="text-[10px] text-zinc-400 font-bold uppercase mb-1">{label}</p>
        <p className={`${isTextHeavy ? 'text-lg line-clamp-2 leading-tight mt-1' : 'text-3xl'} font-serif italic text-white font-black`} title={value}>
          {value}
        </p>
      </div>
    </div>
  );
}

function EmptyState() {
  return <div aria-hidden="true" className="col-span-full h-96 flex items-center justify-center text-zinc-500"><Ghost size={56} /></div>;
}
