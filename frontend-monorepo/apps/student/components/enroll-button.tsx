"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { useAuth } from "@/app/auth-context";
import { PUBLIC_TENANT } from "@/app/courses/page";
import {
  enrollInCourse,
  myEnrollments,
  type AshRpcError,
} from "@tcm-edu/rpc-client";

function errMsg(errors: AshRpcError[]): string {
  return errors?.[0]?.message ?? "操作失败，请稍后重试";
}

/**
 * 选课 CTA：未登录→登录提示；已选课→继续学习；未选课→确认后 enroll。
 * `firstLessonId` 用于组装继续学习链接（无课时则进详情）。
 */
export default function EnrollButton({
  courseId,
  courseTitle,
  firstLessonId,
}: {
  courseId: string;
  courseTitle: string;
  firstLessonId?: string | null;
}) {
  const router = useRouter();
  const { isAuthenticated } = useAuth();
  const [checking, setChecking] = useState(true);
  const [enrolled, setEnrolled] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const check = useCallback(async () => {
    if (!isAuthenticated) {
      setChecking(false);
      return;
    }
    setChecking(true);
    try {
      const res = await myEnrollments({ fields: ["id", "courseId", "status"] });
      if (res.success) {
        setEnrolled(
          (res.data as { courseId: string; status: string }[]).some(
            (e) => e.courseId === courseId && e.status === "active"
          )
        );
      }
    } finally {
      setChecking(false);
    }
  }, [isAuthenticated, courseId]);

  useEffect(() => {
    check();
  }, [check]);

  async function handleEnroll() {
    setSubmitting(true);
    setError(null);
    try {
      const res = await enrollInCourse({
        fields: ["id", "status"],
        tenant: PUBLIC_TENANT,
        input: { courseId },
      });
      if (res.success) {
        setEnrolled(true);
        setConfirming(false);
        if (firstLessonId) {
          router.push(`/learn?course=${courseId}&lesson=${firstLessonId}`);
        }
      } else {
        setError(errMsg(res.errors));
      }
    } catch {
      setError("网络错误，请稍后重试");
    } finally {
      setSubmitting(false);
    }
  }

  const learnHref = firstLessonId
    ? `/learn?course=${courseId}&lesson=${firstLessonId}`
    : `/learn?course=${courseId}`;

  if (checking) {
    return (
      <div className="skeleton h-11 w-full rounded-lg" aria-label="加载中" />
    );
  }

  if (!isAuthenticated) {
    return (
      <Link
        href="/login"
        className="block rounded-lg bg-cinnabar-500 px-6 py-3 text-center text-sm font-medium text-white transition hover:bg-cinnabar-600"
      >
        登录后学习
      </Link>
    );
  }

  if (enrolled) {
    return (
      <Link
        href={learnHref}
        className="block rounded-lg bg-bamboo-500 px-6 py-3 text-center text-sm font-medium text-white transition hover:bg-bamboo-600"
      >
        继续学习
      </Link>
    );
  }

  return (
    <div>
      {!confirming ? (
        <button
          onClick={() => setConfirming(true)}
          className="w-full rounded-lg bg-cinnabar-500 px-6 py-3 text-sm font-medium text-white transition hover:bg-cinnabar-600"
        >
          立即学习
        </button>
      ) : (
        <div className="rounded-lg border border-rice-200 bg-rice-50 p-3">
          <p className="text-sm text-ink-900">
            确认选课《{courseTitle}》吗？选课后可在「我的学习」中找到它。
          </p>
          <div className="mt-3 flex gap-2">
            <button
              onClick={handleEnroll}
              disabled={submitting}
              className="flex-1 rounded-lg bg-cinnabar-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-cinnabar-600 disabled:opacity-50"
            >
              {submitting ? "选课中…" : "确认选课"}
            </button>
            <button
              onClick={() => {
                setConfirming(false);
                setError(null);
              }}
              className="flex-1 rounded-lg border border-rice-200 bg-white px-4 py-2 text-sm text-ink-600 transition hover:border-cinnabar-500"
            >
              再想想
            </button>
          </div>
        </div>
      )}
      {error && <p className="mt-2 text-sm text-cinnabar-700">{error}</p>}
    </div>
  );
}
