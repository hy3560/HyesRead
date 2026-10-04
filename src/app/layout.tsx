import type { Metadata } from "next";
import "./globals.css";
import OpenFilesBridge from "../components/OpenFilesBridge";
import AppDiagnostics from "../components/AppDiagnostics";
import AccessibilityPreferences from "../components/AccessibilityPreferences";

export const metadata: Metadata = {
  title: "HyesRead",
  description: "在本机整理书架、阅读电子书并记录进度。",
  icons: {
    icon: `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/favicon.png`,
    apple: `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/favicon.png`,
  },
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
        <AppDiagnostics />
        <a href="#main-content" className="skip-link">跳到主要内容</a>
        <AccessibilityPreferences>
          <OpenFilesBridge />
          {children}
        </AccessibilityPreferences>
      </body>
    </html>
  );
}
