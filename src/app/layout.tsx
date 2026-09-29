import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "HyesRead",
  description: "在本机整理书架、阅读电子书并记录进度。",
  icons: { icon: "/favicon.png", apple: "/favicon.png" },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html 
      lang="zh-CN" 
      className="dark"
      style={{ colorScheme: 'dark' }}
    >
      <body className="antialiased bg-[#050505] text-white selection:bg-orange-500/30">
        {children}
      </body>
    </html>
  );
}
