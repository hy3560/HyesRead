"use client";
import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";

export const AISettings = () => {
  const [config, setConfig] = useState({ url: "", key: "", models: [] });

  const probeModels = async () => {
    try {
      const models = await invoke("fetch_ai_models", { apiUrl: config.url, apiKey: config.key });
      setConfig({ ...config, models: models as any });
    } catch (e) {
      alert("探查失败，请检查 API 地址");
    }
  };

  return (
    <div className="p-8 space-y-8 max-w-2xl mx-auto">
      <section>
        <h3 className="text-zinc-100 font-serif italic text-xl mb-4">AI Intelligence</h3>
        <div className="space-y-4">
          <div className="flex flex-col gap-1">
            <label className="text-[10px] text-zinc-500 uppercase tracking-widest">Endpoint URL</label>
            <input 
              value={config.url}
              onChange={(e) => setConfig({...config, url: e.target.value})}
              placeholder="https://api.openai.com/v1"
              className="bg-zinc-900 border border-white/5 p-3 rounded-lg focus:outline-none focus:border-orange-500/50 transition-colors"
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-[10px] text-zinc-500 uppercase tracking-widest">API Key</label>
            <input 
              type="password"
              value={config.key}
              onChange={(e) => setConfig({...config, key: e.target.value})}
              className="bg-zinc-900 border border-white/5 p-3 rounded-lg focus:outline-none"
            />
          </div>
          <button 
            onClick={probeModels}
            className="w-full py-3 bg-zinc-100 text-black text-xs font-bold uppercase tracking-widest hover:bg-orange-500 hover:text-white transition-all"
          >
            Probe Available Models
          </button>
        </div>
      </section>

      {config.models.length > 0 && (
        <section className="animate-in fade-in slide-in-from-top-4 duration-700">
          <label className="text-[10px] text-zinc-500 uppercase tracking-widest mb-2 block">Detected Models</label>
          <div className="grid grid-cols-2 gap-2">
            {config.models.map((m: any) => (
              <div key={m.id} className="p-3 bg-white/5 border border-white/5 rounded text-[10px] flex justify-between items-center">
                <span className="text-zinc-300 font-mono">{m.id}</span>
                <span className="text-zinc-600 italic">{m.provider}</span>
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
};