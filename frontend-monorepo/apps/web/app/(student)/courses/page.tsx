"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import CourseCard, { type CourseItem } from "@/components/course-card";
import { CourseCardSkeleton } from "@/components/skeletons";
import {
  listCategories,
  listPublishedCourses,
  type AshRpcError,
} from "@tcm-edu/rpc-client";

/** 公开站默认租户（多租户子域名方案在 Phase 10 接入前写死）。 */
export const PUBLIC_TENANT = "tenant_default";

const COURSE_FIELDS = [
  "id",
  "title",
  "subtitle",
  "coverImageUrl",
  "level",
  "priceCents",
  "lessonCount",
  "studentCount",
  "categoryId",
  "publishedAt",
] as const;

type SortKey = "popular" | "newest" | "lessons" | "priceAsc";

const SORT_OPTIONS: { value: SortKey; label: string }[] = [
  { value: "popular", label: "最受欢迎" },
  { value: "newest", label: "最新发布" },
  { value: "lessons", label: "课时最多" },
  { value: "priceAsc", label: "价格从低到高" },
];

const LEVEL_OPTIONS = [
  { value: "beginner", label: "初级" },
  { value: "intermediate", label: "中级" },
  { value: "advanced", label: "高级" },
];

const PAGE_SIZE = 12;

function errMsg(errors: AshRpcError[]): string {
  return errors?.[0]?.message ?? "加载失败，请稍后重试";
}

export default function CoursesPage() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<CourseItem[]>([]);
  const [categories, setCategories] = useState<{ id: string; name: string }[]>([]);
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [level, setLevel] = useState<string | null>(null);
  const [keyword, setKeyword] = useState("");
  const [sort, setSort] = useState<SortKey>("popular");
  const [page, setPage] = useState(1);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // 服务端：分类 + 难度过滤（标题无 contains 过滤，关键字走客户端）
      const filter: Record<string, { eq: string }> = {};
      if (categoryId) filter.categoryId = { eq: categoryId };
      if (level) filter.level = { eq: level };
      const sortParam =
        sort === "popular"
          ? "-studentCount"
          : sort === "newest"
            ? "-publishedAt"
            : sort === "lessons"
              ? "-lessonCount"
              : "priceCents";
      const [coursesRes, catRes] = await Promise.all([
        listPublishedCourses({
          fields: [...COURSE_FIELDS],
          tenant: PUBLIC_TENANT,
          filter: Object.keys(filter).length > 0 ? filter : undefined,
          sort: sortParam,
        }),
        listCategories({ fields: ["id", "name"], tenant: PUBLIC_TENANT }),
      ]);
      if (!coursesRes.success) {
        setError(errMsg(coursesRes.errors));
        return;
      }
      setRows(coursesRes.data as CourseItem[]);
      if (catRes.success) setCategories(catRes.data as { id: string; name: string }[]);
    } catch {
      setError("网络错误，请稍后重试");
    } finally {
      setLoading(false);
    }
  }, [categoryId, level, sort]);

  useEffect(() => {
    setPage(1);
    load();
  }, [load]);

  const filtered = useMemo(() => {
    const kw = keyword.trim().toLowerCase();
    if (!kw) return rows;
    return rows.filter(
      (r) =>
        r.title.toLowerCase().includes(kw) ||
        (r.subtitle ?? "").toLowerCase().includes(kw)
    );
  }, [rows, keyword]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const pageRows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  return (
    <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
      <h1 className="font-song text-2xl font-bold text-ink-900 md:text-3xl">全部课程</h1>
      <p className="mt-1 text-sm text-ink-600">公开课表，未登录也可浏览；登录后选课学习</p>

      {/* 工具栏 */}
      <div className="mt-6 flex flex-col gap-3 md:flex-row md:items-center">
        <input
          type="search"
          value={keyword}
          onChange={(e) => {
            setKeyword(e.target.value);
            setPage(1);
          }}
          placeholder="搜索课程标题…"
          className="w-full rounded-lg border border-rice-200 bg-white px-3 py-2.5 text-sm outline-none transition focus:border-cinnabar-500 focus:ring-2 focus:ring-cinnabar-100 md:max-w-xs"
        />
        <div className="flex items-center gap-2 md:ml-auto">
          <label htmlFor="sort" className="text-sm text-ink-600">排序</label>
          <select
            id="sort"
            value={sort}
            onChange={(e) => setSort(e.target.value as SortKey)}
            className="rounded-lg border border-rice-200 bg-white px-3 py-2.5 text-sm outline-none transition focus:border-cinnabar-500"
          >
            {SORT_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </div>
      </div>

      <div className="mt-6 flex flex-col gap-6 md:flex-row">
        {/* 侧边栏筛选 */}
        <aside className="w-full shrink-0 md:w-52">
          <div className="rounded-2xl border border-rice-200 bg-white p-4">
            <h2 className="font-song text-sm font-semibold tracking-widest text-ink-900">分类</h2>
            <ul className="mt-2 space-y-1">
              <li>
                <button
                  onClick={() => setCategoryId(null)}
                  className={`block w-full rounded-md px-3 py-2 text-left text-sm transition ${
                    categoryId === null
                      ? "bg-cinnabar-500 font-medium text-white"
                      : "text-ink-600 hover:bg-rice-100"
                  }`}
                >
                  全部
                </button>
              </li>
              {categories.map((c) => (
                <li key={c.id}>
                  <button
                    onClick={() => setCategoryId(categoryId === c.id ? null : c.id)}
                    className={`block w-full rounded-md px-3 py-2 text-left text-sm transition ${
                      categoryId === c.id
                        ? "bg-cinnabar-500 font-medium text-white"
                        : "text-ink-600 hover:bg-rice-100"
                    }`}
                  >
                    {c.name}
                  </button>
                </li>
              ))}
            </ul>
            <h2 className="mt-4 font-song text-sm font-semibold tracking-widest text-ink-900">难度</h2>
            <ul className="mt-2 space-y-1">
              <li>
                <button
                  onClick={() => setLevel(null)}
                  className={`block w-full rounded-md px-3 py-2 text-left text-sm transition ${
                    level === null
                      ? "bg-bamboo-500 font-medium text-white"
                      : "text-ink-600 hover:bg-rice-100"
                  }`}
                >
                  全部
                </button>
              </li>
              {LEVEL_OPTIONS.map((o) => (
                <li key={o.value}>
                  <button
                    onClick={() => setLevel(level === o.value ? null : o.value)}
                    className={`block w-full rounded-md px-3 py-2 text-left text-sm transition ${
                      level === o.value
                        ? "bg-bamboo-500 font-medium text-white"
                        : "text-ink-600 hover:bg-rice-100"
                    }`}
                  >
                    {o.label}
                  </button>
                </li>
              ))}
            </ul>
          </div>
        </aside>

        {/* 结果区 */}
        <section className="flex-1">
          {loading ? (
            <div className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
              {Array.from({ length: 6 }).map((_, i) => (
                <CourseCardSkeleton key={i} />
              ))}
            </div>
          ) : error ? (
            <div className="rounded-2xl border border-rice-200 bg-white px-6 py-10 text-center">
              <p className="text-sm text-ink-600">{error}</p>
              <button
                onClick={load}
                className="mt-4 rounded-lg bg-cinnabar-500 px-5 py-2 text-sm font-medium text-white transition hover:bg-cinnabar-600"
              >
                重新加载
              </button>
            </div>
          ) : filtered.length === 0 ? (
            <div className="rounded-2xl border border-rice-200 bg-white px-6 py-10 text-center text-sm text-ink-600">
              没有符合条件的课程，换个筛选试试。
            </div>
          ) : (
            <>
              <p className="mb-3 text-sm text-ink-400">共 {filtered.length} 门课程</p>
              <div className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
                {pageRows.map((c) => (
                  <CourseCard key={c.id} course={c} />
                ))}
              </div>
              {totalPages > 1 && (
                <div className="mt-6 flex items-center justify-center gap-2">
                  <button
                    disabled={page <= 1}
                    onClick={() => setPage((p) => p - 1)}
                    className="rounded-lg border border-rice-200 bg-white px-4 py-2 text-sm transition hover:border-cinnabar-500 disabled:opacity-40"
                  >
                    上一页
                  </button>
                  <span className="text-sm text-ink-600">
                    {page} / {totalPages}
                  </span>
                  <button
                    disabled={page >= totalPages}
                    onClick={() => setPage((p) => p + 1)}
                    className="rounded-lg border border-rice-200 bg-white px-4 py-2 text-sm transition hover:border-cinnabar-500 disabled:opacity-40"
                  >
                    下一页
                  </button>
                </div>
              )}
            </>
          )}
        </section>
      </div>
    </main>
  );
}
