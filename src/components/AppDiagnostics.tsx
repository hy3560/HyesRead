"use client";

import { useEffect } from "react";
import { installGlobalDiagnostics } from "../lib/diagnostics";

export default function AppDiagnostics() {
  useEffect(() => installGlobalDiagnostics(), []);
  return null;
}
