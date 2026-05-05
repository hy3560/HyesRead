import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface ReaderSettings {
  fontSize: number;
  lineHeight: number;
  theme: 'light' | 'dark' | 'sepia';
  fontFamily: string;
}

interface SettingsStore extends ReaderSettings {
  update: (newSettings: Partial<ReaderSettings>) => void;
}

export const useSettingsStore = create<SettingsStore>()(
  persist(
    (set) => ({
      fontSize: 18,
      lineHeight: 1.5,
      theme: 'light',
      fontFamily: 'system-ui',
      update: (newSettings) => set((state) => ({ ...state, ...newSettings })),
    }),
    { name: 'hyes-read-settings' }
  )
);

export const useReaderEngine = (filePath: string) => {
  const getFormat = () => filePath.split('.').pop()?.toLowerCase();

  // 根据后缀分发解析内核
  const render = async (container: HTMLElement) => {
    const format = getFormat();
    
    switch (format) {
      case 'epub':
      case 'mobi':
      case 'azw3':
        // ARCH_EVOLUTION: 调用 foliate-js 内核（假设已集成）
        // Foliate 能原生处理 MOBI/KF8 到 EPUB DOM 的转换
        return "EPUB_RENDERER";
      case 'pdf':
        return "PDF_RENDERER";
      case 'txt':
        return "TEXT_RENDERER";
      default:
        throw new Error("Unsupported Format");
    }
  };

  return { render, format: getFormat() };
};