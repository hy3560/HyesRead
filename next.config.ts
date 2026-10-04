import type { NextConfig } from "next";
import { readFileSync } from "node:fs";

const basePath = process.env.NEXT_BASE_PATH || "";
const packageVersion = (JSON.parse(readFileSync(new URL("./package.json", import.meta.url), "utf8")) as { version?: string }).version || "unknown";

const nextConfig: NextConfig = {
  output: "export",
  basePath,
  assetPrefix: basePath || "./",
  env: {
    NEXT_PUBLIC_APP_VERSION: packageVersion,
  },

  images: {
    unoptimized: true,
  },

  trailingSlash: false,
};

export default nextConfig;
