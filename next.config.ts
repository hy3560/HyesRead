import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: 'export', 
  assetPrefix: './',
  
  images: {
    unoptimized: true,
  },

  trailingSlash: false,
};

export default nextConfig;
