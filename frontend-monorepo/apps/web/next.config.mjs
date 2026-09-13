/**
 * Next.js configuration for the unified tcm-edu web app.
 *
 * Dev  :  http://localhost:3000/   (单一端口承载三端，按路径分流)
 * Prod :  静态导出到 out/，由 Phoenix FallbackController 挂在 /app/*
 *
 * Antd (管理/教师端) 与 Tailwind v4 (学生端) 共存：
 *   - Antd 用 CSS-in-JS 通过 @ant-design/nextjs-registry 处理 SSR 样式提取
 *   - Tailwind 只在学生路由组生效，学生组件用自研 token 体系
 *   - 路由按 app/(student|admin|teacher)/* 分组，每个分组有自己的 layout
 */
const isProd = process.env.NODE_ENV === "production";

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
  reactStrictMode: true,
  turbopack: {
    // pnpm 把包放在 monorepo 根的 .pnpm 下；root 必须覆盖到 frontend-monorepo，
    // 否则 Turbopack 拒绝编译 workspace 软链的 @tcm-edu/rpc-client。
    root: new URL("../..", import.meta.url).pathname,
  },
  // 生产环境：整个静态导出挂在 /app/，对应 Phoenix FallbackController 的 priv/app/
  // dev 环境：无 basePath，直接 http://localhost:3000/
  ...(isProd
    ? {
        basePath: "/app",
        assetPrefix: "/app",
      }
    : {}),
  async rewrites() {
    // 仅 dev/start 生效，静态导出忽略。/api/* 全部代理到 Phoenix :4011。
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:4011/api/:path*",
      },
    ];
  },
};

export default nextConfig;