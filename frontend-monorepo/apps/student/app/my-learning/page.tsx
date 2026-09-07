"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { useAuth } from "@/app/auth-context";
import { myEnrollments, type AshRpcError } from "@tcm-edu/rpc-client";

interface EnrolledCourse {
  enrollmentId: string;
  status: string;
  enrolledAt?: string | null;
  courseId: string;
  courseTitle: string;
  courseSubtitle?: string | null;
  coverImageUrl?: string | null;
  lessonCount?: number | null;
  avgPct: number;
}

function errMsg(errors: AshRpcError[]): string {
  return errors?.[0]?.message ?? "加载失败，请稍后重试";
}

export default function MyLearningPage() {
  const router = useRouter();
  const { isAuthenticated, ready } = useAuth();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<EnrolledCourse[]>([]);

  const load = useCallback(async () => {
    if (!isAuthenticated) {
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await myEnrollments({
        fields: [
          "id",
          "courseId",
          "status",
          "enrolledAt",
          {
            course: ["id", "title", "subtitle", "coverImageUrl", "lessonCount"],
          },
          { progressRecords: ["lessonId", "progressPct", "status"] },
        ],
      });
      if (!res.success) {
        setError(errMsg(res.errors));
        return;
      }
      const list = (
        res.data as {
          id: string;
          courseId: string;
          status: string;
          enrolledAt?: string | null;
          course?: {
            id: string;
            title: string;
            subtitle?: string | null;
            coverImageUrl?: string | null;
            lessonCount?: number | null;
          } | null;
          progressRecords?: { lessonId: string; progressPct?: number | null }[];
        }[]
      )
        .filter((e) => e.status === "active")
        .map((e) => {
          const pcts = (e.progressRecords ?? []).map((p) => p.progressPct ?? 0);
          const avg =
            pcts.length > 0 ? Math.round(pcts.reduce((s, v) => s + v, 0) / pcts.length) : 0;
          return {
            enrollmentId: e.id,
            status: e.status,
            enrolledAt: e.enrolledAt,
            courseId: e.courseId,
            courseTitle: e.course?.title ?? "（课程已下架）",
            courseSubtitle: e.course?.subtitle,
            coverImageUrl: e.course?.coverImageUrl,
            lessonCount: e.course?.lessonCount,
            avgPct: avg,
          };
        });
      setRows(list);
    } catch {
      setError("网络错误，请稍后重试");
    } finally {
      setLoading(false);
    }
  }, [isAuthenticated]);

  useEffect(() => {
    if (!ready) return;
    if (!isAuthenticated) {
      router.replace("/login");
      return;
    }
    load();
  }, [isAuthenticated, ready, load, router]);

  if (!ready) {
    return (
      <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
        <div className="skeleton h-8 w-48 rounded" />
      </main>
    );
  }

  if (!isAuthenticated) return null;

  return (
    <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
      <h1 className="font-song text-2xl font-bold text-ink-900 md:text-3xl">我的学习</h1>
      <p className="mt-1 text-sm text-ink-600">继续上次的进度，见证你的成长</p>

      {loading ? (
        <div className="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <div key={i} className="overflow-hidden rounded-2xl border border-rice-200 bg-white">
              <div className="skeleton aspect-[16/9] w-full" />
              <div className="flex flex-col gap-2 p-4">
                <div className="skeleton h-5 w-3/4 rounded" />
                <div className="skeleton h-2 w-full rounded-full" />
              </div>
            </div>
          ))}
        </div>
      ) : error ? (
        <div className="mt-6 rounded-2xl border border-rice-200 bg-white px-6 py-10 text-center">
          <p className="text-sm text-ink-600">{error}</p>
          <button
            onClick={load}
            className="mt-4 rounded-lg bg-cinnabar-500 px-5 py-2 text-sm font-medium text-white transition hover:bg-cinnabar-600"
          >
            重新加载
          </button>
        </div>
      ) : rows.length === 0 ? (
        <div className="mt-6 rounded-2xl border border-rice-200 bg-white px-6 py-12 text-center">
          <p className="font-song text-lg text-ink-900">还没有选课</p>
          <p className="mt-1 text-sm text-ink-600">去课程表挑一门感兴趣的课开始吧。</p>
          <Link
            href="/courses"
            className="mt-4 inline-block rounded-lg bg-cinnabar-500 px-6 py-2.5 text-sm font-medium text-white transition hover:bg-cinnabar-600"
          >
            去选课
          </Link>
        </div>
      ) : (
        <div className="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {rows.map((r) => (
            <Link
              key={r.enrollmentId}
              href={`/course?id=${r.courseId}`}
              className="group flex flex-col overflow-hidden rounded-2xl border border-rice-200 bg-white shadow-sm transition hover:-translate-y-1 hover:shadow-lg"
            >
              <div className="relative aspect-[16/9] overflow-hidden bg-rice-100">
                {r.coverImageUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={r.coverImageUrl}
                    alt={r.courseTitle}
                    loading="lazy"
                    className="h-full w-full object-cover transition duration-300 group-hover:scale-105"
                  />
                ) : (
                  <div className="flex h-full w-full items-center justify-center bg-gradient-to-br from-rice-100 via-rice-50 to-bamboo-100">
                    <span className="font-song text-4xl text-cinnabar-500/70">
                      {r.courseTitle.slice(0, 1)}
                    </span>
                  </div>
                )}
              </div>
              <div className="flex flex-1 flex-col gap-2 p-4">
                <h3 className="font-song font-semibold text-ink-900 transition group-hover:text-cinnabar-600">
                  {r.courseTitle}
                </h3>
                <div className="flex items-center justify-between text-xs text-ink-600">
                  <span>总体进度 {r.avgPct}%</span>
                  <span>{r.lessonCount ?? 0} 课时</span>
                </div>
                <div className="h-2 overflow-hidden rounded-full bg-rice-100">
                  <div
                    className="h-full rounded-full bg-bamboo-500 transition-all"
                    style={{ width: `${r.avgPct}%` }}
                  />
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </main>
  );
}
