"use client";

import { useEffect, type ReactNode } from "react";
import { MotionConfig } from "framer-motion";

export default function AccessibilityPreferences({ children }: { children: ReactNode }) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!event.ctrlKey || event.altKey || event.metaKey || event.shiftKey || event.key !== "F10") return;
      const main = document.getElementById("main-content");
      if (!(main instanceof HTMLElement)) return;
      event.preventDefault();
      main.focus({ preventScroll: false });
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  return <MotionConfig reducedMotion="user">{children}</MotionConfig>;
}
