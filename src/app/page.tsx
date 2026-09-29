"use client";

import { useEffect, useState, useMemo } from "react";
import { invoke, isDesktop, readValue, writeValue } from "../lib/platform";
import { getBrowserBook, isBrowserBook, removeBrowserBook, saveBrowserBook } from "../lib/browserBooks";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { 
  Library, Settings2, Loader2, Ghost, 
  Clock, NotebookPen,
  HardDrive, FileType, FolderPlus, FilePlus, Book as BookIcon,
  BookOpen, Timer, Trophy, Activity, CalendarDays,
  Trash2, Search, List, Save
} from "lucide-react";
import { 
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer 
} from "recharts";

type ViewType = 'home' | 'library' | 'stats' | 'settings';

interface Book {
  title: string; author: string; path: string; format: string; size: number; cover: string | null; isFile?: boolean;
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
        setLastOpenedBook(await readValue("hyes_master.json", "last_opened_book", ""));
        
        if (discretePaths && discretePaths.length > 0) {
          if (isDesktop()) {
            invoke<Book[]>("import_files", { filePaths: discretePaths }).then(res => setBooks(prev => mergeBooks(prev, res))).catch(console.error);
          } else {
            const restored = await Promise.all(discretePaths.filter(isBrowserBook).map(async path => {
              const file = await getBrowserBook(path);
              return file ? { title: file.name.replace(/\.[^.]+$/, ""), author: "", path, format: file.name.split(".").pop()?.toUpperCase() || "BOOK", size: file.size / 1048576, cover: null, isFile: true } satisfies Book : null;
            }));
            setBooks(prev => mergeBooks(prev, restored.filter(book => book !== null)));
          }
        }

        const storedSessions = await readValue<ReadingSession[]>("hyes_stats.json", "sessions", []);
        setSessions(storedSessions);

        if (path) handleScan(path);
      } catch (e) { console.error(e); }
    })();
  }, []);

  const handleScan = async (targetPath: string) => {
    setIsScanning(true);
    try {
      const result: Book[] = await invoke("scan_library", { folderPath: targetPath });
      setBooks(prev => {
          const normalizedRoot = targetPath.replace(/[\\/]+$/, "").toLocaleLowerCase();
          const insideRoot = (path: string) => {
            const normalized = path.toLocaleLowerCase();
            return normalized === normalizedRoot || normalized.startsWith(normalizedRoot + "\\") || normalized.startsWith(normalizedRoot + "/");
          };
          return mergeBooks(prev.filter(book => !insideRoot(book.path)), result);
      });
      await writeValue("hyes_master.json", "library_path", targetPath);
    } catch (e: any) { 
      console.error(e); 
      alert("扫描书库失败: " + e);
    }
    finally { setIsScanning(false); }
  };

  const handleImportFiles = async (paths: string[]) => {
    setIsScanning(true);
    try {
        const result: Book[] = await invoke("import_files", { filePaths: paths });
        setBooks(prev => {
            const map = new Map(prev.map(b => [b.path, b]));
            result.forEach(b => map.set(b.path, b));
            return Array.from(map.values());
        });
        
        const existingPaths = await readValue<string[]>("hyes_master.json", "discrete_files", []);
        const newPaths = Array.from(new Set([...existingPaths, ...paths]));
        await writeValue("hyes_master.json", "discrete_files", newPaths);
    } catch (e: any) {
        alert("文件导入异常: " + e);
    } finally {
        setIsScanning(false);
    }
  };

  const handleOpenBook = async (path: string) => {
    if (isDesktop()) {
      try { await invoke("prepare_book_read", { path }); }
      catch (e) { alert(`无法打开这本书：${e}`); return; }
    }
    await writeValue("hyes_master.json", "last_opened_book", path);
    setLastOpenedBook(path);
    router.push(`/reader?path=${encodeURIComponent(path)}`);
  };

  const handleDeleteBook = async (path: string) => {
    setBooks(prev => prev.filter(bk => bk.path !== path));
    try {
      const existingPaths = await readValue<string[]>("hyes_master.json", "discrete_files", []);
      if (existingPaths.includes(path)) {
        await writeValue("hyes_master.json", "discrete_files", existingPaths.filter(p => p !== path));
      }
    } catch(e) { console.error("清理散装列表失败", e); }
  };

  const handleRemoveBook = async (path: string) => {
    setBooks(prev => prev.filter(book => book.path !== path));
    try {
      const existingPaths = await readValue<string[]>("hyes_master.json", "discrete_files", []);
      await writeValue("hyes_master.json", "discrete_files", existingPaths.filter(item => item !== path));
    } catch (e) { console.error("从书库移除失败", e); }
    if (isBrowserBook(path)) await removeBrowserBook(path);
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
                    const book: Book = { title: file.name.replace(/\.[^.]+$/, ""), author: "", path: url, format: file.name.split(".").pop()?.toUpperCase() || "BOOK", size: file.size / 1048576, cover: null, isFile: true };
                    setBooks(prev => [book, ...prev.filter(item => item.path !== url)]);
                    const existing = await readValue<string[]>("hyes_master.json", "discrete_files", []);
                    await writeValue("hyes_master.json", "discrete_files", Array.from(new Set([...existing, url])));
                  }
                  return;
                }
                const paths = await openDialog({ 
                    multiple: true, 
                    directory: false,
                    filters: [{ name: 'Books', extensions: ['epub', 'mobi', 'azw3', 'kf8', 'pdf', 'txt', 'md', 'cbz', 'fb2', 'fbz'] }]
                });
                if (paths && Array.isArray(paths)) handleImportFiles(paths as string[]);
              }} aria-label="添加文件" className="flex items-center gap-2 bg-white/5 text-zinc-300 border border-white/10 px-5 py-2.5 rounded-2xl font-bold text-xs hover:bg-white/10 hover:text-white transition-all z-20 max-[640px]:h-11 max-[640px]:w-11 max-[640px]:justify-center max-[640px]:p-0">
                <FilePlus size={16} />
                <span className="max-[640px]:hidden">添加文件</span>
            </button>

            {isDesktop() && <button onClick={async () => {
                const p = await openDialog({ directory: true });
                if (p) handleScan(p as string);
              }} aria-label="导入书库" className="flex items-center gap-2 bg-white text-black px-5 py-2.5 rounded-2xl font-black text-xs hover:bg-orange-500 hover:text-white transition-all z-20 shadow-[0_0_15px_rgba(255,255,255,0.1)] hover:shadow-[0_0_20px_rgba(249,115,22,0.4)] max-[640px]:h-11 max-[640px]:w-11 max-[640px]:justify-center max-[640px]:p-0">
                <FolderPlus size={16} />
                <span className="max-[640px]:hidden">导入书库</span>
            </button>}
          </div>
        </header>

        <section className="flex-1 overflow-y-auto p-12 custom-scrollbar relative max-[640px]:p-4">
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
              </motion.div>
            )}
          </AnimatePresence>
        </section>
      </main>
    </div>
  );
}
function BookCard({ book, onOpen, onDelete }: { book: Book, onOpen: (path: string) => void, onDelete: (path: string) => void }) {
  const handleDeleteClick = async (e: React.MouseEvent) => {
    e.stopPropagation(); 
    if (book.isFile) { onDelete(book.path); return; }
    if (confirm(`确定永久删除《${book.title}》？这会删除硬盘上的原文件。`)) {
      try {
        await invoke("delete_book", { path: book.path });
        onDelete(book.path);
      } catch (err) {
        alert(err);
      }
    }
  };

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
        <button type="button" aria-label={`从书架移除《${book.title}》`} onClick={() => onDelete(book.path)} className="rounded-full bg-zinc-800/90 p-2 text-white shadow-xl hover:bg-zinc-700"><BookIcon size={12} /></button>
        <button
          type="button"
          aria-label={`永久删除《${book.title}》文件`}
          onClick={handleDeleteClick}
          className="rounded-full bg-red-500/90 p-2 text-white shadow-xl hover:bg-red-500"
        ><Trash2 size={12} /></button>
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
