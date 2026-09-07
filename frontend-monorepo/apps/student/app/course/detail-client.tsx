"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import EnrollButton from "@/components/enroll-button";
import { formatPrice } from "@/components/course-card";
import { PUBLIC_TENANT } from "@/app/courses/page";
import {
  getCourse,
  listTeacherProfiles,
  type AshRpcError,
} from "@tcm-edu/rpc-client";

interface LessonItem {
  id: string;
  title: string;
  contentType?: string | null;
  durationSeconds?: number | null;
  sortOrder?: number | null;
  isFreePreview?: boolean | null;
}

interface ChapterItem {
  id: string;
  title: string;
  sortOrder?: number | null;
  lessons?: LessonItem[];
}

interface CourseDetailData {
  id: string;
  title: string;
  subtitle?: string | null;
  description?: string | null;
  coverImageUrl?: string | null;
  level?: string | null;
  priceCents?: number | null;
  lessonCount?: number | null;
  studentCount?: number | null;
  teacherId?: string | null;
  chapters?: ChapterItem[];
}

interface TeacherProfile {
  id: string;
  name?: string | null;
  avatarUrl?: string | null;
  jobTitle?: string | null;
  school?: string | null;
  bio?: string | null;
}

const LEVEL_LABEL: Record<string, string> = {
  beginner: "初级",
  intermediate: "中级",
  advanced: "高级",
};

const CONTENT_LABEL: Record<string, string> = {
  video: "视频",
  article: "文章",
  pdf: "PDF",
};

type Tab = "intro" | "chapters" | "teacher";

function errMsg(errors: AshRpcError[]): string {
  return errors?.[0]?.message ?? "加载失败，请稍后重试";
}

export default function CourseDetail() {
  const searchParams = useSearchParams();
  const id = searchParams.get("id") ?? "";
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [course, setCourse] = useState<CourseDetailData | null>(null);
  const [teacher, setTeacher] = useState<TeacherProfile | null>(null);
  const [tab, setTab] = useState<Tab>("intro");
  const [openChapters, setOpenChapters] = useState<string[]>([]);

  const load = useCallback(async () => {
    if (!id) {
      setError("缺少课程参数");
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await getCourse({
        getBy: { id },
        fields: [
          "id",
          "title",
          "subtitle",
          "description",
          "coverImageUrl",
          "level",
          "priceCents",
          "lessonCount",
          "studentCount",
          "teacherId",
          {
            chapters: [
              "id",
              "title",
              "sortOrder",
              {
                lessons: [
                  "id",
                  "title",
                  "contentType",
                  "durationSeconds",
                  "sortOrder",
                  "isFreePreview",
                ],
              },
            ],
          },
        ],
        tenant: PUBLIC_TENANT,
      });
      if (!res.success) {
        setError(errMsg(res.errors));
        return;
      }
      const c = res.data as CourseDetailData;
      setCourse(c);
      const chapters = [...(c.chapters ?? [])].sort(
        (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
      );
      if (chapters[0]) setOpenChapters([chapters[0].id]);

      // 讲师介绍走公开名师录（匿名可读），按 teacherId 匹配
      if (c.teacherId) {
        const tRes = await listTeacherProfiles({
          fields: ["id", "name", "avatarUrl", "jobTitle", "school", "bio"],
          tenant: PUBLIC_TENANT,
        });
        if (tRes.success) {
          const found = (tRes.data as TeacherProfile[]).find((t) => t.id === c.teacherId);
          if (found) setTeacher(found);
        }
      }
    } catch {
      setError("网络错误，请稍后重试");
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    load();
  }, [load]);

  const chapters = useMemo(
    () =>
      [...(course?.chapters ?? [])].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)),
    [course]
  );

  const firstLessonId = useMemo(() => {
    for (const ch of chapters) {
      const lessons = [...(ch.lessons ?? [])].sort(
        (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
      );
      if (lessons[0]) return lessons[0].id;
    }
    return null;
  }, [chapters]);

  function toggleChapter(chapterId: string) {
    setOpenChapters((prev) =>
      prev.includes(chapterId) ? prev.filter((c) => c !== chapterId) : [...prev, chapterId]
    );
  }

  if (loading) {
    return (
      <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
        <div className="skeleton h-8 w-1/2 rounded" />
        <div className="mt-4 grid gap-6 md:grid-cols-3">
          <div className="md:col-span-2">
            <div className="skeleton aspect-[16/9] w-full rounded-2xl" />
            <div className="skeleton mt-4 h-5 w-full rounded" />
            <div className="skeleton mt-2 h-5 w-2/3 rounded" />
          </div>
          <div className="skeleton h-64 rounded-2xl" />
        </div>
      </main>
    );
  }

  if (error || !course) {
    return (
      <main className="mx-auto w-full max-w-2xl px-4 py-16 text-center sm:px-6">
        <p className="text-sm text-ink-600">{error ?? "课程不存在"}</p>
        <div className="mt-4 flex justify-center gap-2">
          <button
            onClick={load}
            className="rounded-lg bg-cinnabar-500 px-5 py-2 text-sm font-medium text-white transition hover:bg-cinnabar-600"
          >
            重新加载
          </button>
          <Link
            href="/courses"
            className="rounded-lg border border-rice-200 bg-white px-5 py-2 text-sm text-ink-600 transition hover:border-cinnabar-500"
          >
            返回课程列表
          </Link>
        </div>
      </main>
    );
  }

  return (
    <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
      <Link href="/courses" className="text-sm text-ink-400 transition hover:text-cinnabar-600">
        ← 全部课程
      </Link>

      {/* 顶部信息区 */}
      <div className="mt-4 grid gap-6 md:grid-cols-3">
        <div className="md:col-span-2">
          <div className="relative aspect-[16/9] overflow-hidden rounded-2xl border border-rice-200 bg-gradient-to-br from-rice-100 via-rice-50 to-bamboo-100">
            {course.coverImageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={course.coverImageUrl}
                alt={course.title}
                className="h-full w-full object-cover"
              />
            ) : (
              <div className="flex h-full w-full flex-col items-center justify-center gap-2">
                <span className="font-song text-7xl text-cinnabar-500/70">
                  {course.title.slice(0, 1)}
                </span>
              </div>
            )}
          </div>
          <h1 className="mt-4 font-song text-2xl font-bold text-ink-900 md:text-3xl">
            {course.title}
          </h1>
          {course.subtitle && <p className="mt-1 text-ink-600">{course.subtitle}</p>}
          <div className="mt-3 flex flex-wrap items-center gap-2 text-xs">
            <span className="rounded-full bg-ink-900/80 px-2.5 py-1 text-white">
              {LEVEL_LABEL[course.level ?? ""] ?? "全部水平"}
            </span>
            <span className="rounded-full bg-rice-100 px-2.5 py-1 text-ink-600">
              {course.lessonCount ?? 0} 课时
            </span>
            <span className="rounded-full bg-rice-100 px-2.5 py-1 text-ink-600">
              {course.studentCount ?? 0} 人在学
            </span>
            <span className="rounded-full bg-rice-100 px-2.5 py-1 font-semibold text-cinnabar-600">
              {formatPrice(course.priceCents)}
            </span>
          </div>
        </div>

        <aside className="h-fit rounded-2xl border border-rice-200 bg-white p-5 shadow-sm">
          <p className="font-song text-sm font-semibold tracking-widest text-ink-900">开始学习</p>
          <div className="mt-3">
            <EnrollButton
              courseId={course.id}
              courseTitle={course.title}
              firstLessonId={firstLessonId}
            />
          </div>
          <p className="mt-3 text-xs leading-5 text-ink-400">
            选课后在「我的学习」中继续，学习进度云端同步。
          </p>
        </aside>
      </div>

      {/* Tab 切换 */}
      <div className="mt-8 flex gap-1 border-b border-rice-200">
        {(
          [
            { key: "intro", label: "课程介绍" },
            { key: "chapters", label: `章节目录（${chapters.length}）` },
            { key: "teacher", label: "讲师介绍" },
          ] as { key: Tab; label: string }[]
        ).map((t) => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`px-4 py-2.5 text-sm font-medium transition ${
              tab === t.key
                ? "border-b-2 border-cinnabar-500 text-cinnabar-600"
                : "border-b-2 border-transparent text-ink-600 hover:text-ink-900"
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="py-6">
        {tab === "intro" && (
          <div className="max-w-3xl whitespace-pre-wrap text-sm leading-7 text-ink-900">
            {course.description || "讲师正在完善课程介绍，敬请期待。"}
          </div>
        )}

        {tab === "chapters" && (
          <div className="max-w-3xl">
            {chapters.length === 0 ? (
              <p className="text-sm text-ink-600">暂无章节。</p>
            ) : (
              <div className="divide-y divide-rice-200 overflow-hidden rounded-2xl border border-rice-200 bg-white">
                {chapters.map((ch, ci) => {
                  const lessons = [...(ch.lessons ?? [])].sort(
                    (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)
                  );
                  const open = openChapters.includes(ch.id);
                  return (
                    <div key={ch.id}>
                      <button
                        onClick={() => toggleChapter(ch.id)}
                        className="flex w-full items-center gap-3 bg-rice-50 px-4 py-3 text-left transition hover:bg-rice-100"
                      >
                        <span className="font-song font-semibold text-cinnabar-600">
                          {String(ci + 1).padStart(2, "0")}
                        </span>
                        <span className="flex-1 text-sm font-medium text-ink-900">{ch.title}</span>
                        <span className="text-xs text-ink-400">{lessons.length} 课时</span>
                        <span className="text-ink-400">{open ? "▾" : "▸"}</span>
                      </button>
                      {open && (
                        <ul className="divide-y divide-rice-100">
                          {lessons.map((ls, li) => (
                            <li key={ls.id}>
                              <Link
                                href={`/learn?course=${course.id}&lesson=${ls.id}`}
                                className="flex items-center gap-3 px-4 py-2.5 text-sm transition hover:bg-rice-50"
                              >
                                <span className="w-6 text-xs text-ink-400">{li + 1}</span>
                                <span className="flex-1 text-ink-900">{ls.title}</span>
                                <span className="rounded bg-rice-100 px-1.5 py-0.5 text-xs text-ink-600">
                                  {CONTENT_LABEL[ls.contentType ?? ""] ?? ls.contentType}
                                </span>
                                {ls.isFreePreview && (
                                  <span className="rounded bg-bamboo-100 px-1.5 py-0.5 text-xs text-bamboo-700">
                                    试看
                                  </span>
                                )}
                                {ls.durationSeconds ? (
                                  <span className="text-xs text-ink-400">
                                    {Math.round(ls.durationSeconds / 60)}′
                                  </span>
                                ) : null}
                              </Link>
                            </li>
                          ))}
                        </ul>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {tab === "teacher" && (
          <div className="max-w-3xl">
            {teacher ? (
              <div className="flex flex-col gap-4 rounded-2xl border border-rice-200 bg-white p-6 sm:flex-row">
                {teacher.avatarUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={teacher.avatarUrl}
                    alt={teacher.name ?? "讲师"}
                    className="h-24 w-24 rounded-full border-2 border-rice-200 object-cover"
                  />
                ) : (
                  <span className="flex h-24 w-24 items-center justify-center rounded-full bg-bamboo-500 font-song text-4xl text-white">
                    {(teacher.name ?? "师").slice(0, 1)}
                  </span>
                )}
                <div>
                  <h3 className="font-song text-lg font-semibold text-ink-900">{teacher.name}</h3>
                  {(teacher.jobTitle || teacher.school) && (
                    <p className="mt-1 text-xs text-ink-400">
                      {[teacher.jobTitle, teacher.school].filter(Boolean).join(" · ")}
                    </p>
                  )}
                  <p className="mt-2 text-sm leading-6 text-ink-600">
                    {teacher.bio || "讲师简介完善中。"}
                  </p>
                </div>
              </div>
            ) : (
              <p className="text-sm text-ink-600">讲师信息完善中。</p>
            )}
          </div>
        )}
      </div>
    </main>
  );
}
