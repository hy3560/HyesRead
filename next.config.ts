import type { NextConfig } from "next";

const basePath = process.env.NEXT_BASE_PATH || "";

const nextConfig: NextConfig = {
  output: "export",
  basePath,
  assetPrefix: basePath || "./",

  images: {
    unoptimized: true,
  },

  trailingSlash: false,
};

export default nextConfig;
