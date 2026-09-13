"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import HeroBanner from "@/components/hero-banner";
import CategoryGrid, { type CategoryItem } from "@/components/category-grid";
import CourseCard, { type CourseItem } from "@/components/course-card";
import TeacherCard, { type TeacherItem } from "@/components/teacher-card";
import StatsBar, { type SiteStats } from "@/components/stats-bar";
import LearningPath, { LearningPathCta } from "@/components/learning-path";
import {
  CategorySkeleton,
  CourseCardSkeleton,
  TeacherSkeleton,
} from "@/components/skeletons";
import { useAuth } from "@/lib/auth/compat";
import { cachedQuery } from "@/lib/public-cache";
import {
  listCategories,
  listPopularCourses,
  listTeacherProfiles,
  type AshRpcError,
} from "@tcm-edu/rpc-client";

/** 公开站默认租户（多租户子域名方案在 Phase 10 接入前写死）。 */
const PUBLIC_TENANT = "tenant_default";

const COURSE_FIELDS = [
  "id",
  "title",
  "subtitle",
  "coverImageUrl",
  "level",
  "priceCents",
  "lessonCount",
  "studentCount",
] as const;

const CATEGORY_FIELDS = ["id", "name", "slug", "icon"] as const;

const TEACHER_FIELDS = ["id", "name", "avatarUrl", "jobTitle", "school", "bio"] as const;

function errMsg(errors: AshRpcError[]): string {
  return errors?.[0]?.message ?? "加载失败，请稍后重试";
}

function SectionHead({
  eyebrow,
  title,
  desc,
}: {
  eyebrow: string;
  title: string;
  desc?: string;
}) {
  return (
    <div className="mb-6 text-center">
      <p className="text-xs font-semibold uppercase tracking-[0.3em] text-cinnabar-600">
        {eyebrow}
      </p>
      <h2 className="mt-2 font-song text-2xl font-bold text-ink-900 md:text-3xl">
        {title}
      </h2>
      {desc && <p className="mx-auto mt-2 max-w-xl text-sm text-ink-600">{desc}</p>}
    </div>
  );
}

export default function HomePage() {
  const { isAuthenticated } = useAuth();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [courses, setCourses] = useState<CourseItem[]>([]);
  const [categories, setCategories] = useState<CategoryItem[]>([]);
  const [teachers, setTeachers] = useState<TeacherItem[]>([]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // 公开查询 60s 缓存：路由切回首页不重复打后端
      const [popularRes, catRes, teacherRes] = await Promise.all([
        cachedQuery("home:popular", 60_000, () =>
          listPopularCourses({ fields: [...COURSE_FIELDS], tenant: PUBLIC_TENANT })
        ),
        cachedQuery("home:categories", 60_000, () =>
          listCategories({ fields: [...CATEGORY_FIELDS], tenant: PUBLIC_TENANT })
        ),
        cachedQuery("home:teachers", 60_000, () =>
          listTeacherProfiles({ fields: [...TEACHER_FIELDS], tenant: PUBLIC_TENANT })
        ),
      ]);
      if (!popularRes.success) {
        setError(errMsg(popularRes.errors));
        return;
      }
      setCourses(popularRes.data as CourseItem[]);
      if (catRes.success) setCategories(catRes.data as CategoryItem[]);
      if (teacherRes.success) {
        setTeachers(
          (teacherRes.data as TeacherItem[]).filter((t) => t.name).slice(0, 4)
        );
      }
    } catch {
      setError("网络错误，请稍后重试");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const stats: SiteStats = useMemo(
    () => ({
      courseCount: courses.length,
      studentCount: courses.reduce((s, c) => s + (c.studentCount ?? 0), 0),
      teacherCount: teachers.length,
      lessonCount: courses.reduce((s, c) => s + (c.lessonCount ?? 0), 0),
    }),
    [courses, teachers]
  );

  return (
    <main>
      <HeroBanner />

      <div className="mx-auto w-full max-w-6xl px-4 sm:px-6">
        {/* 数据统计 */}
        <div className="-mt-2 py-10">
          <StatsBar stats={stats} />
        </div>

        {/* 课程分类 */}
        <section className="py-8">
          <SectionHead eyebrow="因材施教" title="课程分类" desc="从基础理论到临床精进，按需选课" />
          {loading ? (
            <CategorySkeleton />
          ) : (
            <CategoryGrid categories={categories} />
          )}
        </section>

        {/* 热门课程 */}
        <section id="courses" className="scroll-mt-20 py-8">
          <SectionHead
            eyebrow="热门推荐"
            title="大家都在学"
            desc="按在学人数排序的热门课程，免费试看先行"
          />
          {loading ? (
            <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
              {Array.from({ length: 4 }).map((_, i) => (
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
          ) : courses.length === 0 ? (
            <div className="rounded-2xl border border-rice-200 bg-white px-6 py-10 text-center text-sm text-ink-600">
              课程正在筹备中，敬请期待。
            </div>
          ) : (
            <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
              {courses.map((c) => (
                <CourseCard key={c.id} course={c} />
              ))}
            </div>
          )}
          {!isAuthenticated && !loading && !error && courses.length > 0 && (
            <p className="mt-6 text-center text-sm text-ink-600">
              登录后即可选课学习，进度云端同步。
              <Link href="/login" className="ml-1 font-medium text-cinnabar-600 hover:underline">
                去登录 →
              </Link>
            </p>
          )}
        </section>

        {/* 学习路径 */}
        <section id="path" className="scroll-mt-20 py-8">
          <SectionHead eyebrow="循序渐进" title="中医学习路径" desc="四阶路径，从筑基到临床" />
          <LearningPath />
          <LearningPathCta />
        </section>

        {/* 名师风采（有数据才渲染） */}
        {teachers.length > 0 && (
          <section id="teachers" className="scroll-mt-20 py-8">
            <SectionHead eyebrow="师者传道" title="名师风采" desc="一线教师精讲每一门课" />
            {loading ? (
              <TeacherSkeleton />
            ) : (
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                {teachers.map((t) => (
                  <TeacherCard key={t.id} teacher={t} />
                ))}
              </div>
            )}
          </section>
        )}
      </div>

      {/* CTA 条 */}
      <section className="mt-8 bg-cinnabar-500">
        <div className="mx-auto flex w-full max-w-6xl flex-col items-center gap-4 px-4 py-12 text-center sm:px-6">
          <h2 className="font-song text-2xl font-bold text-white md:text-3xl">
            今天，就开始你的中医学习之旅
          </h2>
          <p className="max-w-xl text-sm leading-6 text-white/85">
            注册即学：选课、看课、进度跟踪，全程免费起步。
          </p>
          <Link
            href={isAuthenticated ? "/#courses" : "/login"}
            className="rounded-lg bg-white px-8 py-3 text-sm font-semibold text-cinnabar-600 transition hover:bg-rice-100"
          >
            {isAuthenticated ? "继续学习" : "免费注册"}
          </Link>
        </div>
      </section>
    </main>
  );
}
