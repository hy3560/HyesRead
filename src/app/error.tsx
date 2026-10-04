"use client";

import { useEffect } from "react";
import { recordDiagnosticEvent } from "../lib/diagnostics";

export default function ErrorPage({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    void recordDiagnosticEvent("error", error, "next-error-boundary");
  }, [error]);

  return (
    <main id="main-content" tabIndex={-1} className="flex min-h-screen items-center justify-center bg-[#050505] p-6 text-zinc-200">
      <section role="alert" className="w-full max-w-md rounded-3xl border border-white/10 bg-white/[0.03] p-8">
        <h1 className="text-xl font-semibold text-white">HyesRead 暂时无法显示此页面</h1>
        <p className="mt-3 text-sm leading-6 text-zinc-400">故障信息已保存在本机诊断记录中。可以重试当前页面；若问题重复出现，可在设置中导出诊断报告。</p>
        <button type="button" onClick={reset} className="mt-6 rounded-xl bg-white px-4 py-2.5 text-sm font-semibold text-black hover:bg-orange-400">重试</button>
      </section>
    </main>
  );
}
