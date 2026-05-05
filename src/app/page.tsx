"use client";

import { useEffect, useState, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { load } from "@tauri-apps/plugin-store";
import { motion, AnimatePresence } from "framer-motion";
import { 
  Library, Settings2, Loader2, Ghost, 
  RefreshCw, Clock, NotebookPen, 
  HardDrive, FileType, FolderPlus, FilePlus, Book as BookIcon,
  BookOpen, Cpu, Server, Key, Volume2, Timer, Trophy, Activity, CalendarDays,
  Trash2, Save
} from "lucide-react";
import { 
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer 
} from "recharts";

type ViewType = 'home' | 'library' | 'stats' | 'settings';

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

export default function HyesReadMaster() {
  const [books, setBooks] = useState<Book[]>([]);
  const [sessions, setSessions] = useState<ReadingSession[]>([]);
  const [chartRange, setChartRange] = useState<'30days' | 'year'>('30days');

  const [activeTab, setActiveTab] = useState<ViewType>('library');
  const [isScanning, setIsScanning] = useState(false);

  const [apiUrl, setApiUrl] = useState("https://api.openai.com/v1");
  const [apiKey, setApiKey] = useState("");
  const [models, setModels] = useState<string[]>([]);
  const [selectedModel, setSelectedModel] = useState("");
  const [isFetchingModels, setIsFetchingModels] = useState(false);

  const [ttsApiUrl, setTtsApiUrl] = useState("https://api.openai.com/v1");
  const [ttsApiKey, setTtsApiKey] = useState("");
  const [ttsModels, setTtsModels] = useState<string[]>([]);
  const [selectedTtsModel, setSelectedTtsModel] = useState("");
  const [isFetchingTts, setIsFetchingTts] = useState(false);

  const addReadingSession = async (bookPath: string, durationMinutes: number) => {
    const d = new Date();
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const dateStr = `${y}-${m}-${day}`;
    
    const newSession: ReadingSession = { date: dateStr, duration: durationMinutes, bookPath };
    const newSessions = [...sessions, newSession];
    setSessions(newSessions);

    const statsStore = await load("hyes_stats.json");
    await statsStore.set("sessions", newSessions);
    await statsStore.save();
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
       else if (longestBookPath === 'dev_test') longestBookTitle = "开发测试虚拟书籍";
       else longestBookTitle = "已移除的书籍"; 
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

  useEffect(() => {
    (async () => {
      try {
        const store = await load("hyes_master.json");
        const path = await store.get<string>("library_path");
        const discretePaths = await store.get<string[]>("discrete_files");
        
        const storedUrl = await store.get<string>("api_url");
        const storedKey = await store.get<string>("api_key");
        const storedModel = await store.get<string>("selected_model");
        if (storedUrl) setApiUrl(storedUrl);
        if (storedKey) setApiKey(storedKey);
        if (storedModel) setSelectedModel(storedModel);

        const storedTtsUrl = await store.get<string>("tts_api_url");
        const storedTtsKey = await store.get<string>("tts_api_key");
        const storedTtsModel = await store.get<string>("selected_tts_model");
        if (storedTtsUrl) setTtsApiUrl(storedTtsUrl);
        if (storedTtsKey) setTtsApiKey(storedTtsKey);
        if (storedTtsModel) setSelectedTtsModel(storedTtsModel);

        if (discretePaths && discretePaths.length > 0) {
           invoke("import_files", { filePaths: discretePaths }).then((res: any) => {
               setBooks(prev => {
                   const map = new Map(prev.map((b: Book) => [b.path, b]));
                   res.forEach((b: Book) => map.set(b.path, b));
                   return Array.from(map.values());
               });
           }).catch(console.error);
        }

        const statsStore = await load("hyes_stats.json");
        const storedSessions = await statsStore.get<ReadingSession[]>("sessions") || [];
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
          const map = new Map(prev.map(b => [b.path, b]));
          result.forEach(b => map.set(b.path, b));
          return Array.from(map.values());
      });
      const store = await load("hyes_master.json");
      await store.set("library_path", targetPath);
      await store.save();
    } catch (e: any) { 
      console.error(e); 
      alert("书库嗅探异常: " + e);
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
        
        const store = await load("hyes_master.json");
        const existingPaths: string[] = (await store.get<string[]>("discrete_files")) || [];
        const newPaths = Array.from(new Set([...existingPaths, ...paths]));
        await store.set("discrete_files", newPaths);
        await store.save();
    } catch (e: any) {
        alert("文件导入异常: " + e);
    } finally {
        setIsScanning(false);
    }
  };

  const handleOpenBook = async (path: string) => {
    try {
      await invoke("open_book", { path });
      addReadingSession(path, 1); 
    } catch (err) {
      alert("无法唤起系统应用，请确保你的系统已安装能打开该格式的软件: " + err);
    }
  };

  const handleDeleteBook = async (path: string) => {
    setBooks(prev => prev.filter(bk => bk.path !== path));
    try {
      const store = await load("hyes_master.json");
      const existingPaths: string[] = (await store.get<string[]>("discrete_files")) || [];
      if (existingPaths.includes(path)) {
        await store.set("discrete_files", existingPaths.filter(p => p !== path));
        await store.save();
      }
    } catch(e) { console.error("清理散装列表失败", e); }
  };

  const handleSaveSettings = async () => {
    try {
      const store = await load("hyes_master.json");
      await store.set("api_url", apiUrl);
      await store.set("api_key", apiKey);
      await store.set("tts_api_url", ttsApiUrl);
      await store.set("tts_api_key", ttsApiKey);
      await store.save();
      alert("保存成功");
    } catch (e) {
      alert("保存失败");
    }
  };

  const handleFetchModels = async () => {
    if (!apiUrl || !apiKey) return alert("请先填写 AI 接口地址与密钥");
    setIsFetchingModels(true);
    try {
      const fetchedModels: string[] = await invoke("fetch_remote_models", { apiUrl, apiKey });
      setModels(fetchedModels);
      if (fetchedModels.length > 0 && !fetchedModels.includes(selectedModel)) {
        setSelectedModel(fetchedModels[0]);
      }
      const store = await load("hyes_master.json");
      await store.set("api_url", apiUrl);
      await store.set("api_key", apiKey);
      if (fetchedModels.length > 0) await store.set("selected_model", fetchedModels[0]);
      await store.save();
    } catch (e: any) {
      alert("AI 模型嗅探失败: " + e);
    } finally { setIsFetchingModels(false); }
  };

  const handleFetchTtsModels = async () => {
    if (!ttsApiUrl || !ttsApiKey) return alert("请先填写 TTS 接口地址与密钥");
    setIsFetchingTts(true);
    try {
      const fetchedModels: string[] = await invoke("fetch_remote_models", { apiUrl: ttsApiUrl, apiKey: ttsApiKey });
      setTtsModels(fetchedModels);
      if (fetchedModels.length > 0 && !fetchedModels.includes(selectedTtsModel)) {
        setSelectedTtsModel(fetchedModels[0]);
      }
      const store = await load("hyes_master.json");
      await store.set("tts_api_url", ttsApiUrl);
      await store.set("tts_api_key", ttsApiKey);
      if (fetchedModels.length > 0) await store.set("selected_tts_model", fetchedModels[0]);
      await store.save();
    } catch (e: any) {
      alert("TTS 模型嗅探失败: " + e);
    } finally { setIsFetchingTts(false); }
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
          <NavIcon icon={<Clock size={20} />} active={activeTab === 'home'} onClick={() => setActiveTab('home')} />
          <NavIcon icon={<Library size={20} />} active={activeTab === 'library'} onClick={() => setActiveTab('library')} />
        </div>
        <div className="mb-4 flex flex-col gap-8">
           <NavIcon icon={<NotebookPen size={20} />} active={activeTab === 'stats'} onClick={() => setActiveTab('stats')} className="text-blue-400" />
           <NavIcon icon={<Settings2 size={20} />} active={activeTab === 'settings'} onClick={() => setActiveTab('settings')} />
        </div>
      </nav>

      <main className="flex-1 flex flex-col overflow-hidden relative">
        <header className="h-24 flex items-center justify-between px-12 border-b border-white/5 z-20 shrink-0">
          <div>
            <h1 className="text-2xl font-serif italic text-white">Hyes Read</h1>
            <p className="text-[10px] uppercase tracking-[0.4em] text-zinc-600">Unified Adapter Engine Active</p>
          </div>
          
          <div className="flex items-center gap-4">
            <button onClick={async () => {
                const paths = await openDialog({ 
                    multiple: true, 
                    directory: false,
                    filters: [{ name: 'Books', extensions: ['epub', 'mobi', 'azw3', 'kf8', 'pdf', 'txt', 'cbz', 'cbr', 'doc', 'docx', 'rtf', 'md', 'fb2'] }]
                });
                if (paths && Array.isArray(paths)) handleImportFiles(paths as string[]);
              }} className="flex items-center gap-2 bg-white/5 text-zinc-300 border border-white/10 px-5 py-2.5 rounded-2xl font-bold text-xs hover:bg-white/10 hover:text-white transition-all z-20">
                <FilePlus size={16} />
                <span>添加文件</span>
            </button>

            <button onClick={async () => {
                const p = await openDialog({ directory: true });
                if (p) handleScan(p as string);
              }} className="flex items-center gap-2 bg-white text-black px-5 py-2.5 rounded-2xl font-black text-xs hover:bg-orange-500 hover:text-white transition-all z-20 shadow-[0_0_15px_rgba(255,255,255,0.1)] hover:shadow-[0_0_20px_rgba(249,115,22,0.4)]">
                <FolderPlus size={16} />
                <span>导入书库</span>
            </button>
          </div>
        </header>

        <section className="flex-1 overflow-y-auto p-12 custom-scrollbar relative">
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
                <p className="text-xs tracking-[0.5em] text-white font-bold uppercase">嗅探引擎超载运转中</p>
              </motion.div>
            )}

            {!isScanning && activeTab === 'home' && (
              <motion.div key="home" initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="h-full w-full flex flex-col">
                <div className="mb-6">
                  <h2 className="text-xl font-serif text-white border-b border-white/5 pb-4">正在阅读的书籍</h2>
                </div>
                <div className="flex-1 flex flex-col items-center justify-center opacity-20 gap-4">
                  <BookOpen size={48} />
                  <p className="text-[10px] tracking-widest uppercase italic">暂无</p>
                </div>
              </motion.div>
            )}

            {!isScanning && activeTab === 'library' && (
              <motion.div key="grid" initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="grid grid-cols-2 md:grid-cols-5 xl:grid-cols-7 gap-10">
                {books.length === 0 ? <EmptyState /> : books.map(b => (
                  <BookCard 
                    key={b.path} 
                    book={b} 
                    onOpen={handleOpenBook}
                    onDelete={handleDeleteBook}
                  />
                ))}
              </motion.div>
            )}

            {!isScanning && activeTab === 'stats' && (
              <motion.div key="stats" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="max-w-6xl w-full space-y-8 pb-12">
                
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                  <StatCard 
                    icon={<Library className="text-orange-500" />} 
                    label="总藏书维度" 
                    value={`${stats.totalCount} 卷`} 
                    sub={`${stats.formats} 种介质格式`}
                  />
                  <StatCard 
                    icon={<Timer className="text-blue-500" />} 
                    label="沉浸阅读时长" 
                    value={`${stats.totalReadHours} h`} 
                    sub={`引擎真实记录`}
                  />
                  <StatCard 
                    icon={<Trophy className="text-yellow-500" />} 
                    label="最长深度阅读" 
                    value={stats.longestBook} 
                    sub="史诗级里程碑"
                    isTextHeavy
                  />
                  <StatCard 
                    icon={<CalendarDays className="text-emerald-500" />} 
                    label="活跃阅读日" 
                    value={`${stats.activeDays} 天`} 
                    sub="独立日活记录"
                  />
                </div>

                <div className="bg-white/[0.02] border border-white/5 p-8 rounded-[2rem] w-full relative overflow-hidden group">
                  <div className="flex items-center justify-between mb-8 relative z-10">
                    <div className="flex items-center gap-3">
                      <Activity className="text-orange-500" />
                      <h2 className="text-lg font-serif text-white">阅读趋势</h2>
                      <button 
                        onClick={() => addReadingSession(books.length > 0 ? books[0].path : 'dev_test', 60)}
                        className="flex items-center gap-1 px-3 py-1 bg-white/5 hover:bg-orange-500/20 border border-white/10 hover:border-orange-500/50 rounded-lg text-[10px] text-zinc-500 hover:text-orange-400 transition-all ml-4"
                        title="点击此按钮测试真实统计：为今日追加 60 分钟阅读"
                      >
                        <Timer size={10} /> 探针: 测试注入 1h
                      </button>
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
                          labelStyle={{ color: '#71717a', fontSize: '10px', textTransform: 'uppercase', tracking: '0.1em', marginBottom: '4px' }}
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
                    <h2 className="text-sm font-bold text-white tracking-widest">物理资产基盘 (总计: {stats.totalSize} MB)</h2>
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
                  <div className="flex items-center gap-3 border-b border-white/5 pb-4">
                    <Cpu className="text-orange-500" />
                    <h2 className="text-lg font-serif text-white">AI 模型设置</h2>
                  </div>
                  
                  <div className="space-y-4">
                    <div className="space-y-2">
                      <label className="flex items-center gap-2 text-[10px] text-zinc-400 uppercase tracking-widest">
                        <Server size={14} className="text-blue-400" /> 接口地址 (API URL)
                      </label>
                      <input 
                        type="text" value={apiUrl} onChange={(e) => setApiUrl(e.target.value)}
                        placeholder="https://api.openai.com/v1" 
                        className="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-3 text-xs text-white outline-none focus:border-orange-500/50 transition-colors"
                      />
                    </div>
                    <div className="space-y-2">
                      <label className="flex items-center gap-2 text-[10px] text-zinc-400 uppercase tracking-widest">
                        <Key size={14} className="text-emerald-400" /> 密钥 (API KEY)
                      </label>
                      <input 
                        type="password" value={apiKey} onChange={(e) => setApiKey(e.target.value)}
                        placeholder="sk-..." 
                        className="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-3 text-xs text-white outline-none focus:border-orange-500/50 transition-colors"
                      />
                    </div>
                    
                    <button 
                      onClick={handleFetchModels} disabled={isFetchingModels}
                      className="flex items-center justify-center gap-2 w-full bg-white/5 hover:bg-white/10 border border-white/5 text-white px-4 py-3 rounded-xl text-xs font-bold transition-all disabled:opacity-50"
                    >
                      {isFetchingModels ? <Loader2 size={16} className="animate-spin text-orange-500" /> : <RefreshCw size={16} className="text-orange-500" />}
                      嗅探可用模型列表
                    </button>
                    
                    {(models.length > 0 || selectedModel) && (
                      <div className="pt-4 border-t border-white/5 space-y-2">
                        <select 
                           value={selectedModel}
                           onChange={(e) => {
                             setSelectedModel(e.target.value);
                             load("hyes_master.json").then(store => { store.set("selected_model", e.target.value); store.save(); });
                           }}
                           className="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-3 text-xs text-white outline-none focus:border-orange-500/50 appearance-none cursor-pointer"
                        >
                          {models.length > 0 ? models.map(m => <option key={m} value={m}>{m}</option>) : <option value={selectedModel}>{selectedModel}</option>}
                        </select>
                      </div>
                    )}
                  </div>
                </div>

                <div className="bg-white/[0.02] border border-white/5 p-8 rounded-[2rem] space-y-6">
                  <div className="flex items-center gap-3 border-b border-white/5 pb-4">
                    <Volume2 className="text-purple-500" />
                    <h2 className="text-lg font-serif text-white">TTS 模型设置</h2>
                  </div>
                  
                  <div className="space-y-4">
                    <div className="space-y-2">
                      <label className="flex items-center gap-2 text-[10px] text-zinc-400 uppercase tracking-widest">
                        <Server size={14} className="text-blue-400" /> 接口地址 (API URL)
                      </label>
                      <input 
                        type="text" value={ttsApiUrl} onChange={(e) => setTtsApiUrl(e.target.value)}
                        placeholder="https://api.openai.com/v1" 
                        className="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-3 text-xs text-white outline-none focus:border-purple-500/50 transition-colors"
                      />
                    </div>
                    <div className="space-y-2">
                      <label className="flex items-center gap-2 text-[10px] text-zinc-400 uppercase tracking-widest">
                        <Key size={14} className="text-emerald-400" /> 密钥 (API KEY)
                      </label>
                      <input 
                        type="password" value={ttsApiKey} onChange={(e) => setTtsApiKey(e.target.value)}
                        placeholder="sk-..." 
                        className="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-3 text-xs text-white outline-none focus:border-purple-500/50 transition-colors"
                      />
                    </div>
                    
                    <button 
                      onClick={handleFetchTtsModels} disabled={isFetchingTts}
                      className="flex items-center justify-center gap-2 w-full bg-white/5 hover:bg-white/10 border border-white/5 text-white px-4 py-3 rounded-xl text-xs font-bold transition-all disabled:opacity-50"
                    >
                      {isFetchingTts ? <Loader2 size={16} className="animate-spin text-purple-500" /> : <RefreshCw size={16} className="text-purple-500" />}
                      嗅探可用模型列表
                    </button>
                    
                    {(ttsModels.length > 0 || selectedTtsModel) && (
                      <div className="pt-4 border-t border-white/5 space-y-2">
                        <select 
                           value={selectedTtsModel}
                           onChange={(e) => {
                             setSelectedTtsModel(e.target.value);
                             load("hyes_master.json").then(store => { store.set("selected_tts_model", e.target.value); store.save(); });
                           }}
                           className="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-3 text-xs text-white outline-none focus:border-purple-500/50 appearance-none cursor-pointer"
                        >
                          {ttsModels.length > 0 ? ttsModels.map(m => <option key={m} value={m}>{m}</option>) : <option value={selectedTtsModel}>{selectedTtsModel}</option>}
                        </select>
                      </div>
                    )}
                  </div>
                </div>

                <div className="flex justify-end pt-4 pb-8">
                  <button onClick={handleSaveSettings} className="flex items-center gap-2 bg-orange-500 hover:bg-orange-600 text-white px-8 py-3 rounded-2xl font-black text-sm transition-all shadow-[0_0_15px_rgba(249,115,22,0.3)] hover:shadow-[0_0_25px_rgba(249,115,22,0.5)]">
                    <Save size={18} />保存配置
                  </button>
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
  const [isHovered, setIsHovered] = useState(false);

  const handleDeleteClick = async (e: React.MouseEvent) => {
    e.stopPropagation(); 
    if (confirm(`【警告】是否永久删除《${book.title}》？\n\n该操作会销毁你硬盘上的物理文件且不可逆转！`)) {
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
      className="group cursor-pointer relative"
      onClick={() => onOpen(book.path)}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      <div className="aspect-[3/4.2] bg-zinc-900 rounded-2xl overflow-hidden relative border border-white/5 group-hover:border-orange-500/40 transition-all shadow-lg group-hover:shadow-orange-500/10">
        <AnimatePresence>
          {isHovered && (
            <motion.button 
              initial={{ opacity: 0, scale: 0.8 }} 
              animate={{ opacity: 1, scale: 1 }} 
              exit={{ opacity: 0, scale: 0.8 }}
              onClick={handleDeleteClick}
              className="absolute top-2 left-2 z-20 bg-red-500/90 hover:bg-red-500 text-white p-2 rounded-full backdrop-blur shadow-xl transition-colors"
              title="物理抹除文件"
            >
              <Trash2 size={12} />
            </motion.button>
          )}
        </AnimatePresence>

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
    </motion.div>
  );
}

function NavIcon({ icon, active, onClick, className = "" }: any) {
  return (
    <div onClick={onClick} className={`relative p-3 cursor-pointer transition-all ${active ? 'text-white' : 'text-zinc-600 hover:text-zinc-400'} ${className}`}>
      {icon}
      {active && <motion.div layoutId="nav-glow" className="absolute -left-4 top-1/2 -translate-y-1/2 w-1 h-6 bg-orange-500 rounded-full shadow-[0_0_15px_rgba(249,115,22,0.8)]" />}
    </div>
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
  return <div className="col-span-full h-96 flex flex-col items-center justify-center opacity-20 gap-4"><Ghost size={64} /><p className="text-[10px] tracking-widest uppercase italic">等待书库导入...</p></div>;
}