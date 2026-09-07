/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  turbopack: {
    // 同 student：覆盖 monorepo 根，否则 workspace 软链包（@tcm-edu/rpc-client）无法编译。
    root: new URL("../..", import.meta.url).pathname,
  },
  async rewrites() {
    // 管理端所有 /api/* 请求代理到 Phoenix，便于 Bearer 鉴权与租户上下文透传。
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:4011/api/:path*",
      },
    ];
  },
};

export default nextConfig;
