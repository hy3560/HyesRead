"use client";
import { useState } from "react";
import { load } from "@tauri-apps/plugin-store";
import { motion } from "framer-motion";
import { Sparkles, Languages, Volume2, Highlighter, Copy, Loader2 } from "lucide-react";

export const MagicBar = ({ position, selectedText }: { position: { x: number, y: number }, selectedText: string }) => {
  const [isLoading, setIsLoading] = useState(false);

  if (!selectedText) return null;

  const handleReadAloud = async () => {
    if (isLoading || !selectedText) return;
    setIsLoading(true);

    try {
      // ARCH_EVOLUTION: 建立动态配置水合层，告别硬编码
      const store = await load("hyes_master.json");
      const ttsUrl = await store.get<string>("tts_api_url");
      const ttsKey = await store.get<string>("tts_api_key");
      // 容错处理：如果嗅探列表为空，则提供一个通用的基础模型名字兜底
      const ttsModel = await store.get<string>("selected_tts_model") || "tts-1"; 

      if (!ttsUrl) {
        alert("未发现 TTS 服务节点，请先前往设置面板配置 API URL");
        setIsLoading(false);
        return;
      }

      // 智能路由修正：适配标准 OpenAI 格式的 endpoint
      const baseUrl = ttsUrl.replace(/\/$/, "");
      const targetEndpoint = baseUrl.endsWith("/audio/speech") 
        ? baseUrl 
        : `${baseUrl}/audio/speech`;

      // ARCH_EVOLUTION: 升级为标准的 OpenAI Audio API 契约协议，支持 Bearer 鉴权与指定模型
      const response = await fetch(targetEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(ttsKey ? { "Authorization": `Bearer ${ttsKey}` } : {})
        },
        body: JSON.stringify({
          model: ttsModel,
          input: selectedText,
          voice: "alloy", // 默认音色，未来可将其同样抽离至设置中
        })
      });
      
      if (!response.ok) {
        const errText = await response.text();
        throw new Error(`TTS 请求失败 [${response.status}]: ${errText}`);
      }

      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      
      audio.onplay = () => setIsLoading(false);
      audio.onended = () => URL.revokeObjectURL(url);
      
      await audio.play();
    } catch (error) {
      console.error("TTS Error:", error);
      alert("语音合成引擎报错: " + error);
      setIsLoading(false);
    }
  };

  const actions = [
    { icon: <Sparkles size={16} />, label: "AI 解释", color: "text-purple-400", onClick: () => {} },
    { icon: <Languages size={16} />, label: "翻译", color: "text-blue-400", onClick: () => {} },
    { icon: <Highlighter size={16} />, label: "高亮", color: "text-orange-400", onClick: () => {} },
    { 
      icon: isLoading ? <Loader2 size={16} className="animate-spin" /> : <Volume2 size={16} />, 
      label: "朗读", 
      color: "text-green-400", 
      onClick: handleReadAloud 
    },
  ];

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.9, y: 10 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      style={{ left: position.x, top: position.y - 60 }}
      className="fixed z-[100] flex items-center gap-1 p-1.5 bg-zinc-900/80 backdrop-blur-2xl border border-white/10 rounded-full shadow-2xl"
    >
      {actions.map((action) => (
        <button
          key={action.label}
          onClick={action.onClick}
          disabled={isLoading}
          className="flex items-center gap-2 px-3 py-1.5 hover:bg-white/5 rounded-full transition-all group disabled:opacity-50"
        >
          <span className={`${action.color} group-hover:scale-110 transition-transform`}>
            {action.icon}
          </span>
          <span className="text-[10px] uppercase tracking-tighter text-zinc-400 group-hover:text-zinc-200">
            {action.label}
          </span>
        </button>
      ))}
      <div className="w-px h-4 bg-white/10 mx-1" />
      <button 
        onClick={() => navigator.clipboard.writeText(selectedText)}
        className="p-1.5 hover:bg-white/5 rounded-full text-zinc-500"
      >
        <Copy size={14} />
      </button>
    </motion.div>
  );
};