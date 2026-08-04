import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  assetPrefix: "/rubber-duck",
  basePath: "/rubber-duck",
  experimental: {
    turbopackRustReactCompiler: true,
  },
  reactCompiler: true,
  redirects() {
    return Promise.resolve([
      {
        basePath: false,
        destination: "https://blode.co/rubber-duck",
        has: [{ type: "host" as const, value: "rubber-duck.blode.co" }],
        permanent: true,
        source: "/",
      },
      {
        basePath: false,
        destination: "https://blode.co/rubber-duck/:path*",
        has: [{ type: "host" as const, value: "rubber-duck.blode.co" }],
        permanent: true,
        source: "/:path*",
      },
    ]);
  },
};

export default nextConfig;
