import type { Metadata } from "next";
import { Inter, Playfair_Display } from "next/font/google";
import "./globals.css";

// 配置无衬线字体 (Sans) - 对应页面中的 font-sans
const inter = Inter({ 
  subsets: ["latin"],
  variable: "--font-sans",
  display: "swap",
});

// 配置艺术衬线字体 (Serif) - 对应页面中的 font-serif
const playfair = Playfair_Display({
  subsets: ["latin"],
  style: ['italic', 'normal'],
  variable: "--font-serif",
  display: "swap",
});

export const metadata: Metadata = {
  title: "HyesRead - Zenith Reader",
  description: "Aesthetics of Silence | Universal Reading Experience",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html 
      lang="zh-CN" 
      className={`dark ${inter.variable} ${playfair.variable}`}
      style={{ colorScheme: 'dark' }}
    >
      <body className="antialiased bg-[#050505] text-white selection:bg-orange-500/30">
        {children}
      </body>
    </html>
  );
}