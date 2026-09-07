import type { MetadataRoute } from "next";

export const dynamic = "force-static";

const BASE_URL = "https://tcm-edu.example.com";

export default function sitemap(): MetadataRoute.Sitemap {
  const staticRoutes = ["", "/courses", "/login", "/my-learning", "/learn"].map(
    (path) => ({
      url: `${BASE_URL}${path === "" ? "" : path}`,
      lastModified: new Date(),
      changeFrequency: "daily" as const,
      priority: path === "" ? 1 : 0.8,
    })
  );
  // 课程详情是动态路由（构建期无后端可取），由客户端渲染；
  // 完整课程 URL 索引待 SSR/ISR 接入后补充（Phase 10）。
  return staticRoutes;
}
