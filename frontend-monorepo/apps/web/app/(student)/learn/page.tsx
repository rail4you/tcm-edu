"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { useAuth } from "@/lib/auth/compat";
import EnrollButton from "@/components/enroll-button";
import { PUBLIC_TENANT } from "@/app/(student)/courses/page";
import {
  getCourse,
  myEnrollments,
  upsertProgress,
  type AshRpcError,
} from "@tcm-edu/rpc-client";

interface LessonItem {
  id: string;
  title: string;
  contentType?: string | null;
  contentUrl?: string | null;
  contentText?: string | null;
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

interface FlatLesson extends LessonItem {
  chapterTitle: string;
}

const HEARTBEAT_MS = 10_000;

function errMsg(errors: AshRpcError[]): string {
  return errors?.[0]?.message ?? "加载失败，请稍后重试";
}

function LearnInner() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const courseId = searchParams.get("course") ?? "";
  const lessonId = searchParams.get("lesson") ?? "";
  const { isAuthenticated } = useAuth();

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [courseTitle, setCourseTitle] = useState("");
  const [flatLessons, setFlatLessons] = useState<FlatLesson[]>([]);
  const [enrollmentId, setEnrollmentId] = useState<string | null>(null);
  const [enrolled, setEnrolled] = useState(false);
  const [progressPct, setProgressPct] = useState(0);
  const [saving, setSaving] = useState(false);
  const [savedAt, setSavedAt] = useState<string | null>(null);
  const pctRef = useRef(0);
  const posRef = useRef(0);
  const busyRef = useRef(false);

  const activeLesson = useMemo(
    () => flatLessons.find((l) => l.id === lessonId) ?? null,
    [flatLessons, lessonId]
  );

  const neighbor = useMemo(() => {
    const i = flatLessons.findIndex((l) => l.id === lessonId);
    if (i < 0) return { prev: null, next: null };
    return {
      prev: i > 0 ? flatLessons[i - 1] : null,
      next: i < flatLessons.length - 1 ? flatLessons[i + 1] : null,
    };
  }, [flatLessons, lessonId]);

  const load = useCallback(async () => {
    if (!courseId || !lessonId) {
      setError("缺少课程或课时参数");
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const [courseRes, enrRes] = await Promise.all([
        getCourse({
          getBy: { id: courseId },
          fields: [
            "id",
            "title",
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
                    "contentUrl",
                    "contentText",
                    "durationSeconds",
                    "sortOrder",
                    "isFreePreview",
                  ],
                },
              ],
            },
          ],
          tenant: PUBLIC_TENANT,
        }),
        isAuthenticated
          ? myEnrollments({ fields: ["id", "courseId", "status"] })
          : Promise.resolve({ success: true, data: [] } as const),
      ]);
      if (!courseRes.success) {
        setError(errMsg(courseRes.errors));
        return;
      }
      const c = courseRes.data as { title: string; chapters?: ChapterItem[] };
      setCourseTitle(c.title);
      const flat: FlatLesson[] = [...(c.chapters ?? [])]
        .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
        .flatMap((ch) =>
          [...(ch.lessons ?? [])]
            .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))
            .map((ls) => ({ ...ls, chapterTitle: ch.title }))
        );
      setFlatLessons(flat);

      if (enrRes.success) {
        const mine = (enrRes.data as { id: string; courseId: string; status: string }[]).find(
          (e) => e.courseId === courseId && e.status === "active"
        );
        if (mine) {
          setEnrolled(true);
          setEnrollmentId(mine.id);
          // 读回已保存进度作为起点
          const pRes = await upsertProgress({
            fields: ["progressPct", "lastPositionSeconds"],
            tenant: PUBLIC_TENANT,
            input: { enrollmentId: mine.id, lessonId },
          });
          if (pRes.success) {
            const p = pRes.data as { progressPct?: number | null; lastPositionSeconds?: number | null };
            pctRef.current = p.progressPct ?? 0;
            posRef.current = p.lastPositionSeconds ?? 0;
            setProgressPct(pctRef.current);
          }
        }
      }
    } catch {
      setError("网络错误，请稍后重试");
    } finally {
      setLoading(false);
    }
  }, [courseId, lessonId, isAuthenticated]);

  useEffect(() => {
    load();
  }, [load]);

  // 心跳上报（登录且已选课才上报；学完后停止，避免把 100 拉回 90）
  useEffect(() => {
    if (!enrolled || !enrollmentId || !lessonId) return;
    const timer = setInterval(async () => {
      // 已学完不再上报；有请求在飞则跳过本轮（防与“标记已学完”互踩）
      if (pctRef.current >= 100 || busyRef.current) return;
      busyRef.current = true;
      // 文章/PDF：每次心跳推进 5%（上限 90，100 靠手动标记）
      if (activeLesson?.contentType !== "video") {
        pctRef.current = Math.min(90, pctRef.current + 5);
      }
      setSaving(true);
      try {
        const res = await upsertProgress({
          fields: ["progressPct"],
          tenant: PUBLIC_TENANT,
          input: {
            enrollmentId,
            lessonId,
            progressPct: Math.round(pctRef.current),
            lastPositionSeconds: Math.round(posRef.current),
            status: pctRef.current >= 100 ? "completed" : "in_progress",
          },
        });
        if (res.success) {
          setProgressPct(Math.round(pctRef.current));
          setSavedAt(new Date().toLocaleTimeString("zh-CN", { hour12: false }));
        }
      } finally {
        setSaving(false);
        busyRef.current = false;
      }
    }, HEARTBEAT_MS);
    return () => clearInterval(timer);
  }, [enrolled, enrollmentId, lessonId, activeLesson?.contentType]);

  async function markDone() {
    if (!enrollmentId || busyRef.current) return;
    busyRef.current = true;
    setSaving(true);
    try {
      const res = await upsertProgress({
        fields: ["progressPct"],
        tenant: PUBLIC_TENANT,
        input: { enrollmentId, lessonId, progressPct: 100, status: "completed" },
      });
      if (res.success) {
        pctRef.current = 100;
        setProgressPct(100);
        setSavedAt(new Date().toLocaleTimeString("zh-CN", { hour12: false }));
      } else {
        setError(errMsg(res.errors));
      }
    } finally {
      setSaving(false);
      busyRef.current = false;
    }
  }

  function goLesson(targetId: string) {
    pctRef.current = 0;
    posRef.current = 0;
    setProgressPct(0);
    router.push(`/learn?course=${courseId}&lesson=${targetId}`);
  }

  if (loading) {
    return (
      <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
        <div className="skeleton h-7 w-1/3 rounded" />
        <div className="mt-4 grid gap-6 md:grid-cols-3">
          <div className="md:col-span-2"><div className="skeleton aspect-video w-full rounded-2xl" /></div>
          <div className="skeleton h-96 rounded-2xl" />
        </div>
      </main>
    );
  }

  if (error || !activeLesson) {
    return (
      <main className="mx-auto w-full max-w-2xl px-4 py-16 text-center sm:px-6">
        <p className="text-sm text-ink-600">{error ?? "课时不存在"}</p>
        <Link
          href={courseId ? `/course?id=${courseId}` : "/courses"}
          className="mt-4 inline-block rounded-lg border border-rice-200 bg-white px-5 py-2 text-sm text-ink-600 transition hover:border-cinnabar-500"
        >
          返回课程
        </Link>
      </main>
    );
  }

  return (
    <main className="mx-auto w-full max-w-6xl px-4 py-6 sm:px-6">
      <nav className="text-sm text-ink-400">
        <Link href="/courses" className="transition hover:text-cinnabar-600">全部课程</Link>
        {" / "}
        <Link href={`/course?id=${courseId}`} className="transition hover:text-cinnabar-600">
          {courseTitle}
        </Link>
        {" / "}
        <span className="text-ink-900">{activeLesson.title}</span>
      </nav>

      {!isAuthenticated ? (
        <div className="mt-6 rounded-2xl border border-rice-200 bg-white p-8 text-center">
          <p className="text-sm text-ink-600">登录后选课学习，进度云端同步。</p>
          <Link
            href="/login"
            className="mt-4 inline-block rounded-lg bg-cinnabar-500 px-6 py-2.5 text-sm font-medium text-white transition hover:bg-cinnabar-600"
          >
            去登录
          </Link>
        </div>
      ) : !enrolled ? (
        <div className="mx-auto mt-6 max-w-md rounded-2xl border border-rice-200 bg-white p-6">
          <h1 className="font-song text-lg font-semibold text-ink-900">尚未选课</h1>
          <p className="mt-1 text-sm text-ink-600">选课后即可学习《{courseTitle}》。</p>
          <div className="mt-4">
            <EnrollButton courseId={courseId} courseTitle={courseTitle} firstLessonId={lessonId} />
          </div>
        </div>
      ) : (
        <div className="mt-4 grid gap-6 md:grid-cols-3">
          <div className="md:col-span-2">
            <h1 className="font-song text-xl font-bold text-ink-900">{activeLesson.title}</h1>
            <p className="mt-1 text-xs text-ink-400">
              {activeLesson.chapterTitle}
              {activeLesson.isFreePreview ? " · 试看" : ""}
            </p>

            {/* 内容区 */}
            <div className="mt-4 overflow-hidden rounded-2xl border border-rice-200 bg-white">
              {activeLesson.contentType === "video" ? (
                activeLesson.contentUrl ? (
                  <video
                    key={activeLesson.id}
                    controls
                    preload="metadata"
                    src={activeLesson.contentUrl}
                    className="aspect-video w-full bg-black"
                    onTimeUpdate={(e) => {
                      const v = e.currentTarget;
                      if (v.duration > 0) {
                        pctRef.current = Math.min(100, (v.currentTime / v.duration) * 100);
                        posRef.current = v.currentTime;
                      }
                    }}
                  />
                ) : (
                  <div className="flex aspect-video items-center justify-center bg-ink-900 text-sm text-rice-100">
                    讲师尚未上传视频。
                  </div>
                )
              ) : activeLesson.contentType === "pdf" ? (
                activeLesson.contentUrl ? (
                  <iframe
                    key={activeLesson.id}
                    src={activeLesson.contentUrl}
                    title={activeLesson.title}
                    className="h-[70vh] w-full"
                  />
                ) : (
                  <div className="flex aspect-video items-center justify-center text-sm text-ink-400">
                    讲师尚未上传 PDF。
                  </div>
                )
              ) : (
                <article className="prose max-w-none px-6 py-6 text-sm leading-7 text-ink-900">
                  {activeLesson.contentText ? (
                    <ReactMarkdown remarkPlugins={[remarkGfm]}>
                      {activeLesson.contentText}
                    </ReactMarkdown>
                  ) : (
                    <p className="text-ink-400">讲师正在编写本课内容，敬请期待。</p>
                  )}
                </article>
              )}
            </div>

            {/* 进度条 + 操作 */}
            <div className="mt-4 rounded-2xl border border-rice-200 bg-white p-4">
              <div className="flex items-center justify-between text-xs text-ink-600">
                <span>本课进度 {progressPct}%</span>
                <span>
                  {saving ? "同步中…" : savedAt ? `已同步 ${savedAt}` : "每 10 秒自动同步"}
                </span>
              </div>
              <div className="mt-2 h-2 overflow-hidden rounded-full bg-rice-100">
                <div
                  className="h-full rounded-full bg-bamboo-500 transition-all"
                  style={{ width: `${progressPct}%` }}
                />
              </div>
              <div className="mt-3 flex gap-2">
                {neighbor.prev && (
                  <button
                    onClick={() => neighbor.prev && goLesson(neighbor.prev.id)}
                    className="flex-1 rounded-lg border border-rice-200 bg-white px-4 py-2 text-sm text-ink-600 transition hover:border-cinnabar-500"
                  >
                    ← 上一课
                  </button>
                )}
                <button
                  onClick={markDone}
                  disabled={saving || progressPct >= 100}
                  className="flex-1 rounded-lg bg-bamboo-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-bamboo-600 disabled:opacity-50"
                >
                  {progressPct >= 100 ? "已学完 ✓" : "标记已学完"}
                </button>
                {neighbor.next && (
                  <button
                    onClick={() => neighbor.next && goLesson(neighbor.next.id)}
                    className="flex-1 rounded-lg bg-cinnabar-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-cinnabar-600"
                  >
                    下一课 →
                  </button>
                )}
              </div>
            </div>
          </div>

          {/* 章节侧边栏 */}
          <aside className="h-fit rounded-2xl border border-rice-200 bg-white p-4">
            <h2 className="font-song text-sm font-semibold tracking-widest text-ink-900">本课所在课程</h2>
            <p className="mt-1 truncate text-sm text-ink-600">{courseTitle}</p>
            <div className="mt-3 max-h-[60vh] space-y-1 overflow-y-auto">
              {flatLessons.map((ls) => (
                <button
                  key={ls.id}
                  onClick={() => goLesson(ls.id)}
                  className={`block w-full truncate rounded-md px-3 py-2 text-left text-sm transition ${
                    ls.id === lessonId
                      ? "bg-cinnabar-500 font-medium text-white"
                      : "text-ink-600 hover:bg-rice-100"
                  }`}
                >
                  {ls.title}
                </button>
              ))}
            </div>
            <Link
              href="/my-learning"
              className="mt-3 block text-center text-sm text-cinnabar-600 hover:underline"
            >
              前往我的学习 →
            </Link>
          </aside>
        </div>
      )}
    </main>
  );
}

export default function LearnPage() {
  return (
    <Suspense
      fallback={
        <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
          <div className="skeleton h-7 w-1/3 rounded" />
        </main>
      }
    >
      <LearnInner />
    </Suspense>
  );
}
